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
