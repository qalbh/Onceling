import { getApps, initializeApp } from "firebase-admin/app";
import { Firestore, Timestamp, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { celebrateMilestone } from "./milestone.js";
import { daysBetweenKeys, localDateKey, usableTimezone } from "./timezone.js";

if (getApps().length === 0) initializeApp();

/**
 * **P2-39** — `setAnniversary(date)`, the settings edit path for **M-10**.
 *
 * A callable because `couples` denies every client write in every direction:
 * the collection that decides which milestones a couple has crossed is not
 * something an untrusted client edits. The date arrives as a bare calendar
 * key (`YYYY-MM-DD`) rather than an instant, because an anniversary is a day
 * on somebody's wall calendar — the same reasoning as the streak boundary —
 * and letting the client pick the instant would smuggle its timezone into a
 * field the couple's own zone should govern.
 */

/** How far back an anniversary may plausibly reach: 100 years, in days.
 *
 * The longest recorded marriages run a little past 85 years; a century
 * covers every living couple's relationship with margin, and anything
 * earlier is a typo — 1926 for 2026 — which silent acceptance would turn
 * into a couple on day 36,500 with every milestone spent. Rejecting it
 * loudly is the kinder failure. Also keeps the day count well inside the
 * rules' 100000 bound on `milestoneSeen`, so the two limits cannot cross.
 */
export const MAX_ANNIVERSARY_AGE_DAYS = 36525;

/** Shape of a calendar-date key. The parse below rejects impossible dates
 *  (2026-02-30); this only gates the format. */
const DATE_KEY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parses an untrusted calendar-date key, or returns null.
 *
 * Rejects rather than coerces: `2026-02-30` silently becoming March 2nd is
 * exactly the kind of helpfulness that writes a date the couple never chose.
 * The round-trip through `Date.UTC` is what catches impossible dates — the
 * components come back changed.
 *
 * @param {unknown} value the caller-supplied date
 * @return {string | null} the validated key, or null
 */
export function parseDateKey(value: unknown): string | null {
  if (typeof value !== "string" || !DATE_KEY.test(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  const roundTrip = new Date(Date.UTC(year, month - 1, day));
  if (
    roundTrip.getUTCFullYear() !== year ||
    roundTrip.getUTCMonth() !== month - 1 ||
    roundTrip.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

/**
 * An instant that falls on calendar day [key] in [timezone].
 *
 * **Why not just UTC midnight of the key:** `anniversaryDate` is stored as a
 * Timestamp and read back through `localDateKey(instant, coupleZone)` — by
 * the milestones, the streak's first-day fallback, and the client's day
 * counter. UTC midnight lands on the PREVIOUS local day anywhere west of
 * Greenwich, so a couple in Los Angeles picking August 8 would be stored a
 * day off from the date they chose.
 *
 * No single UTC hour works either: offsets span -12..+14, a 26-hour range.
 * So start at UTC noon and correct once in whichever direction the zone
 * pulled the date — one adjustment always suffices, because every offset is
 * within twelve hours of one of the two candidates.
 *
 * @param {string} key the calendar day wanted
 * @param {string} timezone the couple's IANA zone
 * @return {Date} an instant whose local date in [timezone] is [key]
 */
export function instantOnLocalDay(key: string, timezone: string): Date {
  const noon = new Date(`${key}T12:00:00Z`);
  const landed = localDateKey(noon, timezone);
  if (landed === key) return noon;

  const shiftHours = landed < key ? 12 : -12;
  return new Date(noon.getTime() + shiftHours * 3_600_000);
}

/**
 * The write itself, with the clock injected so tests can pin "today".
 *
 * **What an edit does to milestones — the three cases, decided:**
 *
 * **Earlier** (including onto a couple that had no date, the pre-M-10 case):
 * newly-crossed milestones fire through [celebrateMilestone], unchanged —
 * highest only, everything beneath marked spent. The couple being present
 * and watching makes that rule MORE right, not less: they just typed the
 * date, and a burst of four pushes would be the app narrating arithmetic
 * they performed themselves. One moment, the one that is true today. It also
 * means the edit is the first honest demo of P3-03 — the moment appears the
 * instant the date lands, not at the next hourly tick.
 *
 * **Later** (uncrossing a celebrated milestone): `milestoneCelebrated` does
 * NOT roll back. It is a record that a moment happened between these two
 * people, and it did happen — a rollback would re-fire day 365 on the second
 * crossing, and celebrating the same evening twice is worse than a history
 * that is simply true. Mechanically the record's integrity depends on this
 * too: the feed item `{coupleId}-milestone-365` exists, and a re-fire would
 * overwrite it, resetting its timestamp and wiping its reactions. Nothing in
 * this codebase writes `milestoneCelebrated` downward, by construction.
 *
 * **Streaks are untouched, verified rather than assumed:** the incremental
 * path resumes from `streakEvaluatedThrough` and never consults the
 * anniversary once that is set (`evaluateStreakForCouple`'s `from`); the
 * anniversary only seeds `firstDayOf` on a couple never yet evaluated, where
 * the extra pre-pairing days are empty and `replayStreak`'s
 * `streakCount === 0` branch scores them as nothing to protect. A test pins
 * the whole claim.
 *
 * @param {Firestore} db the admin handle
 * @param {string} uid the caller
 * @param {unknown} rawDate the caller-supplied date
 * @param {Date} now the current instant
 * @return {Promise<{date: string, milestone: number | null}>} what was set
 */
export async function applyAnniversary(
  db: Firestore,
  uid: string,
  rawDate: unknown,
  now: Date = new Date(),
): Promise<{ date: string; milestone: number | null }> {
  const key = parseDateKey(rawDate);
  if (key == null) {
    throw new HttpsError("invalid-argument", "That is not a date.", {
      reason: "date-invalid",
    });
  }

  // No coupleId parameter, deliberately. The couple is read from the
  // caller's own profile, so there is nothing to forge: the strongest form
  // of "a non-member cannot set another couple's anniversary" is an API in
  // which no other couple can be named.
  const profile = await db.doc(`users/${uid}`).get();
  const coupleId = profile.data()?.coupleId as string | null | undefined;
  if (coupleId == null) {
    throw new HttpsError("failed-precondition", "You are not paired.", {
      reason: "not-paired",
    });
  }

  await db.runTransaction(async (t) => {
    const ref = db.doc(`couples/${coupleId}`);
    const snap = await t.get(ref);
    const members = (snap.data()?.memberIds ?? []) as string[];
    if (!snap.exists || !members.includes(uid)) {
      throw new HttpsError("permission-denied", "That couple is not yours.", {
        reason: "not-a-member",
      });
    }
    if (snap.data()?.status === "unpaired") {
      throw new HttpsError("failed-precondition", "That couple has ended.", {
        reason: "unpaired",
      });
    }

    // Bounds are checked against TODAY IN THE COUPLE'S OWN ZONE, not UTC.
    // Just past their midnight, "today" is a future date by UTC's clock, and
    // rejecting a couple's actual anniversary because Greenwich has not
    // caught up would be the exact off-by-one Q3 exists to prevent.
    const timezone = usableTimezone(snap.data()?.timezone);
    const today = localDateKey(now, timezone);
    const age = daysBetweenKeys(key, today);
    if (age < 0) {
      throw new HttpsError("invalid-argument", "That day has not happened.", {
        reason: "date-future",
      });
    }
    if (age > MAX_ANNIVERSARY_AGE_DAYS) {
      throw new HttpsError("invalid-argument", "That is too long ago.", {
        reason: "date-too-old",
      });
    }

    // Idempotent by nature: the same key produces the same instant, and
    // writing a field to the value it already holds is a no-op in every way
    // that matters.
    t.update(ref, {
      anniversaryDate: Timestamp.fromDate(instantOnLocalDay(key, timezone)),
    });
  });

  // After the commit, never inside it: the milestone check runs its own
  // idempotent transaction, and a failure here must not unwind a date that
  // was validly set — the hourly tick will fire the milestone within the
  // hour anyway. This call only makes it immediate, which is what a couple
  // standing in settings deserves.
  let milestone: number | null = null;
  try {
    milestone = (await celebrateMilestone(db, coupleId, now))?.day ?? null;
  } catch (err) {
    console.warn(`[P2-39] milestone after edit failed for ${coupleId}: ${err}`);
  }

  return { date: key, milestone };
}

/** **P2-39** — the callable wrapper. All logic lives in [applyAnniversary],
 *  where a test can inject the clock. */
export const setAnniversary = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  return await applyAnniversary(getFirestore(), uid, request.data?.date);
});
