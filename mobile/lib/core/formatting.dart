import 'package:intl/intl.dart';

final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');

String formatDate(DateTime? value) {
  if (value == null) return 'Not set';
  return _dayMonthYear.format(value.toLocal());
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String percentLabel(double? value) {
  if (value == null) return 'Not scored';
  return '${(value * 100).round()}% heuristic score';
}
