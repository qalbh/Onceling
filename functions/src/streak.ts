import { getApps, initializeApp } from "firebase-admin/app";
import { Firestore, Timestamp, getFirestore } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { celebrateMilestone } from "./milestone.js";
import { sweepExpiredRequests } from "./pairing.js";
import { sweepStuckCouples } from "./unpair.js";
import {
  daysBetweenKeys,
  localDateKey,
  shiftKey,
  usableTimezone,
} from "./timezone.js";

if (getApps().length === 0) initializeApp();

/**
 * **What counts as "posted"** — every item type, and only item types.
 *
 * Brief §6 says a streak day is one where both partners posted. The five types
 * are text, photo, emoji, status and secret, and all five are a person choosing
 * to put something in the shared thread:
 *
 * - `text`, `photo`, `secret` — unambiguous.
 * - `emoji` — a tray tap is low effort, but a streak measures *reaching out*,
 *   not effort. A couple who sent each other hearts all day plainly showed up,
 *   and telling them they did not would be indefensible.
 * - `status` — a mood. The closest call, because it is authored about yourself
 *   rather than to your partner. It counts because it lands in their thread and
 *   they read it: someone who told their partner how they were doing that day
 *   has not "failed to post" in any sense a person would accept. Brief §12
 *   flags coercion risk in streaks, which argues for the forgiving reading
 *   wherever the line is genuinely unclear.
 *
 * **Reactions deliberately do not count**, and they are the sharp edge here.
 * A reaction is not an item at all — it is a field on the *other* person's
 * message. Replying to someone is not the same as reaching out to them, and a
 * streak that could be kept alive purely by tapping ❤️ on whatever arrived
 * would measure attendance rather than contact.
 */
export const POSTING_TYPES = ["text", "photo", "emoji", "status", "secret"];

/**
 * **Q2: one grace day per rolling seven days.**
 *
 * Rolling rather than a fixed week boundary. A fixed boundary creates a cliff
 * nobody could explain: miss Saturday and Sunday and the streak dies, miss
 * Sunday and Monday and it survives, purely because an invisible line sits
 * between them. Rolling means the promise is simply true — there is always one
 * forgiveness available per week — at the cost of storing the date the last
 * grace was spent rather than a counter that resets.
 */
export const GRACE_PERIOD_DAYS = 7;

/** Days evaluated per scheduled run. A backlog drains over subsequent ticks. */
export const MAX_DAYS_PER_RUN = 40;

/** Days a full recalculation replays. Bounds the repair path's cost. */
export const MAX_RECALC_DAYS = 400;

/** Couples examined per scheduled tick. */
export const COUPLE_BATCH = 200;

/**
 * The streak, as stored on `couples/{id}`.
 *
 * **Dates are calendar-date keys (`YYYY-MM-DD`), not timestamps.** A timestamp
 * would be ambiguous about whose midnight it meant, which is the entire problem
 * Q3 exists to solve. Stored as strings so they sort and compare directly.
 */
export interface StreakState {
  /** Days both partners posted, consecutively (grace days excepted). */
  streakCount: number;

  /** Last day that counted toward the streak. Null before the first one. */
  lastStreakDate: string | null;

  /** When the rolling grace was last spent. Null if never. */
  lastGraceDate: string | null;

  /**
   * The day the streak broke, or null while healthy.
   *
   * **This is "faded, not zeroed" in the data.** `streakCount` is deliberately
   * left at its last value when a streak breaks, and this field is what tells
   * the UI to render it faded. Zeroing would erase the history for having been
   * interrupted, which Q2 explicitly rules out; a separate "previous count"
   * field would say the same thing while letting the two drift apart.
   */
  streakBrokenAt: string | null;

  /**
   * Last local day evaluated. **This is what makes the daily run idempotent** —
   * a second tick for the same day finds nothing to do, so the count cannot be
   * incremented twice. Distinct from `lastStreakDate`, because a day that did
   * not count still must not be evaluated again.
   */
  streakEvaluatedThrough: string | null;
}

export const emptyStreak: StreakState = {
  streakCount: 0,
  lastStreakDate: null,
  lastGraceDate: null,
  streakBrokenAt: null,
  streakEvaluatedThrough: null,
};

