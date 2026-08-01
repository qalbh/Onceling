/// Clock time as the feed shows it: `8:12 AM`, `2:14 PM`.
///
/// Deliberately hand-rolled rather than pulling in `intl` — the feed shows one
/// format, and a dependency for it would be its own maintenance surface.
String formatClockTime(DateTime time) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A calendar date as the header reads it: `4 November 2023`.
///
/// Hand-rolled for the same reason as [formatClockTime] — one format, and
/// `intl` would be a maintenance surface for it. Day is unpadded: "4 November"
/// not "04 November".
String formatCalendarDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

/// Whole days between two dates, counted by calendar day rather than by
/// elapsed hours (**M-10**).
///
/// `DateTime.difference().inDays` truncates elapsed time, so an anniversary at
/// 11pm yesterday would read as 0 days until 11pm today. Normalising both ends
/// to midnight makes "days together" tick over at midnight, which is what the
/// number means to the people reading it.
///
/// Local time on purpose: whose midnight this is becomes a real question once
/// two people are in different zones, and that is **Q3**, still open. Until it
/// is answered each device counts by its own midnight.
int daysBetween(DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// Coarse "how long ago", for the pairing waiting state (**P2-24**).
///
/// Deliberately vague past an hour: the exact minute a request was sent is not
/// information anyone needs, and "3 days ago" reads better than a timestamp
/// while B is waiting.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);

  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) {
    final minutes = elapsed.inMinutes;
    return '$minutes minute${minutes == 1 ? '' : 's'} ago';
  }
  if (elapsed.inHours < 24) {
    final hours = elapsed.inHours;
    return '$hours hour${hours == 1 ? '' : 's'} ago';
  }
  final days = elapsed.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}
