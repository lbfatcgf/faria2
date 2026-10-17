/// Snapshot of `aria2.getGlobalStat`.
class GlobalStat {
  const GlobalStat({
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.numActive = 0,
    this.numWaiting = 0,
    this.numStopped = 0,
  });

  static const GlobalStat empty = GlobalStat();

  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;

  factory GlobalStat.fromJson(Map<String, dynamic> json) {
    return GlobalStat(
      downloadSpeed: _toInt(json['downloadSpeed']),
      uploadSpeed: _toInt(json['uploadSpeed']),
      numActive: _toInt(json['numActive']),
      numWaiting: _toInt(json['numWaiting']),
      numStopped: _toInt(json['numStopped']),
    );
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
