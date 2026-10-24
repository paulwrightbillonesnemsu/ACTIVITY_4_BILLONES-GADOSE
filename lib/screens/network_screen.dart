import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_diagnostic.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = appState.networkStatus;
    final isOffline = status == NetworkStatus.offline;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.arrow_back,
                    color: isDark ? Colors.white : AppColors.textDark),
                const SizedBox(width: 12),
                const Text('Network Monitor',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 28),
            _CurrentNetworkCard(status: status, isDark: isDark),
            const SizedBox(height: 48),
            _RequestCard(
              isDark: isDark,
              isOffline: isOffline,
              onStartRequest: () {
                appState.startRequest('Dataset Download');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isOffline
                        ? 'Request added to Pending Requests.'
                        : 'Request sent over ${appState.networkLabel}.'),
                  ),
                );
              },
              onToggleLoss: appState.toggleSimulatedLoss,
              isSimulatedLoss: appState.isSimulatedLoss,
            ),
            const SizedBox(height: 48),
            _PendingRequestsCard(
              isDark: isDark,
              requests: appState.requests,
              sentRequestCount: appState.sentRequestCount,
            ),
            const SizedBox(height: 28),
            _DiagnosticCard(appState: appState, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _CurrentNetworkCard extends StatelessWidget {
  final NetworkStatus status;
  final bool isDark;

  const _CurrentNetworkCard({required this.status, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWifi = status == NetworkStatus.wifi;
    final isCellular = status == NetworkStatus.cellular;
    final label = switch (status) {
      NetworkStatus.wifi => 'Wi-Fi',
      NetworkStatus.cellular => 'Cellular Data',
      NetworkStatus.offline => 'No connection',
      NetworkStatus.checking => 'Checking connection',
    };
    return _Panel(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Network',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 26),
          Row(
            children: [
              Icon(
                  isWifi
                      ? Icons.wifi
                      : isCellular
                          ? Icons.signal_cellular_alt
                          : Icons.signal_wifi_off,
                  color: isOfflineStatus(status)
                      ? Colors.redAccent
                      : (isCellular
                          ? const Color(0xFF1960A5)
                          : AppColors.primary),
                  size: 32),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                            child: Text(label,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        _StatusPill(connected: !isOfflineStatus(status)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOfflineStatus(status)
                          ? 'Network unavailable. Requests will be queued.'
                          : 'Monitoring network changes in real-time',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textWhiteSoft
                              : AppColors.textGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

bool isOfflineStatus(NetworkStatus status) =>
    status == NetworkStatus.offline || status == NetworkStatus.checking;

({String value, String unit})? _speedReading(double? mbps) {
  if (mbps == null || !mbps.isFinite) return null;
  if (mbps < 1) {
    final kbps = mbps * 1000;
    return (value: kbps.toStringAsFixed(kbps < 10 ? 1 : 0), unit: 'Kbps');
  }
  if (mbps < 1000) {
    return (value: mbps.toStringAsFixed(1), unit: 'Mbps');
  }
  final gbps = mbps / 1000;
  return (value: gbps.toStringAsFixed(gbps < 10 ? 2 : 1), unit: 'Gbps');
}

String formatNetworkSpeed(double? mbps) {
  final reading = _speedReading(mbps);
  return reading == null ? '--' : '${reading.value} ${reading.unit}';
}

class _RequestCard extends StatelessWidget {
  final bool isDark;
  final bool isOffline;
  final bool isSimulatedLoss;
  final VoidCallback onStartRequest;
  final VoidCallback onToggleLoss;

  const _RequestCard(
      {required this.isDark,
      required this.isOffline,
      required this.isSimulatedLoss,
      required this.onStartRequest,
      required this.onToggleLoss});

  @override
  Widget build(BuildContext context) => _Panel(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Network Request',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  Icon(Icons.cloud_download_outlined, color: AppColors.primary),
                ]),
            const SizedBox(height: 26),
            const Text('Dataset Download',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 48),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                    onPressed: onStartRequest,
                    child: const Text('Start Request'),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                    onPressed: onToggleLoss,
                    child: Text(
                        isSimulatedLoss ? 'Restore Network' : 'Simulate Loss'),
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
}

class _PendingRequestsCard extends StatelessWidget {
  final bool isDark;
  final List<NetworkRequest> requests;
  final int sentRequestCount;

  const _PendingRequestsCard({
    required this.isDark,
    required this.requests,
    required this.sentRequestCount,
  });

  @override
  Widget build(BuildContext context) => _Panel(
        isDark: isDark,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pending Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color:
                    isDark ? AppColors.darkBackground : const Color(0xFFF2F3FF),
                borderRadius: BorderRadius.circular(8)),
            child: requests.isEmpty
                ? Column(children: [
                    const Icon(Icons.library_add_check_outlined,
                        color: AppColors.textGray, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      sentRequestCount == 0
                          ? 'No pending requests'
                          : '$sentRequestCount request${sentRequestCount == 1 ? '' : 's'} sent successfully',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                        'New requests will automatically be queued here when interrupted by connection loss.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textGray)),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${requests.length} request${requests.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      ...requests.map(
                          (request) => _RequestStatusCard(request: request)),
                      if (sentRequestCount > 0)
                        Text(
                          '$sentRequestCount request${sentRequestCount == 1 ? '' : 's'} sent successfully',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF16803A)),
                        ),
                    ],
                  ),
          ),
        ]),
      );
}

class _RequestStatusCard extends StatelessWidget {
  final NetworkRequest request;

  const _RequestStatusCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final isWaiting = request.status == RequestStatus.waitingForNetwork;
    final isSending = request.status == RequestStatus.sending;
    final accent = isWaiting
        ? Colors.orange.shade800
        : isSending
            ? AppColors.primary
            : const Color(0xFF16803A);
    final status = isWaiting
        ? 'Waiting for network'
        : isSending
            ? 'Sending request'
            : 'Sent successfully';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(75)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isWaiting
                ? Icons.cloud_off_rounded
                : isSending
                    ? Icons.cloud_upload_rounded
                    : Icons.check_circle_rounded,
            color: accent,
            size: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(status,
                    style: TextStyle(
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (isSending)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _Panel({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _StatusPill extends StatelessWidget {
  final bool connected;
  const _StatusPill({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF25CD47) : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(40)),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(connected ? 'Connected' : 'Disconnected',
            style: TextStyle(fontSize: 11, color: color)),
      ]),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  final AppStateProvider appState;
  final bool isDark;

  const _DiagnosticCard({required this.appState, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final result = appState.diagnosticResult;
    final isRunning =
        appState.diagnosticPhase == DiagnosticPhase.measuringIdlePing ||
            appState.diagnosticPhase == DiagnosticPhase.measuringDownload ||
            appState.diagnosticPhase == DiagnosticPhase.measuringUpload;
    final health = appState.connectionHealth;
    final accent = _healthColor(health);

    return _Panel(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Network Diagnostic Dashboard',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.speed_rounded, color: accent),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: _SpeedDial(
              value: result?.downloadMbps ?? 0,
              isRunning: isRunning,
              accent: accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(health.label,
                  style: TextStyle(
                      color: accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: isRunning ? null : appState.runDiagnostic,
                tooltip: 'Run diagnostic again',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(_phaseLabel(appState.diagnosticPhase),
              style: TextStyle(
                  fontSize: 12,
                  color:
                      isDark ? AppColors.textWhiteSoft : AppColors.textGray)),
          const SizedBox(height: 10),
          _DiagnosticSteps(phase: appState.diagnosticPhase, accent: accent),
          if (isRunning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 4),
          ],
          if (appState.diagnosticError != null) ...[
            const SizedBox(height: 10),
            Text(appState.diagnosticError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                  child: _Metric(
                      label: 'Idle ping',
                      value: _formatMs(result?.idlePingMs),
                      icon: Icons.radio_button_checked_rounded)),
              Expanded(
                  child: _Metric(
                      label: 'Download',
                      value: formatNetworkSpeed(result?.downloadMbps),
                      icon: Icons.download_rounded)),
              Expanded(
                  child: _Metric(
                      label: 'Upload',
                      value: formatNetworkSpeed(result?.uploadMbps),
                      icon: Icons.upload_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  static String _phaseLabel(DiagnosticPhase phase) => switch (phase) {
        DiagnosticPhase.idle => 'Ready to test',
        DiagnosticPhase.measuringIdlePing => 'Step 1 of 3: measuring idle ping',
        DiagnosticPhase.measuringDownload =>
          'Step 2 of 3: downloading while tracking ping',
        DiagnosticPhase.measuringUpload =>
          'Step 3 of 3: uploading while tracking ping',
        DiagnosticPhase.complete => 'Updated just now',
        DiagnosticPhase.failed => 'Diagnostic could not complete',
      };

  static String _formatMs(double? value) => value == null || value.isInfinite
      ? '--'
      : '${value.toStringAsFixed(0)} ms';

  static Color _healthColor(ConnectionHealth health) => switch (health) {
        ConnectionHealth.excellent => const Color(0xFF16803A),
        ConnectionHealth.fair => const Color(0xFFB26A00),
        ConnectionHealth.poor => const Color(0xFFD04A00),
        ConnectionHealth.degraded => const Color(0xFFD93025),
        ConnectionHealth.unknown => AppColors.textGray,
      };
}

class _SpeedDial extends StatelessWidget {
  final double value;
  final bool isRunning;
  final Color accent;

  const _SpeedDial(
      {required this.value, required this.isRunning, required this.accent});

  @override
  Widget build(BuildContext context) {
    final progress = (value / 100).clamp(0.0, 1.0).toDouble();
    final reading = _speedReading(value == 0 ? null : value);
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              value: isRunning ? null : progress,
              strokeWidth: 9,
              backgroundColor: AppColors.primaryLight,
              color: accent == AppColors.textGray ? AppColors.primary : accent,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reading?.value ?? '--',
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
              ),
              Text('${reading?.unit ?? 'Mbps'} download',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textGray)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticSteps extends StatelessWidget {
  final DiagnosticPhase phase;
  final Color accent;

  const _DiagnosticSteps({required this.phase, required this.accent});

  @override
  Widget build(BuildContext context) {
    final activeIndex = switch (phase) {
      DiagnosticPhase.measuringIdlePing => 0,
      DiagnosticPhase.measuringDownload => 1,
      DiagnosticPhase.measuringUpload => 2,
      DiagnosticPhase.complete => 3,
      _ => -1,
    };
    const labels = ['Idle ping', 'Download + ping', 'Upload + ping'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                Icon(
                  index < activeIndex || activeIndex == 3
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_checked_rounded,
                  size: 16,
                  color: index <= activeIndex ? accent : AppColors.border,
                ),
                const SizedBox(height: 3),
                Text(labels[index],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textGray)),
              ],
            ),
          ),
          if (index < labels.length - 1)
            const Expanded(child: Divider(height: 1)),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textGray)),
              ],
            ),
          ),
        ],
      );
}
