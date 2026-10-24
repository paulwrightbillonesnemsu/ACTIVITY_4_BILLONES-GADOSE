import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/network_diagnostic.dart';

typedef DiagnosticProgress = void Function(DiagnosticPhase phase);

class NetworkDiagnosticService {
  static const _transferSamples = 3;
  static const _downloadBytes = 2 * 1024 * 1024;
  static const _uploadBytes = 512 * 1024;
  static final _downloadUri =
      Uri.parse('https://speed.cloudflare.com/__down?bytes=$_downloadBytes');
  static final _uploadUri = Uri.parse('https://speed.cloudflare.com/__up');
  static final _pingUri =
      Uri.parse('https://speed.cloudflare.com/__down?bytes=1');

  final http.Client _client;
  final Duration timeout;

  NetworkDiagnosticService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  Future<NetworkDiagnosticResult> run({DiagnosticProgress? onProgress}) async {
    onProgress?.call(DiagnosticPhase.measuringIdlePing);
    final idlePing = await _measureSequentialPing(samples: 5);

    onProgress?.call(DiagnosticPhase.measuringDownload);
    final downloadRates = <double>[];
    final downloadPingSamples = <double?>[];
    for (var sample = 0; sample < _transferSamples; sample++) {
      final downloadStarted = Stopwatch()..start();
      final download = _client.get(_downloadUri).timeout(timeout);
      final downloadPing = _measureConcurrentPing();
      final response = await download;
      downloadStarted.stop();
      final pingStats = await downloadPing;
      _ensureSuccess(response);
      downloadRates.add(
        _megabitsPerSecond(response.bodyBytes.length, downloadStarted.elapsed),
      );
      downloadPingSamples.addAll(pingStats.samples);
    }
    final downloadMbps = _median(downloadRates);
    final downloadPingStats = _PingStats.fromSamples(downloadPingSamples);

    onProgress?.call(DiagnosticPhase.measuringUpload);
    final payload = Uint8List(_uploadBytes);
    final uploadRates = <double>[];
    final uploadPingSamples = <double?>[];
    for (var sample = 0; sample < _transferSamples; sample++) {
      final uploadStarted = Stopwatch()..start();
      final upload = _client.post(_uploadUri, body: payload).timeout(timeout);
      final uploadPing = _measureConcurrentPing();
      final response = await upload;
      uploadStarted.stop();
      final pingStats = await uploadPing;
      _ensureSuccess(response);
      uploadRates
          .add(_megabitsPerSecond(payload.length, uploadStarted.elapsed));
      uploadPingSamples.addAll(pingStats.samples);
    }
    final uploadMbps = _median(uploadRates);
    final uploadPingStats = _PingStats.fromSamples(uploadPingSamples);

    final jitterSamples = [
      ...idlePing.samples,
      ...downloadPingStats.samples,
      ...uploadPingStats.samples,
    ];

    return NetworkDiagnosticResult(
      testedAt: DateTime.now(),
      idlePingMs: idlePing.averageMs,
      downloadMbps: downloadMbps,
      downloadPingMs: downloadPingStats.averageMs,
      uploadMbps: uploadMbps,
      uploadPingMs: uploadPingStats.averageMs,
      jitterMs: _jitterMs(jitterSamples),
      packetLossPercent: (idlePing.lossPercent +
              downloadPingStats.lossPercent +
              uploadPingStats.lossPercent) /
          3,
    );
  }

  Future<_PingStats> _measureSequentialPing({int samples = 5}) async {
    final values = <double?>[];
    for (var i = 0; i < samples; i++) {
      values.add(await _measurePing());
    }
    return _PingStats.fromSamples(values);
  }

  Future<_PingStats> _measureConcurrentPing() async {
    final samples = await Future.wait(List.generate(3, (_) => _measurePing()));
    return _PingStats.fromSamples(samples);
  }

  Future<double?> _measurePing() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client.get(_pingUri).timeout(timeout);
      _ensureSuccess(response);
      return stopwatch.elapsedMicroseconds / 1000;
    } catch (_) {
      return null;
    }
  }

  double _megabitsPerSecond(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : (bytes * 8 / seconds) / 1000000;
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _jitterMs(List<double> samples) {
    if (samples.length < 2) return 0;
    final mean = samples.reduce((left, right) => left + right) / samples.length;
    final variance = samples
            .map((sample) => pow(sample - mean, 2))
            .reduce((left, right) => left + right) /
        samples.length;
    return sqrt(variance);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Network diagnostic returned ${response.statusCode}.');
    }
  }

  void dispose() => _client.close();
}

class _PingStats {
  final double averageMs;
  final double lossPercent;
  final List<double> samples;

  const _PingStats({
    required this.averageMs,
    required this.lossPercent,
    required this.samples,
  });

  factory _PingStats.fromSamples(List<double?> samples) {
    final successful = samples.whereType<double>().toList();
    final averageMs = successful.isEmpty
        ? double.infinity
        : successful.reduce((left, right) => left + right) / successful.length;
    return _PingStats(
      averageMs: averageMs,
      lossPercent: (samples.length - successful.length) / samples.length * 100,
      samples: successful,
    );
  }
}
