// helper/android_version_checker.dart
// Helper for detecting Android 10 devices

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class AndroidVersionChecker {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Checks if the device is running Android 10 (API level 29)
  static Future<bool> isAndroid10() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final int sdkInt = androidInfo.version.sdkInt;

      // Log version information for debugging
      print('Android SDK: $sdkInt, Release: ${androidInfo.version.release}');

      // Android 10 = API level 29
      return sdkInt == 29;
    } catch (e) {
      print('Error checking Android version: $e');
      return false;
    }
  }
}
