import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'mesh_chat_screen.dart';
import 'network_screen.dart';
import 'settings_screen.dart';

/// Which tab is selected is local, screen-specific UI state that has
/// nothing to do with the rest of the app -> a textbook case for
/// StatefulWidget (as opposed to the global theme, which lives in Provider).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final AppStateProvider _appState;
  NetworkStatus? _lastNetworkStatus;
  NetworkStatus? _notificationStatus;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _lastNetworkStatus = _appState.networkStatus;
    _appState.addListener(_showConnectivityNotification);
  }

  void _showConnectivityNotification() {
    final status = _appState.networkStatus;
    if (!mounted ||
        status == _lastNetworkStatus ||
        status == NetworkStatus.checking) {
      return;
    }
    _lastNetworkStatus = status;
    _notificationTimer?.cancel();
    setState(() => _notificationStatus = status);
    _notificationTimer =
        Timer(const Duration(seconds: 5), _dismissNotification);
  }

  void _dismissNotification() {
    if (!mounted) return;
    setState(() => _notificationStatus = null);
  }

  void _dismissNotificationNow() {
    _notificationTimer?.cancel();
    _dismissNotification();
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _appState.removeListener(_showConnectivityNotification);
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              const DashboardScreen(),
              const NetworkScreen(),
              MeshChatScreen(isVisible: _currentIndex == 2),
              const SettingsScreen(),
            ],
          ),
          if (_notificationStatus case final status?)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              right: 16,
              child: _ConnectivityBanner(
                status: status,
                onDismiss: _dismissNotificationNow,
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkNavBg : AppColors.navBg,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isActive: _currentIndex == 0,
                  onTap: () => _onTabTapped(0),
                ),
                _NavItem(
                  icon: Icons.public_rounded,
                  label: 'Network',
                  isActive: _currentIndex == 1,
                  onTap: () => _onTabTapped(1),
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chats',
                  isActive: _currentIndex == 2,
                  onTap: () => _onTabTapped(2),
                ),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  isActive: _currentIndex == 3,
                  onTap: () => _onTabTapped(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  final NetworkStatus status;
  final VoidCallback onDismiss;

  const _ConnectivityBanner({required this.status, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isOffline = status == NetworkStatus.offline;
    final accent =
        isOffline ? const Color(0xFFD93025) : const Color(0xFF16803A);
    final surface =
        isOffline ? const Color(0xFFFFF4F2) : const Color(0xFFF0FBF3);
    final title = isOffline ? 'Connection lost' : 'Connection restored';
    final message = isOffline
        ? 'Requests will be queued until you are back online.'
        : 'You are connected to ${status == NetworkStatus.wifi ? 'Wi-Fi' : 'Cellular Data'}.';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: accent.withAlpha(65)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss notification',
              icon: const Icon(Icons.close_rounded, size: 19),
              color: AppColors.textGray,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isActive
        ? AppColors.primary
        : (isDark ? AppColors.textWhiteSoft : AppColors.textGray);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
