part of '../flutter_govar_foreground_service.dart';

class ForegroundServiceHandler {
  static const MethodChannel _mainChannel = const MethodChannel("flutter_media_foreground_service");

  static Future<void> startService(String title, String text) async {
    return await _mainChannel.invokeMethod<void>(
        'startService', {'title': title, 'text': text});
  }

  static Future<void> stopService() async {
    return await _mainChannel.invokeMethod<void>('stopService');
  }
}