import 'dart:async';

import 'package:flutter/material.dart';
import '../services/mesh_chat_service.dart';
import '../theme/app_theme.dart';

class MeshChatScreen extends StatefulWidget {
  final bool isVisible;
  final MeshChatController? controller;

  const MeshChatScreen({
    super.key,
    this.isVisible = true,
    this.controller,
  });

  @override
  State<MeshChatScreen> createState() => _MeshChatScreenState();
}

class _MeshChatScreenState extends State<MeshChatScreen> {
  late final MeshChatController _controller;
  late final bool _ownsController;
  late final Future<void> _initialization;
  final TextEditingController _messageController = TextEditingController();
  int _selectedTab = 0;
  MeshPeer? _activeConversation;
  String? _showingPendingEndpoint;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? MeshChatController();
    _controller.addListener(_onControllerChanged);
    _initialization = _controller.initialize();
    if (widget.isVisible) unawaited(_startWhenReady());
  }

  @override
  void didUpdateWidget(covariant MeshChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      unawaited(_startWhenReady());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _messageController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _startWhenReady() async {
    await _initialization;
    if (mounted && widget.isVisible) {
      await _controller.startScanning();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _showNextPairingRequest();
  }

  void _showNextPairingRequest() {
    if (_showingPendingEndpoint != null ||
        _controller.pendingConnections.isEmpty) {
      return;
    }
    final request = _controller.pendingConnections.first;
    _showingPendingEndpoint = request.endpointId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PairingRequestDialog(request: request),
      );
      if (!mounted) return;
      if (accepted == true) {
        await _controller.acceptConnection(request.endpointId);
      } else {
        await _controller.rejectConnection(request.endpointId);
      }
      _showingPendingEndpoint = null;
      _showNextPairingRequest();
    });
  }

  void _openConversation(MeshPeer peer) {
    setState(() {
      _activeConversation = peer;
      _selectedTab = 1;
    });
  }

  Future<void> _sendMessage() async {
    final peer = _activeConversation;
    final text = _messageController.text.trim();
    if (peer == null || text.isEmpty || !peer.isConnected) return;
    final sent = await _controller.sendMessage(peer.id, text);
    if (sent) _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeConversation != null) {
      final peer = _controller.peers
          .where((item) => item.id == _activeConversation!.id)
          .firstOrNull;
      final currentPeer = peer ?? _activeConversation!;
      return _ConversationView(
        peer: currentPeer,
        messages: _controller.messagesFor(currentPeer.id),
        controller: _messageController,
        errorMessage: _controller.errorMessage,
        onClearError: _controller.clearError,
        onSend: _sendMessage,
        onBack: () => setState(() => _activeConversation = null),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          _MeshTabs(
            selectedTab: _selectedTab,
            onSelected: (index) => setState(() => _selectedTab = index),
          ),
          Expanded(
            child: _selectedTab == 0 ? _buildPairTab() : _buildChatsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildPairTab() {
    final devices = _controller.discoveredDevices;
    final peers = _controller.peers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _SearchPanel(
          localName: _controller.localName,
          isSearching: _controller.isScanning,
          onSearch: _controller.refreshDiscovery,
        ),
        if (_controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(
            message: _controller.errorMessage!,
            onDismiss: _controller.clearError,
          ),
        ],
        const SizedBox(height: 24),
        _SectionTitle(
          title: 'Discovered Nearby',
          trailing: devices.isNotEmpty
              ? TextButton.icon(
                  onPressed: _controller.refreshDiscovery,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Scan'),
                )
              : null,
        ),
        const SizedBox(height: 10),
        if (devices.isEmpty)
          _EmptyState(
            icon: _controller.isScanning
                ? Icons.radar_rounded
                : Icons.devices_other,
            title: _controller.hasSearched
                ? 'No devices found yet'
                : 'No nearby devices yet',
            message: _controller.isScanning
                ? 'Discovery is active. Ask the other person to open Mesh Chat and keep Bluetooth, Wi-Fi, and Location enabled.'
                : 'Start a scan to find another device running Mesh Chat nearby.',
            actionLabel: _controller.isScanning ? null : 'Search nearby devices',
            onAction: _controller.isScanning
                ? null
                : _controller.startScanning,
          )
        else
          ...devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NearbyDeviceTile(
                device: device,
                isConnecting: _controller.isConnecting(device.endpointId),
                onPair: () => _controller.requestConnection(device),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const _SectionTitle(title: 'Paired Devices'),
        const SizedBox(height: 10),
        if (peers.isEmpty)
          const _EmptyState(
            icon: Icons.link_off_rounded,
            title: 'No connected devices',
            message:
                'Devices you pair will appear here. Verify the pairing code on both devices to connect.',
          )
        else
          ...peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PairedDeviceTile(
                peer: peer,
                onMessage: () => _openConversation(peer),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatsTab() {
    final chatPeers = _controller.peers
        .where((peer) => _controller.messagesFor(peer.id).isNotEmpty)
        .toList()
      ..sort((a, b) {
        final aMessages = _controller.messagesFor(a.id);
        final bMessages = _controller.messagesFor(b.id);
        return bMessages.last.sentAt.compareTo(aMessages.last.sentAt);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        const Text(
          'Chats',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        if (_controller.errorMessage != null) ...[
          _ErrorBanner(
            message: _controller.errorMessage!,
            onDismiss: _controller.clearError,
          ),
          const SizedBox(height: 12),
        ],
        if (chatPeers.isEmpty)
          _EmptyState(
            icon: Icons.forum_outlined,
            title: _controller.peers.isEmpty
                ? 'No conversations yet'
                : 'No messages yet',
            message: _controller.peers.isEmpty
                ? 'Pair with a nearby device first. Your conversations will show up here.'
                : 'Send a message to a connected device to start a conversation.',
            actionLabel: _controller.peers.isEmpty ? 'Find nearby devices' : null,
            onAction: _controller.peers.isEmpty
                ? () => setState(() => _selectedTab = 0)
                : null,
          )
        else
          ...chatPeers.map((peer) {
            final messages = _controller.messagesFor(peer.id);
            final latest = messages.last;
            return _ChatListTile(
              peer: peer,
              preview: latest.text,
              time: _formatTime(latest.sentAt),
              onTap: () => _openConversation(peer),
            );
          }),
      ],
    );
  }
}

class _MeshTabs extends StatelessWidget {
  final int selectedTab;
  final ValueChanged<int> onSelected;

  const _MeshTabs({required this.selectedTab, required this.onSelected});

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            _MeshTab(
              label: 'Pair',
              isSelected: selectedTab == 0,
              onTap: () => onSelected(0),
            ),
            _MeshTab(
              label: 'Chats',
              isSelected: selectedTab == 1,
              onTap: () => onSelected(1),
            ),
          ],
        ),
      );
}

class _MeshTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MeshTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : _secondaryTextColor(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: isSelected ? 72 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SearchPanel extends StatelessWidget {
  final String localName;
  final bool isSearching;
  final Future<void> Function() onSearch;

  const _SearchPanel({
    required this.localName,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nearby Devices',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Visible to nearby devices as $localName',
              style: TextStyle(
                fontSize: 11,
                color: _secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isSearching
                        ? 'Searching for nearby devices...'
                        : 'Find devices to pair',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isSearching)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                IconButton(
                  onPressed: onSearch,
                  tooltip: 'Search nearby devices',
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.primary,
                ),
              ],
            ),
            if (isSearching) ...[
              const SizedBox(height: 4),
              const LinearProgressIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.primaryLight,
              ),
            ],
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        isDark ? const Color(0xFFFFB4AB) : const Color(0xFFD93025);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF3B2524)
            : const Color(0xFFFFF4F2),
        border: Border.all(color: foreground.withAlpha(90)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss error',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.primary.withAlpha(180)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _secondaryTextColor(context),
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      );
}

class _NearbyDeviceTile extends StatelessWidget {
  final NearbyMeshDevice device;
  final bool isConnecting;
  final VoidCallback onPair;

  const _NearbyDeviceTile({
    required this.device,
    required this.isConnecting,
    required this.onPair,
  });

  @override
  Widget build(BuildContext context) => _DeviceCard(
        name: device.name,
        subtitle: 'Nearby device',
        action: FilledButton(
          onPressed: isConnecting ? null : onPair,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: Text(isConnecting ? 'Connecting…' : 'Pair'),
        ),
        online: true,
      );
}

class _PairedDeviceTile extends StatelessWidget {
  final MeshPeer peer;
  final VoidCallback onMessage;

  const _PairedDeviceTile({required this.peer, required this.onMessage});

  @override
  Widget build(BuildContext context) => _DeviceCard(
        name: peer.name,
        subtitle: peer.isConnected ? 'Connected' : 'Offline',
        action: FilledButton(
          onPressed: peer.isConnected ? onMessage : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Message'),
        ),
        online: peer.isConnected,
      );
}

class _DeviceCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final Widget action;
  final bool online;

  const _DeviceCard({
    required this.name,
    required this.subtitle,
    required this.action,
    required this.online,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _DeviceAvatar(name: name, online: online, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            action,
          ],
        ),
      );
}

class _DeviceAvatar extends StatelessWidget {
  final String name;
  final bool online;
  final double size;

  const _DeviceAvatar({
    required this.name,
    required this.online,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: AppColors.primary,
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: online ? const Color(0xFF24C55A) : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      );
}

class _PairingRequestDialog extends StatelessWidget {
  final MeshConnectionRequest request;

  const _PairingRequestDialog({required this.request});

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _DeviceAvatar(name: request.endpointName, online: true, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    request.endpointName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Wants to establish an encrypted, offline peer-to-peer connection.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 18),
            const Text(
              'Verify this code matches the other device:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                request.authenticationToken,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFBDB3FF)
                      : AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Verify & Accept'),
                ),
              ),
            ],
          ),
        ],
      );
}

