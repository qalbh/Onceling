/// The words for each milestone (**P3-03**).
///
/// **A hand-kept mirror of `milestoneCopy` in `functions/src/milestone.ts`** —
/// Dart and TypeScript cannot share a constant, so this is the same D-17 shape
/// as the pairing-code alphabet and the item payloads. The push comes from the
/// TS copy; the feed line and the full-screen moment come from this one. If
/// they drift, the lock screen and the app disagree about the same moment.
///
/// Register: the onboarding's. Plain, warm, nothing shouted, no exclamation
/// marks. Both partners read the identical words, because neither of them
/// caused this.
library;

/// The milestones, in order. Mirrors `MILESTONE_DAYS` in TypeScript.
const milestoneDays = [100, 365, 500, 1000];

/// The single line under the day number.
String milestoneLine(int day) => switch (day) {
  100 => 'One hundred days of the two of you.',
  365 => 'A whole year. Every day of it yours.',
  500 => 'Five hundred days, still choosing each other.',
  1000 => 'A thousand days of the two of you. Imagine that.',
  // A day this build does not know: a future milestone added server-side
  // first. Degrade to something true rather than crashing the feed on it.
  _ => '$day days of the two of you.',
};
