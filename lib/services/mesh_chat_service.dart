import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _meshServiceId = 'com.example.flutter_lab_portfolio.meshchat';
const _maxMessageLength = 2000;
const _maxPayloadBytes = 8192;

class NearbyMeshDevice {
  final String endpointId;
  final String name;

  const NearbyMeshDevice({required this.endpointId, required this.name});
}

class MeshPeer {
  final String id;
  final String name;
  final bool isConnected;

  const MeshPeer({
    required this.id,
    required this.name,
    required this.isConnected,
  });

  MeshPeer copyWith({String? name, bool? isConnected}) => MeshPeer(
        id: id,
        name: name ?? this.name,
        isConnected: isConnected ?? this.isConnected,
      );
}

class MeshMessage {
  final String id;
  final String text;
  final bool isMine;
  final DateTime sentAt;

  const MeshMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.sentAt,
  });
}

class MeshConnectionRequest {
  final String endpointId;
  final String endpointName;
  final String authenticationToken;

  const MeshConnectionRequest({
    required this.endpointId,
    required this.endpointName,
    required this.authenticationToken,
  });
}

enum MeshConnectionStatus { connected, rejected, error }

typedef MeshEndpointFound = void Function(String id, String name);
typedef MeshEndpointLost = void Function(String? id);
typedef MeshConnectionInitiated = void Function(
  String id,
  String name,
  String authenticationToken,
);
typedef MeshConnectionResult = void Function(
  String id,
  MeshConnectionStatus status,
);
typedef MeshEndpointDisconnected = void Function(String id);
typedef MeshPayloadReceived = void Function(String id, Uint8List bytes);

abstract interface class MeshTransport {
  bool get isSupported;

  Future<bool> start({
    required String localName,
    required MeshEndpointFound onEndpointFound,
    required MeshEndpointLost onEndpointLost,
    required MeshConnectionInitiated onConnectionInitiated,
    required MeshConnectionResult onConnectionResult,
    required MeshEndpointDisconnected onDisconnected,
    required MeshPayloadReceived onPayloadReceived,
  });

  Future<bool> refreshDiscovery();
  Future<bool> requestConnection(String localName, String endpointId);
  Future<bool> acceptConnection(String endpointId);
  Future<bool> rejectConnection(String endpointId);
  Future<void> sendBytes(String endpointId, Uint8List bytes);
  Future<void> stop();
}

abstract interface class MeshPermissionGate {
  Future<void> ensureGranted();
}