/**
 * Advances [state] across [days] in order. Pure — no clock, no database.
 *
 * Being pure is what makes idempotency structural rather than asserted: the
 * same days and the same starting state always give the same answer, so the
 * repair path and the daily path cannot disagree about how a streak is scored.
 *
 * [postedOn] maps a date key to the set of uids that posted that day.
 */
export function replayStreak(
  state: StreakState,
  days: string[],
  postedOn: (day: string) => Set<string>,
  members: string[],
): StreakState {
  let next: StreakState = { ...state };

  for (const day of days) {
    const posters = postedOn(day);
    // Brief §6: BOTH partners. One person posting alone does not extend it.
    const bothPosted =
      members.length >= 2 && members.every((m) => posters.has(m));

    if (bothPosted) {
      next = {
        ...next,
        // A broken streak restarts at one rather than resuming. The old number
        // stays visible until this moment precisely so it is not erased; once
        // they are back, the run that is running is a new one.
        streakCount: next.streakBrokenAt != null ? 1 : next.streakCount + 1,
        lastStreakDate: day,
        streakBrokenAt: null,
      };
    } else if (next.streakBrokenAt != null) {
      // Already broken. Stays broken and stays faded until they post together.
    } else if (next.streakCount === 0) {
      // Nothing to protect yet — a couple who has not started cannot break.
    } else {
      const graceAvailable =
        next.lastGraceDate == null ||
        daysBetweenKeys(next.lastGraceDate, day) >= GRACE_PERIOD_DAYS;

      next = graceAvailable
        // Spent: the count survives but does not grow. `lastStreakDate` is
        // untouched, because no one posted — the streak is alive, not extended.
        ? { ...next, lastGraceDate: day }
        // The grace was already used inside the last seven days.
        : { ...next, streakBrokenAt: day };
    }

    next = { ...next, streakEvaluatedThrough: day };
  }

  return next;
}

/** Reads the couple's posting history over a span, bucketed by local day. */
async function postsByDay(
  db: Firestore,
  coupleId: string,
  timezone: string,
  firstDay: string,
  lastDay: string,
): Promise<Map<string, Set<string>>> {
  // A local day spans at most 26 hours of UTC, so a one-day cushion on each
  // side certainly contains the whole range. The precise assignment is done
  // below by local date key, not by this window.
  const from = new Date(`${shiftKey(firstDay, -1)}T00:00:00Z`);
  const to = new Date(`${shiftKey(lastDay, 2)}T00:00:00Z`);

  // INDEX: items — coupleId ASC + createdAt **ASC**.
  //
  // Not the same index the feed uses. The feed asks for `createdAt DESC`; this
  // is a range with no explicit orderBy, so Firestore sorts ASCENDING, and
  // composite index directions are not interchangeable. Declared separately in
  // `firestore.indexes.json` for exactly that reason.
  //
  // Found at **P2-16**, the first real deploy: the emulator does not enforce
  // indexes, so this query had never once run somewhere that could tell it the
  // index was missing. It would have failed on every scheduled tick in
  // production. That is what **D-10** was warning about.
  const snap = await db
    .collection("items")
    .where("coupleId", "==", coupleId)
    .where("createdAt", ">=", Timestamp.fromDate(from))
    .where("createdAt", "<", Timestamp.fromDate(to))
    .get();

  const byDay = new Map<string, Set<string>>();
  for (const docSnap of snap.docs) {
    const data = docSnap.data();
    if (!POSTING_TYPES.includes(data.type)) continue;

    const createdAt = data.createdAt as Timestamp | undefined;
    const senderId = data.senderId as string | undefined;
    if (createdAt == null || senderId == null) continue;

    const day = localDateKey(createdAt.toDate(), timezone);
    const posters = byDay.get(day) ?? new Set<string>();
    posters.add(senderId);
    byDay.set(day, posters);
  }
  return byDay;
}

/** Inclusive list of date keys from [from] to [to], capped at [max]. */
function dayRange(from: string, to: string, max: number): string[] {
  const span = daysBetweenKeys(from, to);
  if (span < 0) return [];
  const days: string[] = [];
  for (let i = 0; i <= Math.min(span, max - 1); i++) {
    days.push(shiftKey(from, i));
  }
  return days;
}

