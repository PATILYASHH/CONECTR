import 'package:intl/intl.dart';

/// "Just now", "5 min ago", "Today, 9:40 AM", "Yesterday, 6:02 PM",
/// "Sep 3, 8:05 AM", or "Dec 31, 2025" — as close to "how long ago" as is
/// still useful.
String formatWhen(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final ago = current.difference(local);

  if (!ago.isNegative && ago < const Duration(minutes: 1)) return 'Just now';
  if (!ago.isNegative && ago < const Duration(hours: 1)) {
    return '${ago.inMinutes} min ago';
  }

  final clock = DateFormat.jm().format(local);
  // Calendar days compared in UTC so a DST change can't make "yesterday"
  // a 23-hour day that rounds to zero.
  final days = DateTime.utc(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
  if (days == 0) return 'Today, $clock';
  if (days == 1) return 'Yesterday, $clock';
  if (local.year == current.year) {
    return '${DateFormat.MMMd().format(local)}, $clock';
  }
  return DateFormat.yMMMd().format(local);
}
