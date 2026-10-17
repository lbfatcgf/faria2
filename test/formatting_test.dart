import 'package:faria2/core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('formats small values as bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('formats binary units', () {
      expect(formatBytes(1024), '1.0 KiB');
      expect(formatBytes(1536), '1.5 KiB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MiB');
      expect(formatBytes(120 * 1024 * 1024 * 1024), '120 GiB');
    });

    test('marks negative values as unknown', () {
      expect(formatBytes(-1), '未知');
    });
  });

  group('speed and duration', () {
    test('formats speed', () {
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(2048), '2.0 KiB/s');
    });

    test('formats duration', () {
      expect(formatDuration(Duration.zero), '--');
      expect(formatDuration(const Duration(seconds: 65)), '00:01:05');
      expect(
        formatDuration(const Duration(days: 1, hours: 2, minutes: 3)),
        '1天 02:03',
      );
    });

    test('formats eta and percent', () {
      expect(formatEta(30), '00:00:30');
      expect(formatPercent(0.4567), '45.7%');
      expect(formatPercent(2), '100.0%');
    });
  });
}
