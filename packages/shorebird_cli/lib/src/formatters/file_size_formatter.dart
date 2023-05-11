import 'dart:math';

String formatBytes(int bytes, {int decimals = 2}) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  final i = (log(bytes) / log(1024)).floor();
  final value = bytes / pow(1024, i);
  final suffix = suffixes[i];
  final formattedValue = value % 1 == 0 || decimals <= 0
      ? '${value.toInt()} $suffix'
      : '${value.toStringAsFixed(decimals)} $suffix';
  return formattedValue;
}