class _ChatListTile extends StatelessWidget {
  final MeshPeer peer;
  final String preview;
  final String time;
  final VoidCallback onTap;

  const _ChatListTile({
    required this.peer,
    required this.preview,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        leading: _DeviceAvatar(
          name: peer.name,
          online: peer.isConnected,
          size: 50,
        ),
        title: Text(
          peer.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          time,
          style: TextStyle(
            fontSize: 11,
            color: _secondaryTextColor(context),
          ),
        ),
        onTap: onTap,
      );
}

class _ConversationView extends StatelessWidget {
  final MeshPeer peer;
  final List<MeshMessage> messages;
  final TextEditingController controller;
  final String? errorMessage;
  final VoidCallback onClearError;
  final VoidCallback onSend;
  final VoidCallback onBack;

  const _ConversationView({
    required this.peer,
    required this.messages,
    required this.controller,
    required this.errorMessage,
    required this.onClearError,
    required this.onSend,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          children: [
            Material(
              elevation: 2,
              color: Theme.of(context).cardColor,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      tooltip: 'Back to chats',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                      color: AppColors.primary,
                    ),
                    _DeviceAvatar(
                      name: peer.name,
                      online: peer.isConnected,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          peer.isConnected ? 'Connected' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: _secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _ErrorBanner(
                  message: errorMessage!,
                  onDismiss: onClearError,
                ),
              ),
            Expanded(
              child: messages.isEmpty
                  ? _EmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: 'Start a conversation',
                      message: peer.isConnected
                          ? 'Send a message to your connected device.'
                          : 'Reconnect to this device to send a message.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return Align(
                          alignment: message.isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: message.isMine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * 0.75,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: message.isMine
                                        ? const Color(0xFF55C7AA)
                                        : Theme.of(context)
                                            .dividerColor
                                            .withAlpha(100),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    message.text,
                                    style: TextStyle(
                                      color:
                                          message.isMine ? Colors.white : null,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(message.sentAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _secondaryTextColor(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: peer.isConnected,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: peer.isConnected
                            ? 'Type your message...'
                            : 'Reconnect to send messages',
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: peer.isConnected ? onSend : null,
                    tooltip: 'Send message',
                    icon: const Icon(Icons.send_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

String _formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

Color _secondaryTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textWhiteSoft
        : AppColors.textGray;
