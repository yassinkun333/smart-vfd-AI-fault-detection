class VfdData {
  final double frequency;
  final double targetFrequency;
  final double amplitude;
  final double temperature;
  final double pressure;
  final double flowRate;
  final bool   motorRunning;
  final int    mode;
  final DateTime timestamp;

  VfdData({
    this.frequency       = 0.0,
    this.targetFrequency = 0.0,
    this.amplitude       = 0.0,
    this.temperature     = 22.0,
    this.pressure        = 0.0,
    this.flowRate        = 0.0,
    this.motorRunning    = false,
    this.mode            = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  double get power    => motorRunning ? (frequency / 50.0) * 3000.0 : 0.0;
  double get speedRpm => frequency * 60.0;

  VfdData copyWith({
    double? frequency, double? targetFrequency, double? amplitude,
    double? temperature, double? pressure, double? flowRate,
    bool? motorRunning, int? mode,
  }) => VfdData(
    frequency:       frequency       ?? this.frequency,
    targetFrequency: targetFrequency ?? this.targetFrequency,
    amplitude:       amplitude       ?? this.amplitude,
    temperature:     temperature     ?? this.temperature,
    pressure:        pressure        ?? this.pressure,
    flowRate:        flowRate        ?? this.flowRate,
    motorRunning:    motorRunning    ?? this.motorRunning,
    mode:            mode            ?? this.mode,
    timestamp:       DateTime.now(),
  );
}

class SeqStep {
  double freqHz;
  int    durationSec;
  SeqStep({required this.freqHz, required this.durationSec});
}

class ChartPoint {
  final DateTime time;
  final double   value;
  ChartPoint(this.time, this.value);
}
