/// Formats a UTC [DateTime] in the device's own local time. Every
/// reservation/chore timestamp from the backend is UTC; this is the one
/// place that converts it for display, so "4:00" shown to a user always
/// means their own device's 4:00.
extension LocalTimeFormat on DateTime {
  String toLocalTimeLabel() {
    final local = toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  String toLocalDateLabel() {
    final local = toLocal();
    final now = DateTime.now();
    final isToday =
        local.year == now.year && local.month == now.month && local.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        local.year == tomorrow.year && local.month == tomorrow.month && local.day == tomorrow.day;
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }

  String toLocalDateTimeLabel() => '${toLocalDateLabel()}, ${toLocalTimeLabel()}';
}
