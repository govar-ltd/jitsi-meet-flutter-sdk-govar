library flutter_govar_foreground_service;

export 'call_notification.dart';

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

part 'src/android_foreground_service_handler.dart';

class FlutterGovarForegroundService {
  static startService(String title, String text) async {
    if (Platform.isAndroid) {
      await ForegroundServiceHandler.startService(title, text);
    } else {
      debugPrint("Error: Can only use foreground services on Android!");
    }
  }

  static stopService() async {
    if (Platform.isAndroid) {
      await ForegroundServiceHandler.stopService();
    } else {
      debugPrint("Error: Can only use foreground services on Android!");
    }
  }

}
