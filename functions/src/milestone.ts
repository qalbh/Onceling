import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Firestore } from "firebase-admin/firestore";

import { send } from "./notify.js";
import { daysBetweenKeys, localDateKey, usableTimezone } from "./timezone.js";

if (getApps().length === 0) initializeApp();

/**
 * **P3-03** — milestones at day 100, 365, 500 and 1000.
 *
 * Counted from `anniversaryDate`, not from posting. Q2's grace days and streak
 * breaks do not touch these: a couple whose streak died at day 40 still hits
 * day 100 together, because the milestone measures the relationship, not the
 * app usage.
 */
export const MILESTONE_DAYS = [100, 365, 500, 1000];

/**
 * Days from the anniversary to now, in the couple's own timezone.
 *
 * Calendar dates, not instants — the same rule as the streak boundary, using
 * the same helpers, so the two features cannot disagree about when a couple's
 * day ticks over. A milestone that fires at the wrong local midnight is worse
 * than one that fires late.
 *
 * @param {Date} anniversary the couple's day zero
 * @param {string} timezone an IANA zone, already validated
 * @param {Date} now the current instant
 * @return {number} whole days elapsed; negative if the anniversary is ahead
 */
export function daysSinceAnniversary(
  anniversary: Date,
  timezone: string,
  now: Date,
): number {
  return daysBetweenKeys(
    localDateKey(anniversary, timezone),
    localDateKey(now, timezone),
  );
}

/**
 * The highest milestone at or below [daysSince], or null below the first.
 *
 * @param {number} daysSince whole days since the anniversary
 * @return {number | null} the milestone day, or null
 */
export function highestCrossed(daysSince: number): number | null {
  let crossed: number | null = null;
  for (const day of MILESTONE_DAYS) {
    if (daysSince >= day) crossed = day;
  }
  return crossed;
}

/**
 * The words for one milestone — the push and the feed item share them.
 *
 * Same register as the onboarding: plain, warm, nothing shouted. Both partners
 * receive the identical text, because neither of them caused this.
 *
 * @param {number} day the milestone
 * @return {{title: string, body: string}} what the lock screen shows
 */
export function milestoneCopy(day: number): { title: string; body: string } {
  const body =
    {
      100: "One hundred days of the two of you.",
      365: "A whole year. Every day of it yours.",
      500: "Five hundred days, still choosing each other.",
      1000: "A thousand days of the two of you. Imagine that.",
    }[day] ?? `${day} days of the two of you.`;
  return { title: `Day ${day}`, body };
}

/** The deterministic feed-item id for a couple's milestone.
 *
 * Deterministic on purpose: even if two ticks raced past the transaction's
 * check, they would write the SAME document rather than a duplicate. The item
 * is written once per couple, never once per partner — it belongs to the
 * couple, and the id has no member in it.
 *
 * @param {string} coupleId the couple
 * @param {number} day the milestone
 * @return {string} the items/ document id
 */
export function milestoneItemId(coupleId: string, day: number): string {
  return `${coupleId}-milestone-${day}`;
}

/**
 * Fires the milestone crossing for one couple, if there is one. Idempotent.
 *
 * **The record is `milestoneCelebrated` on the couple document** — a single
 * integer, the highest day already celebrated. One monotonic field rather than
 * an array of fired days, because the firing rule collapses to one comparison
 * (`crossed > celebrated`) and the backdate decision below falls out of the
 * same shape instead of needing its own bookkeeping. Clients cannot forge it:
 * `couples` is closed to client writes entirely.
 *
 * **Backdated anniversaries fire the HIGHEST crossed milestone only.** M-10
 * defaults the anniversary to the pairing date, but P2-39 will let it be
 * edited — a couple three years in sets their real date and instantly crosses
 * 100, 365, 500 and 1000. Three pushes at once is spam; four same-timestamp
 * feed items is clutter pretending to be history; silence loses a real moment.
 * The one statement that is TRUE TODAY is the biggest one — "a thousand days"
 * — so that fires, and everything beneath it is marked spent, never to fire
 * late. The same principle covers an app dormant across two milestones: the
 * moment shown is the one that is current, and the skipped one is not
 * back-filled.
 *
 * **Exactly-once, structurally.** The check-and-set runs in a transaction that
 * re-reads the couple, so two overlapping ticks cannot both pass the
 * comparison; the feed item is created in that same transaction at a
 * deterministic id, so even a bug upstream of the check could not produce a
 * second document. The pushes happen after the commit — a crash between
 * commit and send loses a push but can never double-fire the milestone.
 *
 * @param {Firestore} db the admin handle
 * @param {string} coupleId the couple
 * @param {Date} now the current instant
 * @return {Promise<{day: number, recipients: string[]} | null>} what fired
 */
export async function celebrateMilestone(
  db: Firestore,
  coupleId: string,
  now: Date = new Date(),
): Promise<{ day: number; recipients: string[] } | null> {
  const ref = db.doc(`couples/${coupleId}`);

  const fired = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return null;
    const data = snap.data() ?? {};

    // A separated couple's milestones are as meaningless as its streak.
    if (data.status === "unpaired") return null;

    // No anniversary, no day count. Couples from before M-10 are in this
    // state permanently and must not crash the tick — P2-39's edit path is
    // what will give them a day zero.
    const anniversary = data.anniversaryDate?.toDate?.() as Date | undefined;
    if (anniversary == null) return null;

    const timezone = usableTimezone(data.timezone);
    const crossed = highestCrossed(
      daysSinceAnniversary(anniversary, timezone, now),
    );
    const celebrated = (data.milestoneCelebrated as number | undefined) ?? 0;
    if (crossed == null || crossed <= celebrated) return null;

    t.update(ref, { milestoneCelebrated: crossed });
    t.set(db.doc(`items/${milestoneItemId(coupleId, crossed)}`), {
      coupleId,
      type: "milestone",
      day: crossed,
      reactions: {},
      createdAt: FieldValue.serverTimestamp(),
      // Deliberately NO senderId. A milestone has no author, and the absence
      // is load-bearing three times over: `notifyOnItem` returns early on a
      // missing senderId (so this cannot cause a one-sided push), P3-02's
      // postsByDay skips it (a milestone is not somebody posting, so it can
      // never extend a streak), and the feed renders it centred because it
      // belongs to neither side.
    });
    return crossed;
  });

  if (fired == null) return null;

  // Pushes after the commit, to BOTH partners. Every other notification in
  // this app excludes the actor; a milestone has no actor, so for the first
  // time there is nobody to exclude. Neither caused it. Both get it.
  const couple = (await ref.get()).data() ?? {};
  const members = (couple.memberIds ?? []) as string[];
  const copy = milestoneCopy(fired);

  const recipients: string[] = [];
  for (const uid of members) {
    const profile = await db.doc(`users/${uid}`).get();
    const token = (profile.data()?.pushToken as string | undefined) ?? null;
    if (token == null) continue;
    recipients.push(uid);
    // Fixed copy, no user content — the recipient's preview setting gates
    // previews of what a PERSON wrote, and nobody wrote this.
    await send(db, { uid, token, previews: false }, copy, {
      kind: "milestone",
      day: `${fired}`,
    });
  }

  return { day: fired, recipients };
}