/**
 * Reads the stored streak, defaulting every field.
 *
 * @param {FirebaseFirestore.DocumentData} data the couple document
 * @return {StreakState} the state, with absent fields at their zero value
 */
function readState(data: FirebaseFirestore.DocumentData): StreakState {
  return {
    streakCount: (data.streakCount as number | undefined) ?? 0,
    lastStreakDate: (data.lastStreakDate as string | null | undefined) ?? null,
    lastGraceDate: (data.lastGraceDate as string | null | undefined) ?? null,
    streakBrokenAt: (data.streakBrokenAt as string | null | undefined) ?? null,
    streakEvaluatedThrough:
      (data.streakEvaluatedThrough as string | null | undefined) ?? null,
  };
}

/** The couple's first meaningful day: anniversary, else their creation. */
function firstDayOf(
  data: FirebaseFirestore.DocumentData,
  timezone: string,
  fallback: Date,
): string {
  const anniversary = data.anniversaryDate as Timestamp | undefined;
  const created = data.createdAt as Timestamp | undefined;
  const start = anniversary?.toDate() ?? created?.toDate() ?? fallback;
  return localDateKey(start, timezone);
}

/**
 * **P3-02** — brings one couple's streak up to date.
 *
 * **Incremental, not a full recalculation on every tick.** The trade the task
 * names is real: recalculating from history is self-healing, incrementing is
 * cheap. This increments, because a daily full replay of every couple's entire
 * thread is a collection read per couple per day that grows without bound, for
 * a number that changes by at most one.
 *
 * **How a wrong count gets fixed:** [recalculateStreak] replays from history
 * and overwrites. It shares the same pure [replayStreak] core, so the repair
 * cannot disagree with the daily path about the rules — only about how far back
 * it looked. That is the self-healing property, kept as an explicit operation
 * rather than paid for on every tick.
 */
export async function evaluateStreakForCouple(
  db: Firestore,
  coupleId: string,
  now: Date = new Date(),
): Promise<{ evaluated: number; state: StreakState } | null> {
  const ref = db.doc(`couples/${coupleId}`);
  const snap = await ref.get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  // A separated couple's streak is meaningless and its data is being swept.
  if (data.status === "unpaired") return null;

  const timezone = usableTimezone(data.timezone);
  const members = (data.memberIds ?? []) as string[];
  const state = readState(data);

  // **P3-03** rides this tick rather than walking `couples` a second time —
  // a second scheduled sweep would double D-20's read cost to learn nothing
  // this one does not already know. The check is pure arithmetic against a
  // document this function has already read, so it costs nothing until a
  // milestone actually fires; its own transaction re-reads before writing, so
  // sharing the tick adds no race. Isolated so a milestone failure cannot
  // stop the streak from being scored, or vice versa.
  try {
    await celebrateMilestone(db, coupleId, now);
  } catch (err) {
    console.warn(`[P3-03] milestone failed for ${coupleId}: ${err}`);
  }

  // Only completed days are scored. Today is still in progress — evaluating it
  // would break every streak at midnight and mend it again when someone posts.
  const yesterday = shiftKey(localDateKey(now, timezone), -1);

  const from =
    state.streakEvaluatedThrough != null
      ? shiftKey(state.streakEvaluatedThrough, 1)
      : firstDayOf(data, timezone, now);

  const days = dayRange(from, yesterday, MAX_DAYS_PER_RUN);
  if (days.length === 0) return { evaluated: 0, state };

  const byDay = await postsByDay(
    db,
    coupleId,
    timezone,
    days[0],
    days[days.length - 1],
  );
  const next = replayStreak(
    state,
    days,
    (day) => byDay.get(day) ?? new Set<string>(),
    members,
  );

  await ref.update({ ...next });
  return { evaluated: days.length, state: next };
}

/**
 * The repair path: replays from the couple's beginning and overwrites.
 *
 * Bounded at [MAX_RECALC_DAYS] so one pathological couple cannot make this
 * unbounded; a streak older than that keeps whatever the daily path computed
 * for the days before the window, which is the honest limit of a bounded
 * replay rather than a silent truncation.
 */
