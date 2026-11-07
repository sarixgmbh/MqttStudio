import 'package:flutter/services.dart';

// Updates of the macOS app with Sparkle (macos/Runner/MainFlutterWindow.swift), which checks once a day by itself. The
// Windows app is updated by the Microsoft Store, the web app needs no updates.
const MethodChannel _updaterChannel = MethodChannel('eu.sarix.mqttstudio/updater');

// Sparkle shows its own windows for the result
Future checkForUpdates() async {
  await _updaterChannel.invokeMethod('checkForUpdates');
}
