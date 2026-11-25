import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vfd_data.dart';

class VfdProvider extends ChangeNotifier {
  VfdData _data        = VfdData();
  bool    _simMode     = false;
  bool    _bleConnected= false;
  String  _bleStatus   = 'Déconnecté';
  String  _consoleLog  = '';
  int     _currentMode = 0;
  double  _displayFreq = 0.0;
  bool    _scanning    = false;

  final List<ChartPoint> tempHistory = [];
  final List<ChartPoint> presHistory = [];
  final List<ChartPoint> flowHistory = [];

  final List<SeqStep> seqSteps      = [];
  bool   _seqRunning    = false;
  int    _seqCurStep    = 0;
  Timer? _seqTimer;
  Timer? _simTimer;
  Timer? _rampTimer;
  Timer? _chartTimer;

  BluetoothDevice?        _device;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription?     _notifySub;
  StreamSubscription?     _scanSub;
  StreamSubscription?     _connSub;

  static const _svcUUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const _rxUUID  = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const _txUUID  = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  final Random _rng = Random();

  VfdData get data         => _data;
  bool    get simMode      => _simMode;
  bool    get bleConnected => _bleConnected;
  String  get bleStatus    => _bleStatus;
  String  get consoleLog   => _consoleLog;
  int     get currentMode  => _currentMode;
  double  get displayFreq  => _displayFreq;
  bool    get seqRunning   => _seqRunning;
  int     get seqCurStep   => _seqCurStep;
  bool    get scanning     => _scanning;

  VfdProvider() {
    _loadPrefs();
    _startChartTimer();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _simMode = p.getBool('sim_mode') ?? false;
    if (_simMode) _startSimulation();
    notifyListeners();
  }

  Future<void> setSimMode(bool val) async {
    _simMode = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('sim_mode', val);
    if (val) {
      await _disconnectBle();
      _startSimulation();
    } else {
      _stopSimulation();
      _bleStatus = 'Déconnecté';
    }
    notifyListeners();
  }

  // ── Simulation ─────────────────────────────────────────────────────────────
  void _startSimulation() {
    _simTimer?.cancel();
    _bleStatus = 'MODE SIMULATION';
    _simTimer  = Timer.periodic(const Duration(milliseconds: 500), (_) => _tickSim());
  }