export async function recalculateStreak(
  db: Firestore,
  coupleId: string,
  now: Date = new Date(),
): Promise<StreakState | null> {
  const ref = db.doc(`couples/${coupleId}`);
  const snap = await ref.get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  const timezone = usableTimezone(data.timezone);
  const members = (data.memberIds ?? []) as string[];

  const yesterday = shiftKey(localDateKey(now, timezone), -1);
  const earliest = firstDayOf(data, timezone, now);
  const windowStart = shiftKey(yesterday, -(MAX_RECALC_DAYS - 1));
  const from = earliest > windowStart ? earliest : windowStart;

  const days = dayRange(from, yesterday, MAX_RECALC_DAYS);
  if (days.length === 0) {
    await ref.update({ ...emptyStreak });
    return emptyStreak;
  }

  const byDay = await postsByDay(
    db,
    coupleId,
    timezone,
    days[0],
    days[days.length - 1],
  );
  const next = replayStreak(
    emptyStreak,
    days,
    (day) => byDay.get(day) ?? new Set<string>(),
    members,
  );

  await ref.update({ ...next });
  return next;
}

/**
 * Every couple whose local yesterday is not yet scored.
 *
 * **Hourly, not daily, and that is how the timezone problem is solved.** A
 * streak day ends at the couple's own midnight, and couples in different zones
 * do not share one. Rather than trying to fire a cron per zone, the tick runs
 * often and the *evaluation* is idempotent and keyed on the couple's local
 * date: a couple is scored within an hour of their own midnight, and a couple
 * already scored for that day is a no-op. Frequency becomes an implementation
 * detail instead of a correctness property.
 */
export async function sweepStreaks(
  db: Firestore,
  now: Date = new Date(),
): Promise<{ examined: number; updated: number }> {
  const couples = await db.collection("couples").limit(COUPLE_BATCH).get();

  let updated = 0;
  for (const docSnap of couples.docs) {
    try {
      const result = await evaluateStreakForCouple(db, docSnap.id, now);
      if (result != null && result.evaluated > 0) updated++;
    } catch (err) {
      // One couple must not stop the pass.
      console.warn(`[P3-02] streak failed for ${docSnap.id}: ${err}`);
    }
  }
  return { examined: couples.size, updated };
}

/**
 * Everything the hourly tick carries, in one place (**P3-02**, **P2-28**,
 * **P2-38** — and **P3-03**, which rides inside the streak evaluation).
 *
 * One schedule, several sweeps: each additional scheduled function walking
 * its own query would compound **D-20**'s read cost for nothing, and the
 * jobs are all the same shape — idempotent cleanup that tolerates running an
 * hour late. Each is isolated so one failing cannot starve the others.
 *
 * Exported so a test can run the tick as deployed, clock injected, rather
 * than asserting three functions that might not actually be wired.
 *
 * @param {Firestore} db the admin handle
 * @param {Date} now the current instant
 * @return {Promise<void>} nothing — each job logs its own outcome
 */
export async function runHourlyTick(
  db: Firestore,
  now: Date = new Date(),
): Promise<void> {
  try {
    const result = await sweepStreaks(db, now);
    if (result.updated > 0) {
      console.log(
        `[P3-02] scored ${result.updated} couple(s) of ${result.examined}.`,
      );
    }
  } catch (err) {
    console.error(`[P3-02] streak sweep failed: ${err}`);
  }

  try {
    const result = await sweepExpiredRequests(db, now);
    if (result.expired > 0) {
      console.log(`[P2-28] expired ${result.expired} stale request(s).`);
    }
  } catch (err) {
    console.error(`[P2-28] request sweep failed: ${err}`);
  }

  try {
    // Logs its own firings, loudly — a silent backstop tells you nothing
    // about how often the primary fails.
    await sweepStuckCouples(db, now);
  } catch (err) {
    console.error(`[P2-38] backstop failed: ${err}`);
  }
}

export const updateStreaksScheduled = onSchedule(
  // The deployed name predates the tick carrying more than streaks; renaming
  // a live scheduled function is delete-and-recreate churn for cosmetics.
  { schedule: "every 1 hours", retryCount: 3 },
  async () => {
    await runHourlyTick(getFirestore());
  },
);
