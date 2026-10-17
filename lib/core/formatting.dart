/// Human readable formatting helpers shared by the UI.
const List<String> _byteUnits = <String>[
  'B',
  'KiB',
  'MiB',
  'GiB',
  'TiB',
  'PiB',
];

/// Formats a byte count such as `1536` into `1.5 KiB`.
String formatBytes(int bytes, {int fractionDigits = 1}) {
  if (bytes < 0) {
    return '未知';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _byteUnits.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : fractionDigits;
  return '${value.toStringAsFixed(digits)} ${_byteUnits[unit]}';
}

/// Formats a transfer speed, for example `1.2 MiB/s`.
String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond <= 0) {
    return '0 B/s';
  }
  return '${formatBytes(bytesPerSecond)}/s';
}

/// Formats a duration as `hh:mm:ss` (or `Xd hh:mm` for long durations).
String formatDuration(Duration duration) {
  if (duration.inSeconds <= 0) {
    return '--';
  }
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  String two(int value) => value.toString().padLeft(2, '0');
  if (days > 0) {
    return '$days天 ${two(hours)}:${two(minutes)}';
  }
  return '${two(hours)}:${two(minutes)}:${two(seconds)}';
}

/// Formats an ETA given in seconds.
String formatEta(int seconds) => formatDuration(Duration(seconds: seconds));

/// Formats a 0..1 progress value as a percentage.
String formatPercent(double value) {
  final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
  return '${(clamped * 100).toStringAsFixed(1)}%';
}