class NearbyMeshPermissionGate implements MeshPermissionGate {
  @override
  Future<void> ensureGranted() async {
    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = <Permission>[];
    if (sdkInt <= 32) permissions.add(Permission.locationWhenInUse);
    if (sdkInt >= 31) {
      permissions.addAll([
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    }
    if (sdkInt >= 33) permissions.add(Permission.nearbyWifiDevices);
    final requested = await permissions.request();

    final denied = requested.entries
        .where((entry) => !entry.value.isGranted && !entry.value.isLimited)
        .map((entry) => entry.key.toString().split('.').last)
        .toList();
    if (denied.isNotEmpty) {
      throw StateError(
        'Nearby device permissions are required. Allow ${denied.join(', ')} in Settings, then scan again.',
      );
    }
    if (!await Permission.location.serviceStatus.isEnabled) {
      throw StateError(
        'Turn on Location services so Android can discover nearby devices.',
      );
    }
  }
}

class NearbyConnectionsMeshTransport implements MeshTransport {
  final Nearby _nearby = Nearby();
  String? _localName;
  bool _advertising = false;

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> start({
    required String localName,
    required MeshEndpointFound onEndpointFound,
    required MeshEndpointLost onEndpointLost,
    required MeshConnectionInitiated onConnectionInitiated,
    required MeshConnectionResult onConnectionResult,
    required MeshEndpointDisconnected onDisconnected,
    required MeshPayloadReceived onPayloadReceived,
  }) async {
    _localName = localName;
    _lastEndpointFound = onEndpointFound;
    _lastEndpointLost = onEndpointLost;
    _onConnectionInitiated = onConnectionInitiated;
    _onConnectionResult = onConnectionResult;
    _onDisconnected = onDisconnected;
    _onPayloadReceived = onPayloadReceived;
    final advertising = await _nearby.startAdvertising(
      localName,
      Strategy.P2P_CLUSTER,
      serviceId: _meshServiceId,
      onConnectionInitiated: (id, info) => onConnectionInitiated(
        id,
        info.endpointName,
        info.authenticationToken,
      ),
      onConnectionResult: (id, status) =>
          onConnectionResult(id, _mapStatus(status)),
      onDisconnected: onDisconnected,
    );
    _advertising = advertising;
    final bool discovering;
    try {
      discovering = await _nearby.startDiscovery(
        localName,
        Strategy.P2P_CLUSTER,
        serviceId: _meshServiceId,
        onEndpointFound: (id, name, _) => onEndpointFound(id, name),
        onEndpointLost: onEndpointLost,
      );
    } on Object {
      if (_advertising) {
        await _nearby.stopAdvertising();
        _advertising = false;
      }
      rethrow;
    }
    if (!advertising || !discovering) {
      await _nearby.stopDiscovery();
      if (advertising) await _nearby.stopAdvertising();
      _advertising = false;
      return false;
    }
    return true;
  }

  @override
  Future<bool> refreshDiscovery() async {
    final name = _localName;
    if (name == null) return false;
    await _nearby.stopDiscovery();
    return _nearby.startDiscovery(
      name,
      Strategy.P2P_CLUSTER,
      serviceId: _meshServiceId,
      onEndpointFound: (id, endpointName, _) =>
          _lastEndpointFound?.call(id, endpointName),
      onEndpointLost: (id) => _lastEndpointLost?.call(id),
    );
  }

  MeshEndpointFound? _lastEndpointFound;
  MeshEndpointLost? _lastEndpointLost;

  @override
  Future<bool> requestConnection(String localName, String endpointId) =>
      _nearby.requestConnection(
        localName,
        endpointId,
        onConnectionInitiated: (id, info) => _onConnectionInitiated?.call(
          id,
          info.endpointName,
          info.authenticationToken,
        ),
        onConnectionResult: (id, status) =>
            _onConnectionResult?.call(id, _mapStatus(status)),
        onDisconnected: (id) => _onDisconnected?.call(id),
      );

  MeshConnectionInitiated? _onConnectionInitiated;
  MeshConnectionResult? _onConnectionResult;
  MeshEndpointDisconnected? _onDisconnected;
  MeshPayloadReceived? _onPayloadReceived;

  @override
  Future<bool> acceptConnection(String endpointId) => _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (id, payload) {
          final bytes = payload.bytes;
          if (bytes != null) _onPayloadReceived?.call(id, bytes);
        },
      );

  @override
  Future<bool> rejectConnection(String endpointId) =>
      _nearby.rejectConnection(endpointId);

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) =>
      _nearby.sendBytesPayload(endpointId, bytes);

  @override
  Future<void> stop() async {
    await _nearby.stopDiscovery();
    if (_advertising) {
      await _nearby.stopAdvertising();
      _advertising = false;
    }
    await _nearby.stopAllEndpoints();
  }

  MeshConnectionStatus _mapStatus(Status status) => switch (status) {
        Status.CONNECTED => MeshConnectionStatus.connected,
        Status.REJECTED => MeshConnectionStatus.rejected,
        Status.ERROR => MeshConnectionStatus.error,
      };
}

class MeshChatController extends ChangeNotifier {
  MeshChatController({
    MeshTransport? transport,
    MeshPermissionGate? permissionGate,
  })  : _transport = transport ?? NearbyConnectionsMeshTransport(),
        _permissionGate = permissionGate ?? NearbyMeshPermissionGate();

