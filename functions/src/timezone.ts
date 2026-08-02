/**
 * Timezone handling for **Q3** (**P2-40**) and the streak boundary (**P3-02**).
 *
 * Everything here works in *calendar dates*, not instants. A streak day is a
 * day on somebody's wall calendar, and "which day is it" is only answerable
 * once you know whose midnight you mean — which is exactly why Q3 had to be
 * decided before P3-02 could be built.
 */

/**
 * Used when a couple has no usable timezone.
 *
 * Every couple paired before **P2-40** has `timezone: null`, and there is no
 * migration by design. The alternative to a fallback is skipping those couples
 * entirely, which would mean their streak silently never moves — indefinitely,
 * invisibly, and looking exactly like a bug. A wrong-by-a-few-hours boundary is
 * a far smaller harm than a feature that quietly does not run, and **P2-39**'s
 * edit path fixes it properly.
 */
export const FALLBACK_TIMEZONE = "UTC";

/** Longest accepted zone name. Real ones are well under this. */
const MAX_TIMEZONE_LENGTH = 64;

/**
 * IANA names only: `Region/City`, or the bare `UTC`.
 *
 * **This pattern is the point of the whole function.** `Intl.DateTimeFormat`
 * happily accepts `+05:00` and `-0800` as timeZone values, so validating with
 * Intl alone would let a UTC offset through — and an offset is exactly what Q3
 * rules out, because it is wrong for half the year anywhere that observes DST.
 * The anchored pattern rejects anything starting with a sign or digit.
 */
const IANA_NAME = /^(?:UTC|[A-Za-z][A-Za-z0-9_+-]*(?:\/[A-Za-z0-9_+-]+)+)$/;

/**
 * Validates a client-supplied zone, returning null for anything unusable.
 *
 * **Returns null rather than throwing, on purpose.** This is called from
 * `respondToPairing`, and failing an accept because a device could not name its
 * own timezone would sacrifice the flow brief §11 calls the single most
 * important metric for a field nothing reads until the next daily tick. The
 * couple pairs; the zone is null; [FALLBACK_TIMEZONE] covers it.
 */
export function normaliseTimezone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_TIMEZONE_LENGTH) return null;
  if (!IANA_NAME.test(trimmed)) return null;

  // Second gate: the runtime must actually be able to compute with it. Using
  // the same mechanism P3-02 uses for the day boundary means a zone that
  // validates here cannot fail there.
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: trimmed }).format(new Date());
  } catch {
    return null;
  }
  return trimmed;
}

/** [normaliseTimezone] with the fallback applied. Never returns null. */
export function usableTimezone(value: unknown): string {
  return normaliseTimezone(value) ?? FALLBACK_TIMEZONE;
}

/**
 * The calendar date an instant falls on, in [timezone], as `YYYY-MM-DD`.
 *
 * `en-CA` because it formats as `2026-08-03` — ISO order, zero-padded, so the
 * strings sort chronologically and compare with `<`. That property is load
 * bearing: `streakEvaluatedThrough >= yesterday` is a string comparison.
 */
export function localDateKey(instant: Date, timezone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/** A date key as milliseconds, treating it as a UTC midnight. */
function keyToMillis(key: string): number {
  const [year, month, day] = key.split("-").map(Number);
  return Date.UTC(year, month - 1, day);
}

/**
 * Whole days from [from] to [to]. Negative when [to] is earlier.
 *
 * Safe against DST because both keys are anchored to UTC midnight first — the
 * arithmetic is on calendar dates, which have no offset, rather than on
 * instants, which do.
 */
export function daysBetweenKeys(from: string, to: string): number {
  return Math.round((keyToMillis(to) - keyToMillis(from)) / 86_400_000);
}

/** The date key [days] after [key]. Negative shifts backwards. */
export function shiftKey(key: string, days: number): string {
  const shifted = new Date(keyToMillis(key) + days * 86_400_000);
  const month = `${shifted.getUTCMonth() + 1}`.padStart(2, "0");
  const day = `${shifted.getUTCDate()}`.padStart(2, "0");
  return `${shifted.getUTCFullYear()}-${month}-${day}`;
}
