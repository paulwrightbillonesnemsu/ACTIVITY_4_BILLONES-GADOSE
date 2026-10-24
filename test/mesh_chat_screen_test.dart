import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_lab_portfolio/screens/mesh_chat_screen.dart';
import 'package:flutter_lab_portfolio/services/mesh_chat_service.dart';
import 'package:flutter_lab_portfolio/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows empty states before any devices are paired',
      (tester) async {
    final transport = _FakeMeshTransport();
    final controller = MeshChatController(
      transport: transport,
      permissionGate: _FakePermissionGate(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeshChatScreen(controller: controller),
        ),
      ),
    );
    await _pumpUi(tester);

    expect(transport.startCount, 1);
    expect(find.text('No devices found yet'), findsOneWidget);
    expect(find.text('No connected devices'), findsOneWidget);
    await tester.tap(find.text('Chats'));
    await _pumpUi(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('uses readable light text for chat details in dark mode',
      (tester) async {
    final controller = MeshChatController(
      transport: _FakeMeshTransport(),
      permissionGate: _FakePermissionGate(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: MeshChatScreen(controller: controller)),
      ),
    );
    await _pumpUi(tester);

    final nearbyHint = tester.widget<Text>(
      find.textContaining('Visible to nearby devices as'),
    );
    expect(nearbyHint.style?.color, AppColors.textWhiteSoft);
    final emptyMessage = tester.widget<Text>(
      find.textContaining('Discovery is active.'),
    );
    expect(emptyMessage.style?.color, AppColors.textWhiteSoft);
  });

  testWidgets('pairs with a discovered device and sends and receives messages',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = _FakeMeshTransport();
    final controller = MeshChatController(
      transport: transport,
      permissionGate: _FakePermissionGate(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeshChatScreen(controller: controller),
        ),
      ),
    );
    await _pumpUi(tester);

    transport.discover('endpoint-1', 'Neighbor phone');
    await _pumpUi(tester);
    expect(find.text('Neighbor phone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await _pumpUi(tester);
    expect(find.text('Verify & Accept'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    await tester.tap(find.text('Verify & Accept'));
    await _pumpUi(tester);

    expect(find.text('Connected'), findsOneWidget);
    expect(transport.sentPackets.any((packet) => packet['type'] == 'hello'),
        isTrue);

    await tester.tap(find.text('Message'));
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextField), 'Hello from this device');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpUi(tester);

    expect(find.text('Hello from this device'), findsOneWidget);
    expect(
      transport.sentPackets.any(
        (packet) =>
            packet['type'] == 'message' &&
            packet['text'] == 'Hello from this device',
      ),
      isTrue,
    );

    transport.receive({
      'version': 1,
      'type': 'message',
      'id': 'remote-message-1',
      'senderId': 'remote-peer-id',
      'text': 'Reply over Nearby Connections',
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _pumpUi(tester);
    expect(find.text('Reply over Nearby Connections'), findsOneWidget);

    final restoredController = MeshChatController(
      transport: _FakeMeshTransport(),
      permissionGate: _FakePermissionGate(),
    );
    await restoredController.initialize();
    expect(restoredController.peers.single.name, 'Neighbor phone');
    expect(
      restoredController
          .messagesFor('remote-peer-id')
          .map((message) => message.text),
      containsAll([
        'Hello from this device',
        'Reply over Nearby Connections',
      ]),
    );
    restoredController.dispose();
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

class _FakePermissionGate implements MeshPermissionGate {
  @override
  Future<void> ensureGranted() async {}
}

class _FakeMeshTransport implements MeshTransport {
  MeshEndpointFound? _onEndpointFound;
  MeshConnectionInitiated? _onConnectionInitiated;
  MeshConnectionResult? _onConnectionResult;
  MeshPayloadReceived? _onPayloadReceived;
  final List<Map<String, dynamic>> sentPackets = [];
  String? _activeEndpointId;
  int startCount = 0;

  @override
  bool get isSupported => true;

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
    startCount++;
    _onEndpointFound = onEndpointFound;
    _onConnectionInitiated = onConnectionInitiated;
    _onConnectionResult = onConnectionResult;
    _onPayloadReceived = onPayloadReceived;
    return true;
  }

  void discover(String id, String name) => _onEndpointFound?.call(id, name);

  @override
  Future<bool> refreshDiscovery() async => true;

  @override
  Future<bool> requestConnection(String localName, String endpointId) async {
    _activeEndpointId = endpointId;
    _onConnectionInitiated?.call(endpointId, 'Neighbor phone', '123456');
    return true;
  }

  @override
  Future<bool> acceptConnection(String endpointId) async {
    _onConnectionResult?.call(endpointId, MeshConnectionStatus.connected);
    receive({
      'version': 1,
      'type': 'hello',
      'peerId': 'remote-peer-id',
      'name': 'Neighbor phone',
    });
    return true;
  }

  void receive(Map<String, Object> packet) {
    final endpointId = _activeEndpointId;
    if (endpointId != null) {
      _onPayloadReceived?.call(
        endpointId,
        Uint8List.fromList(utf8.encode(jsonEncode(packet))),
      );
    }
  }

  @override
  Future<bool> rejectConnection(String endpointId) async => true;

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    sentPackets.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  }

  @override
  Future<void> stop() async {}
}