  void _stopSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
  }

  void _tickSim() {
    if (!_data.motorRunning) {
      _data = _data.copyWith(
        temperature: _data.temperature > 22.0 ? _data.temperature - 0.08 : 22.0,
        pressure:    _data.pressure > 0.0    ? _data.pressure - 0.04    : 0.0,
        flowRate:    _data.flowRate > 0.0    ? _data.flowRate - 0.15    : 0.0,
      );
    } else {
      final r  = _data.frequency / 50.0;
      final tT = 22.0 + r * 43.0 + _rng.nextDouble() * 0.5;
      final pT = r * r * 3.2    + _rng.nextDouble() * 0.04;
      final qT = r * 18.0       + _rng.nextDouble() * 0.3;
      _data = _data.copyWith(
        temperature: _data.temperature + (tT - _data.temperature) * 0.04,
        pressure:    _data.pressure    + (pT - _data.pressure)    * 0.08,
        flowRate:    _data.flowRate    + (qT - _data.flowRate)     * 0.10,
      );
    }
    notifyListeners();
  }

  // ── Ramp animation ─────────────────────────────────────────────────────────
  void _animateRamp(double target) {
    _rampTimer?.cancel();
    _rampTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final diff = target - _displayFreq;
      if (diff.abs() < 0.15) {
        _displayFreq = target;
        if (_simMode) _data = _data.copyWith(frequency: target);
        _rampTimer?.cancel();
      } else {
        _displayFreq += diff * 0.055;
        if (_simMode) _data = _data.copyWith(frequency: _displayFreq);
      }
      notifyListeners();
    });
  }

  // ── Charts ─────────────────────────────────────────────────────────────────
  void _startChartTimer() {
    _chartTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final t = DateTime.now();
      _push(tempHistory, t, _data.temperature);
      _push(presHistory, t, _data.pressure);
      _push(flowHistory, t, _data.flowRate);
      notifyListeners();
    });
  }

  void _push(List<ChartPoint> l, DateTime t, double v) {
    l.add(ChartPoint(t, v));
    if (l.length > 60) l.removeAt(0);
  }

  // ── Console ────────────────────────────────────────────────────────────────
  void _log(String m) {
    final n = DateTime.now();
    final s = '${n.hour.toString().padLeft(2,'0')}:'
              '${n.minute.toString().padLeft(2,'0')}:'
              '${n.second.toString().padLeft(2,'0')}';
    _consoleLog = '[$s] $m\n$_consoleLog';
    if (_consoleLog.length > 5000) _consoleLog = _consoleLog.substring(0, 5000);
    notifyListeners();
  }

  void clearConsole() { _consoleLog = ''; notifyListeners(); }

  // ── BLE parse ──────────────────────────────────────────────────────────────
  void _parseLine(String line) {
    _log(line);
    if (!line.startsWith('TELEM')) return;

    double? f, t, p, q, a, tf;
    bool?   r;

    RegExp(r'F:([\d.]+)').firstMatch(line)?.let((m)  => f  = double.tryParse(m.group(1)!));
    RegExp(r' T:([\d.]+)').firstMatch(line)?.let((m) => t  = double.tryParse(m.group(1)!));
    RegExp(r'P:([\d.]+)').firstMatch(line)?.let((m)  => p  = double.tryParse(m.group(1)!));
    RegExp(r'Q:([\d.]+)').firstMatch(line)?.let((m)  => q  = double.tryParse(m.group(1)!));
    RegExp(r'A:([\d.]+)').firstMatch(line)?.let((m)  => a  = double.tryParse(m.group(1)!));
    RegExp(r'Tf:([\d.]+)').firstMatch(line)?.let((m) => tf = double.tryParse(m.group(1)!));
    RegExp(r'R:([01])').firstMatch(line)?.let((m)    => r  = m.group(1) == '1');

    _data = _data.copyWith(
      frequency: f ?? _data.frequency,
      targetFrequency: tf ?? _data.targetFrequency,
      amplitude: a ?? _data.amplitude,
      temperature: (t != null && t! > 1) ? t : _data.temperature,
      pressure: p ?? _data.pressure,
      flowRate: q ?? _data.flowRate,
      motorRunning: r ?? _data.motorRunning,
    );
    if (f != null) _displayFreq = f!;
    notifyListeners();
  }

  // ── BLE connect ────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    if (_simMode) return;
    _scanning  = true;
    _bleStatus = 'Scan BLE...';
    notifyListeners();

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName == 'VFD-Aquatec') {
          FlutterBluePlus.stopScan();
          _connectTo(r.device);
          break;
        }
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      _scanning = false;
      if (!_bleConnected) _bleStatus = 'Introuvable';
      notifyListeners();
    });
  }

  Future<void> _connectTo(BluetoothDevice dev) async {
    _bleStatus = 'Connexion...';
    _scanning  = false;
    notifyListeners();
    try {
      await dev.connect(timeout: const Duration(seconds: 10));
      _device = dev;
      _bleStatus = 'Découverte services...';
      notifyListeners();

      final services = await dev.discoverServices();
      String lineBuf = '';
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != _svcUUID) continue;
        for (final c in svc.characteristics) {
          final u = c.uuid.toString().toLowerCase();
          if (u == _txUUID) {
            await c.setNotifyValue(true);
            _notifySub = c.lastValueStream.listen((v) {
              if (v.isEmpty) return;
              lineBuf += String.fromCharCodes(v);
              while (lineBuf.contains('\n')) {
                final idx = lineBuf.indexOf('\n');
                final line = lineBuf.substring(0, idx).trim();
                lineBuf = lineBuf.substring(idx + 1);
                if (line.isNotEmpty) _parseLine(line);
              }
            });
          }
          if (u == _rxUUID) _rxChar = c;
        }
      }

      _bleConnected = true;
      _bleStatus    = 'Connecté ✓';
      _log('✓ VFD-Aquatec connecté');
      notifyListeners();

      _connSub = dev.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _bleConnected = false;
          _bleStatus    = 'Déconnecté';
          _log('⚠ Connexion perdue');
          notifyListeners();
        }
      });
    } catch (e) {
      _bleStatus = 'Erreur: $e';
      _scanning  = false;
      _log('✗ $e');
      notifyListeners();
    }
  }

  Future<void> _disconnectBle() async {
    await _notifySub?.cancel();
    await _scanSub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _bleConnected = false;
    _device  = null;
    _rxChar  = null;
  }

  Future<void> disconnect() async {
    await _disconnectBle();
    _bleStatus = 'Déconnecté';
    notifyListeners();
  }

  // ── Send command ───────────────────────────────────────────────────────────
  Future<void> sendCommand(String cmd) async {
    _log('>> $cmd');
    if (_simMode) { _simHandleCmd(cmd); return; }
    if (!_bleConnected || _rxChar == null) { _log('⚠ Non connecté'); return; }
    try {
      await _rxChar!.write([...cmd.codeUnits, 13, 10], withoutResponse: true);
    } catch (e) { _log('✗ $e'); }
  }

  // ── Sim command handler ────────────────────────────────────────────────────
  void _simHandleCmd(String raw) {
    final cmd = raw.trim().toUpperCase();

    if (cmd == 'MODE 1') {
      _currentMode = 1;
      _data = _data.copyWith(mode: 1, motorRunning: true, targetFrequency: 50.0);
      _animateRamp(50.0);
      _log('<< [MODE 1] AUTO – Démarrage 50 Hz');
    } else if (cmd == 'MODE 2') {
      _currentMode = 2;
      _data = _data.copyWith(mode: 2);
      _log('<< [MODE 2] MANUEL – en attente de commandes');
    } else if (cmd == 'MODE 3') {
      _currentMode = 3;
      _data = _data.copyWith(mode: 3);
      _log('<< [MODE 3] SÉQUENCE – construis ta séquence');
    } else if (cmd == 'START') {
      if (_data.targetFrequency < 5) {
        _log('<< [ERR] Tape FREQ xx d abord (min 5 Hz)');
      } else {
        _data = _data.copyWith(motorRunning: true);
        _animateRamp(_data.targetFrequency);
        _log('<< [OK] Démarrage vers ${_data.targetFrequency.toStringAsFixed(1)} Hz');
      }
    } else if (cmd == 'STOP') {
      _data = _data.copyWith(motorRunning: false, targetFrequency: 0.0);
      _seqRunning = false;
      _seqTimer?.cancel();
      _animateRamp(0.0);
      _log('<< [OK] Décélération... Moteur ARRÊTÉ');
    } else if (cmd.startsWith('FREQ ')) {
      final f = double.tryParse(cmd.substring(5)) ?? 0;
      if (f < 5 || f > 50) {
        _log('<< [ERR] Fréquence hors limites (5–50 Hz)');
      } else {
        _data = _data.copyWith(targetFrequency: f);
        if (_data.motorRunning) _animateRamp(f);
        _log('<< [OK] Fréquence cible = ${f.toStringAsFixed(1)} Hz');
      }
    } else if (cmd == 'STATUS') {
      final ms = ['AUCUN','AUTO','MANUEL','SÉQUENCE'];
      _log('<< Mode:${ms[_currentMode.clamp(0,3)]} | '
           'Moteur:${_data.motorRunning?"EN MARCHE":"ARRÊTÉ"} | '
           'F:${_data.frequency.toStringAsFixed(1)} Hz');
    } else if (cmd.startsWith('ADD ')) {
      final p = cmd.substring(4).trim().split(' ');
      if (p.length >= 2) {
        final hz  = double.tryParse(p[0]) ?? 0;
        final sec = int.tryParse(p[1]) ?? 0;
        if (hz >= 5 && hz <= 50 && sec > 0) {
          seqSteps.add(SeqStep(freqHz: hz, durationSec: sec));
          _log('<< [SEQ] Step ${seqSteps.length} : ${hz}Hz / ${sec}s');
        } else { _log('<< [ERR] Valeurs invalides'); }
      }
    } else if (cmd == 'LIST') {
      if (seqSteps.isEmpty) { _log('<< [SEQ] Vide'); }
      else { for (int i=0;i<seqSteps.length;i++) _log('<< [${i+1}] ${seqSteps[i].freqHz}Hz – ${seqSteps[i].durationSec}s'); }
    } else if (cmd == 'CLEAR') {
      seqSteps.clear();
      _log('<< [SEQ] Effacée');
    } else if (cmd == 'GO') {
      if (seqSteps.isEmpty) { _log('<< [ERR] Aucune étape'); return; }
      _seqRunning = true;
      _seqCurStep = 0;
      _log('<< [SEQ] GO – ${seqSteps.length} étapes');
      _execSeqStep();
    } else if (cmd == 'TELEM ON') {
      _log('<< [OK] Télémétrie ON');
    } else if (cmd == 'TELEM OFF') {
      _log('<< [OK] Télémétrie OFF');
    }
    notifyListeners();
  }

  void _execSeqStep() {
    if (_seqCurStep >= seqSteps.length) {
      _seqRunning = false;
      _data = _data.copyWith(motorRunning: false, targetFrequency: 0.0);
      _animateRamp(0.0);
      _log('<< [SEQ] Terminée – Arrêt moteur');
      notifyListeners();
      return;
    }
    final s = seqSteps[_seqCurStep];
    _data = _data.copyWith(motorRunning: true, targetFrequency: s.freqHz);
    _animateRamp(s.freqHz);
    _log('<< [SEQ] Step ${_seqCurStep+1}/${seqSteps.length} : ${s.freqHz}Hz – ${s.durationSec}s');
    notifyListeners();
    _seqTimer?.cancel();
    _seqTimer = Timer(Duration(seconds: s.durationSec), () {
      _seqCurStep++;
      _execSeqStep();
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  void setMode(int m)          { _currentMode = m; sendCommand('MODE $m'); notifyListeners(); }
  void motorStart()            => sendCommand('START');
  void motorStop()             => sendCommand('STOP');
  void setFrequency(double f)  => sendCommand('FREQ ${f.toStringAsFixed(1)}');
  void seqAdd(double hz, int s){ sendCommand('ADD ${hz.toStringAsFixed(1)} $s'); }
  void seqClear()              { seqSteps.clear(); sendCommand('CLEAR'); notifyListeners(); }
  void seqGo()                 => sendCommand('GO');
  void seqStop()               => sendCommand('STOP');
  void getStatus()             => sendCommand('STATUS');
  void telemOn()               => sendCommand('TELEM ON');
  void telemOff()              => sendCommand('TELEM OFF');

  @override
  void dispose() {
    _simTimer?.cancel();
    _rampTimer?.cancel();
    _chartTimer?.cancel();
    _seqTimer?.cancel();
    _disconnectBle();
    super.dispose();
  }
}

extension _Let<T> on T? {
  void let(void Function(T) f) { if (this != null) f(this as T); }
}