  final MeshTransport _transport;
  final MeshPermissionGate _permissionGate;
  final Map<String, NearbyMeshDevice> _discovered = {};
  final Map<String, MeshPeer> _peers = {};
  final Map<String, List<MeshMessage>> _messages = {};
  final Map<String, String> _peerIdByEndpoint = {};
  final Map<String, String> _endpointByPeerId = {};
  final Map<String, String> _nameByEndpoint = {};
  final Map<String, MeshConnectionRequest> _pendingByEndpoint = {};
  final Set<String> _connectingEndpointIds = {};
  final Set<String> _connectedEndpointIds = {};
  final Set<String> _helloSentEndpointIds = {};
  String? _localPeerId;
  String? _localName;
  bool _isScanning = false;
  bool _hasSearched = false;
  bool _disposed = false;
  String? _errorMessage;

  bool get isScanning => _isScanning;
  bool get hasSearched => _hasSearched;
  String? get errorMessage => _errorMessage;
  String get localName => _localName ?? 'This device';
  List<NearbyMeshDevice> get discoveredDevices =>
      List.unmodifiable(_discovered.values);
  List<MeshConnectionRequest> get pendingConnections =>
      List.unmodifiable(_pendingByEndpoint.values);
  List<MeshPeer> get peers {
    final result = _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(result);
  }

  List<MeshMessage> messagesFor(String peerId) =>
      List.unmodifiable(_messages[peerId] ?? const []);

