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
