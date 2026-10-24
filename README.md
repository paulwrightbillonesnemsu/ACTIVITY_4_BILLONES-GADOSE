# Flutter Lab Portfolio App — Setup Guide

This zip has the `lib/` source code and `pubspec.yaml` for your app, but it's
missing the platform folders (`android/`, `ios/`, etc.) that only the Flutter
CLI can generate. Follow these steps in order.

## 1. Install Flutter (skip if already installed)
Download and install the Flutter SDK from https://flutter.dev, then add it to
your PATH. Confirm it works:
```
flutter doctor
```
Fix anything it flags as missing (Android SDK, licenses, etc.).

## 2. Scaffold a fresh project
In a terminal, **outside** this extracted folder:
```
flutter create flutter_lab_portfolio
```
This generates the `android/`, `ios/`, `web/` folders and a default `lib/`
and `pubspec.yaml` you don't need.

## 3. Copy in the provided code
- Delete the generated `lib/` folder inside `flutter_lab_portfolio/` and
  replace it with the `lib/` folder from this zip.
- Replace the generated `pubspec.yaml` with the one from this zip.

## 4. Open in Android Studio
- Android Studio → Open → select the `flutter_lab_portfolio` folder.
- Let it index, then open a terminal inside Android Studio and run:
```
flutter pub get
```

## 5. Connect your phone
1. On your phone: Settings → About phone → tap "Build number" 7 times to
   unlock Developer Options.
2. Settings → Developer Options → enable **USB debugging**.
3. Plug the phone into your computer with a USB cable.
4. Accept the "Allow USB debugging?" prompt on the phone.
5. In Android Studio's device dropdown (top toolbar), your phone should now
   appear. Select it.

## 6. Run
Click the green ▶ Run button, or from the terminal:
```
flutter run
```
The app will build and launch directly on your phone.

## What's inside
- `lib/main.dart` – app entry point, wires up Provider + theming
- `lib/providers/app_state_provider.dart` – global state (theme mode, user
  profile, activity list) using `ChangeNotifier`
- `lib/models/activity.dart` – plain data model for an activity
- `lib/theme/app_theme.dart` – colors + light/dark `ThemeData`
- `lib/screens/main_screen.dart` – bottom nav host (`StatefulWidget`, holds
  local tab-index state)
- `lib/screens/dashboard_screen.dart` – Home tab, lists activities
- `lib/screens/activity_details_screen.dart` – pushed when "View Activity"
  is tapped
- `lib/screens/settings_screen.dart` – profile card + Light/Dark segmented
  toggle that drives the global theme
- `lib/widgets/activity_card.dart` – reusable `StatelessWidget` card

## Local Mesh Chat

The Chats tab provides offline, direct device-to-device text messaging using
Google Nearby Connections. It automatically advertises this device and
discovers other installs while the Chats screen is open. Both devices need to
run the Android app, enable Bluetooth and Wi-Fi, and grant the nearby-device
permissions requested by Android. On older Android versions, Location
permission/services may also be required for discovery.

Pair requests show Nearby Connections' authentication code. Compare the code
on both devices before accepting. Messages and paired-device history are kept
locally on each device; no server is used. This implementation supports direct
peers only, not multi-hop message relaying. The `nearby_connections` package
used here is Android-only; iOS discovery and messaging are not implemented. card

## How the state management requirement is satisfied
`AppStateProvider` extends `ChangeNotifier` and is provided at the root of
the widget tree in `main.dart`. The Settings screen calls
`appState.setThemeMode(...)`, which calls `notifyListeners()`. Because
`MyApp`, `DashboardScreen`, and `SettingsScreen` all call
`context.watch<AppStateProvider>()`, they rebuild instantly and the whole
app (including the Home Dashboard) reflects the new theme — satisfying the
"changing this value must instantly update the UI across the app"
requirement without any manual `setState` plumbing between screens.