  bool isConnecting(String endpointId) =>
      _connectingEndpointIds.contains(endpointId);

  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      var peerId = preferences.getString('mesh.peerId');
      var localName = preferences.getString('mesh.localName');
      if (peerId == null || localName == null) {
        final random = Random.secure();
        peerId = List<int>.generate(16, (_) => random.nextInt(16))
            .map((digit) => digit.toRadixString(16))
            .join();
        localName = 'Mesh-${peerId.substring(0, 4).toUpperCase()}';
        await preferences.setString('mesh.peerId', peerId);
        await preferences.setString('mesh.localName', localName);
      }
      _localPeerId = peerId;
      _localName = localName;
      _loadSavedPeers(preferences);
      _loadSavedMessages(preferences);
      notifyListeners();
    } on Object catch (error, stackTrace) {
      _reportError(
        'Unable to load the local chat profile: $error',
        error,
        stackTrace,
      );
    }
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _hasSearched = true;
    _errorMessage = null;
    notifyListeners();
    if (!_transport.isSupported) {
      _setError('Nearby Connections is currently supported on Android only.');
      return;
    }
    if (_localPeerId == null || _localName == null) {
      _setError(
          'The local chat profile is not ready. Reopen Chats and try again.');
      return;
    }
    try {
      await _permissionGate.ensureGranted();
      final started = await _transport.start(
        localName: _localName!,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        onPayloadReceived: _onPayloadReceived,
      );
      if (!started) {
        throw StateError(
          'Android could not start nearby discovery. Check Bluetooth, Wi-Fi, and Location, then scan again.',
        );
      }
      _isScanning = true;
      notifyListeners();
    } on Object catch (error, stackTrace) {
      _isScanning = false;
      _reportError(
        'Could not start nearby discovery: $error',
        error,
        stackTrace,
      );
    }
  }

  Future<void> refreshDiscovery() async {
    _errorMessage = null;
    try {
      if (!_isScanning) {
        await startScanning();
        return;
      }
      _discovered.clear();
      final refreshed = await _transport.refreshDiscovery();
      if (!refreshed) {
        throw StateError('Android could not restart nearby discovery.');
      }
      notifyListeners();
    } on Object catch (error, stackTrace) {
      _reportError(
          'Could not refresh nearby devices: $error', error, stackTrace);
    }
  }

  Future<void> requestConnection(NearbyMeshDevice device) async {
    if (!_isScanning || _connectingEndpointIds.contains(device.endpointId)) {
      return;
    }
    _errorMessage = null;
    _connectingEndpointIds.add(device.endpointId);
    _nameByEndpoint[device.endpointId] = device.name;
    notifyListeners();
    try {
      final requested = await _transport.requestConnection(
        localName,
        device.endpointId,
      );
      if (!requested) {
        _connectingEndpointIds.remove(device.endpointId);
        throw StateError('The connection request could not be sent.');
      }
    } on Object catch (error, stackTrace) {
      _connectingEndpointIds.remove(device.endpointId);
      _reportError('Could not request a connection: $error', error, stackTrace);
    }
  }

  Future<void> acceptConnection(String endpointId) async {
    final request = _pendingByEndpoint[endpointId];
    if (request == null) return;
    _errorMessage = null;
    try {
      final accepted = await _transport.acceptConnection(endpointId);
      if (!accepted) {
        throw StateError('Android could not accept this connection.');
      }
      _pendingByEndpoint.remove(endpointId);
      _connectingEndpointIds.add(endpointId);
      _nameByEndpoint[endpointId] = request.endpointName;
      notifyListeners();
    } on Object catch (error, stackTrace) {
      _reportError(
          'Could not accept the pairing request: $error', error, stackTrace);
    }
  }

  Future<void> rejectConnection(String endpointId) async {
    _pendingByEndpoint.remove(endpointId);
    _connectingEndpointIds.remove(endpointId);
    notifyListeners();
    try {
      final rejected = await _transport.rejectConnection(endpointId);
      if (!rejected) {
        throw StateError('Android could not reject this connection.');
      }
    } on Object catch (error, stackTrace) {
      _reportError(
          'Could not decline the pairing request: $error', error, stackTrace);
    }
  }

  Future<bool> sendMessage(String peerId, String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;
    if (cleanText.length > _maxMessageLength) {
      _setError('Messages must be $_maxMessageLength characters or fewer.');
      return false;
    }
    final endpointId = _endpointByPeerId[peerId];
    if (endpointId == null || !_connectedEndpointIds.contains(endpointId)) {
      _setError(
          'This device is not connected. Reconnect before sending a message.');
      return false;
    }
    final now = DateTime.now();
    final messageId =
        '${_localPeerId ?? 'local'}-${now.microsecondsSinceEpoch}';
    final packet = <String, Object>{
      'version': 1,
      'type': 'message',
      'id': messageId,
      'senderId': _localPeerId!,
      'text': cleanText,
      'sentAt': now.toUtc().toIso8601String(),
    };
    try {
      await _sendPacket(endpointId, packet);
      final message = MeshMessage(
        id: messageId,
        text: cleanText,
        isMine: true,
        sentAt: now,
      );
      _messages.putIfAbsent(peerId, () => []).add(message);
      notifyListeners();
    } on Object catch (error, stackTrace) {
      _reportError('Message could not be sent: $error', error, stackTrace);
      return false;
    }
    await _persistMessagesSafely();
    return true;
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> shutdown() async {
    _disposed = true;
    _isScanning = false;
    await _transport.stop();
  }

  void _onEndpointFound(String id, String name) {
    if (_connectedEndpointIds.contains(id) || name == _localName) return;
    _discovered[id] = NearbyMeshDevice(endpointId: id, name: name);
    _nameByEndpoint[id] = name;
    notifyListeners();
  }

  void _onEndpointLost(String? id) {
    if (id == null || _connectedEndpointIds.contains(id)) return;
    _discovered.remove(id);
    _connectingEndpointIds.remove(id);
    notifyListeners();
  }

  void _onConnectionInitiated(
    String id,
    String name,
    String authenticationToken,
  ) {
    _nameByEndpoint[id] = name;
    _connectingEndpointIds.add(id);
    _pendingByEndpoint[id] = MeshConnectionRequest(
      endpointId: id,
      endpointName: name,
      authenticationToken: authenticationToken,
    );
    _errorMessage = null;
    notifyListeners();
  }

  void _onConnectionResult(String id, MeshConnectionStatus status) {
    _connectingEndpointIds.remove(id);
    _pendingByEndpoint.remove(id);
    switch (status) {
      case MeshConnectionStatus.connected:
        _connectedEndpointIds.add(id);
        _discovered.remove(id);
        unawaited(_sendHello(id));
      case MeshConnectionStatus.rejected:
        _connectedEndpointIds.remove(id);
        _setError('The pairing request was declined.');
      case MeshConnectionStatus.error:
        _connectedEndpointIds.remove(id);
        _setError(
            'The connection could not be established. Try pairing again.');
    }
    notifyListeners();
  }

  void _onDisconnected(String id) {
    _connectedEndpointIds.remove(id);
    _connectingEndpointIds.remove(id);
    _pendingByEndpoint.remove(id);
    final peerId = _peerIdByEndpoint.remove(id);
    if (peerId != null) {
      _endpointByPeerId.remove(peerId);
      final peer = _peers[peerId];
      if (peer != null) {
        _peers[peerId] = peer.copyWith(isConnected: false);
        unawaited(_persistPeersSafely());
      }
    }
    _helloSentEndpointIds.remove(id);
    notifyListeners();
  }

  void _onPayloadReceived(String endpointId, Uint8List bytes) {
    if (!_connectedEndpointIds.contains(endpointId)) return;
    if (bytes.length > _maxPayloadBytes) {
      _setError('A nearby device sent a payload that was too large.');
      return;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported message format.');
      }
      switch (decoded['type']) {
        case 'hello':
          _handleHello(endpointId, decoded);
        case 'message':
          _handleMessage(endpointId, decoded);
        default:
          throw const FormatException('Unknown message type.');
      }
    } on FormatException catch (error, stackTrace) {
      _reportError(
        'Could not read a message from a nearby device: ${error.message}',
        error,
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      _reportError(
          'Could not process a nearby message: $error', error, stackTrace);
    }
  }

  void _handleHello(String endpointId, Map<String, dynamic> packet) {
    final peerId = packet['peerId'];
    final peerName = packet['name'];
    if (peerId is! String ||
        peerId.isEmpty ||
        peerId == _localPeerId ||
        peerName is! String ||
        peerName.trim().isEmpty ||
        peerName.length > 40) {
      throw const FormatException('Invalid peer identity.');
    }
    final previousEndpoint = _endpointByPeerId[peerId];
    if (previousEndpoint != null && previousEndpoint != endpointId) {
      _setError(
          'This peer identity is already connected from another endpoint.');
      unawaited(_rejectInvalidConnection(endpointId));
      return;
    }
    _peerIdByEndpoint[endpointId] = peerId;
    _endpointByPeerId[peerId] = endpointId;
    _peers[peerId] = MeshPeer(
      id: peerId,
      name: peerName.trim(),
      isConnected: true,
    );
    _messages.putIfAbsent(peerId, () => []);
    notifyListeners();
    unawaited(_persistPeersSafely());
  }

  void _handleMessage(String endpointId, Map<String, dynamic> packet) {
    final peerId = _peerIdByEndpoint[endpointId];
    final senderId = packet['senderId'];
    final messageId = packet['id'];
    final text = packet['text'];
    final sentAt = packet['sentAt'];
    if (peerId == null ||
        senderId != peerId ||
        messageId is! String ||
        text is! String ||
        text.trim().isEmpty ||
        text.length > _maxMessageLength ||
        sentAt is! String) {
      throw const FormatException('Invalid chat message.');
    }
    final time = DateTime.tryParse(sentAt);
    if (time == null) throw const FormatException('Invalid message timestamp.');
    final messages = _messages.putIfAbsent(peerId, () => []);
    if (messages.any((message) => message.id == messageId)) return;
    messages.add(
      MeshMessage(
        id: messageId,
        text: text,
        isMine: false,
        sentAt: time.toLocal(),
      ),
    );
    notifyListeners();
    unawaited(_persistMessagesSafely());
  }

  Future<void> _sendHello(String endpointId) async {
    final localId = _localPeerId;
    final name = _localName;
    if (localId == null ||
        name == null ||
        !_helloSentEndpointIds.add(endpointId)) {
      return;
    }
    try {
      await _sendPacket(endpointId, {
        'version': 1,
        'type': 'hello',
        'peerId': localId,
        'name': name,
      });
    } on Object catch (error, stackTrace) {
      _helloSentEndpointIds.remove(endpointId);
      _reportError(
          'Could not complete the peer handshake: $error', error, stackTrace);
    }
  }

  Future<void> _sendPacket(
      String endpointId, Map<String, Object> packet) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(packet)));
    if (bytes.length > _maxPayloadBytes) {
      throw StateError('The encoded message exceeds the nearby payload limit.');
    }
    await _transport.sendBytes(endpointId, bytes);
  }

  void _loadSavedPeers(SharedPreferences preferences) {
    final raw = preferences.getString('mesh.peers');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Expected peer list.');
      for (final value in decoded) {
        if (value is! Map<String, dynamic> ||
            value['id'] is! String ||
            value['name'] is! String) {
          throw const FormatException('Invalid saved peer.');
        }
        final id = value['id'] as String;
        final name = value['name'] as String;
        _peers[id] = MeshPeer(id: id, name: name, isConnected: false);
      }
    } on FormatException catch (error, stackTrace) {
      _reportError(
          'Saved device list is damaged: ${error.message}', error, stackTrace);
    }
  }

  void _loadSavedMessages(SharedPreferences preferences) {
    final raw = preferences.getString('mesh.messages');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected chat map.');
      }
      for (final entry in decoded.entries) {
        final values = entry.value;
        if (values is! List) {
          throw const FormatException('Invalid chat history.');
        }
        _messages[entry.key] = values.map((value) {
          if (value is! Map<String, dynamic> ||
              value['id'] is! String ||
              value['text'] is! String ||
              value['isMine'] is! bool ||
              value['sentAt'] is! String) {
            throw const FormatException('Invalid saved message.');
          }
          final sentAt = DateTime.tryParse(value['sentAt'] as String);
          if (sentAt == null) {
            throw const FormatException('Invalid saved timestamp.');
          }
          return MeshMessage(
            id: value['id'] as String,
            text: value['text'] as String,
            isMine: value['isMine'] as bool,
            sentAt: sentAt,
          );
        }).toList();
      }
    } on FormatException catch (error, stackTrace) {
      _reportError(
          'Saved chat history is damaged: ${error.message}', error, stackTrace);
    }
  }

  Future<void> _persistPeers() async {
    final preferences = await SharedPreferences.getInstance();
    final values = _peers.values
        .map((peer) => {'id': peer.id, 'name': peer.name})
        .toList();
    await preferences.setString('mesh.peers', jsonEncode(values));
  }

  Future<void> _persistPeersSafely() async {
    try {
      await _persistPeers();
    } on Object catch (error, stackTrace) {
      _reportError(
        'Could not save the paired device list: $error',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _persistMessages() async {
    final preferences = await SharedPreferences.getInstance();
    final values = _messages.map(
      (peerId, messages) => MapEntry(
        peerId,
        messages
            .map(
              (message) => {
                'id': message.id,
                'text': message.text,
                'isMine': message.isMine,
                'sentAt': message.sentAt.toIso8601String(),
              },
            )
            .toList(),
      ),
    );
    await preferences.setString('mesh.messages', jsonEncode(values));
  }

  Future<void> _persistMessagesSafely() async {
    try {
      await _persistMessages();
    } on Object catch (error, stackTrace) {
      _reportError('Could not save chat history: $error', error, stackTrace);
    }
  }

  Future<void> _rejectInvalidConnection(String endpointId) async {
    try {
      final rejected = await _transport.rejectConnection(endpointId);
      if (!rejected) {
        throw StateError('Android could not reject the duplicate peer.');
      }
    } on Object catch (error, stackTrace) {
      _reportError(
        'Could not reject the duplicate connection: $error',
        error,
        stackTrace,
      );
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _reportError(String message, Object error, StackTrace stackTrace) {
    _errorMessage = message;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'mesh chat',
        context: ErrorDescription(message),
      ),
    );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      _transport.stop().catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'mesh chat',
            context: ErrorDescription('Could not stop nearby connections'),
          ),
        );
      }),
    );
    super.dispose();
  }
}
