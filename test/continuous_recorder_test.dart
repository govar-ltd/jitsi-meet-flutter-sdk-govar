import 'dart:async';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:jitsi_meet_govar_flutter_sdk/src/jitsi_audio_recorder.dart';

class Capture extends Fake
    with MockPlatformInterfaceMixin
    implements RecordPlatform {
  int starts = 0, stops = 0;
  final pcm = StreamController<Uint8List>();
  @override
  Future<void> create(String id) async {}
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async => true;
  @override
  Stream<RecordState> onStateChanged(String id) => const Stream.empty();
  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig config) async {
    starts++;
    expect(config.sampleRate, 48000);
    expect(config.encoder, AudioEncoder.pcm16bits);
    return pcm.stream;
  }

  @override
  Future<bool> isRecording(String id) async => starts > stops;
  @override
  Future<String?> stop(String id) async {
    stops++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one microphone start across 10s and 60s; final tail drains on stop',
      () async {
    final previous = RecordPlatform.instance;
    final platform = Capture();
    RecordPlatform.instance = platform;
    final tmp = await Directory.systemTemp.createTemp('sdk-continuous-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => tmp.path);
    try {
      final recorder = JitsiAudioRecorder();
      final files = <String>[];
      final errors = <Object>[];
      await recorder.createRecordingFolder();
      final r = await recorder.startContinuousRecording(
          onChunk: files.add, onError: (e, _) => errors.add(e));
      expect(r.isSuccess, true);
      await recorder.startContinuousRecording(
          onChunk: files.add, onError: (e, _) => errors.add(e));
      for (var i = 0; i < 71; i++) {
        platform.pcm.add(Uint8List(96000));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await recorder.stopRecording();
      expect(platform.starts, 1);
      expect(platform.stops, 1);
      expect(errors, isEmpty);
      expect(files.map((p) => File(p).lengthSync()), [960044, 5760044, 96044]);
    } finally {
      RecordPlatform.instance = previous;
      await platform.pcm.close();
      await tmp.delete(recursive: true);
    }
  });
}
