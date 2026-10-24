// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_lab_portfolio/main.dart';
import 'package:flutter_lab_portfolio/models/network_diagnostic.dart';
import 'package:flutter_lab_portfolio/providers/app_state_provider.dart';
import 'package:flutter_lab_portfolio/screens/network_screen.dart';

void main() {
  test('formats network speed with adaptive units', () {
    expect(formatNetworkSpeed(0.5), '500 Kbps');
    expect(formatNetworkSpeed(25), '25.0 Mbps');
    expect(formatNetworkSpeed(1500), '1.50 Gbps');
    expect(formatNetworkSpeed(null), '--');
  });

  testWidgets('creates an activity and uses USER as the profile name',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppStateProvider(),
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello! USER'), findsOneWidget);
    await tester.tap(find.byTooltip('Create activity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Field Notes');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Record observations from the lab.',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Field Notes'), findsOneWidget);
    final appState =
        tester.element(find.byType(MyApp)).read<AppStateProvider>();
    expect(appState.activities.first.objective,
        'Record observations from the lab.');
  });

  testWidgets('shows the network monitor tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppStateProvider(),
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();

    expect(find.text('Network Monitor'), findsOneWidget);
    expect(find.text('Current Network'), findsOneWidget);
    expect(find.text('Dataset Download'), findsOneWidget);
  });

  testWidgets('queues requests offline and sends them after reconnection',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppStateProvider(),
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Simulate Loss'));
    await tester.tap(find.text('Simulate Loss'));
    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(find.text('Start Request'));
    await tester.tap(find.text('Start Request'));
    await tester.pump();

    expect(find.text('Waiting for network'), findsOneWidget);
    expect(find.text('Dataset Download'), findsWidgets);

    final appState =
        tester.element(find.byType(MyApp)).read<AppStateProvider>();
    await tester.tap(find.text('Restore Network'));
    await tester.pump();
    appState.setNetworkStatusForTesting(NetworkStatus.wifi);
    await tester.pump();
    expect(find.text('Sending request'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1 request sent successfully'), findsOneWidget);
    expect(find.text('Sent successfully'), findsOneWidget);
  });

  test('classifies connection health by speed and network quality', () {
    expect(
      classifyConnectionHealth(
        downloadMbps: 25,
        uploadMbps: 12,
        averagePingMs: 40,
        packetLossPercent: 0,
      ),
      ConnectionHealth.excellent,
    );
    expect(
      classifyConnectionHealth(
        downloadMbps: 6,
        uploadMbps: 3,
        averagePingMs: 80,
        packetLossPercent: 0,
      ),
      ConnectionHealth.fair,
    );
    expect(
      classifyConnectionHealth(
        downloadMbps: 1.5,
        uploadMbps: 1,
        averagePingMs: 80,
        packetLossPercent: 0,
      ),
      ConnectionHealth.poor,
    );
    expect(
      classifyConnectionHealth(
        downloadMbps: 20,
        uploadMbps: 20,
        averagePingMs: 450,
        packetLossPercent: 0,
      ),
      ConnectionHealth.degraded,
    );
  });
}
