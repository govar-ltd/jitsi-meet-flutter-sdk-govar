import 'dart:async';
import 'pcm_chunk_writer.dart';
import 'package:jitsi_meet_govar_flutter_sdk/src/method_response.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class JitsiAudioRecorder {
  final _recorder = AudioRecorder();
  Directory? _audioDirectory;
  StreamSubscription? _pcmSubscription;
  PcmChunkWriter? _writer;
  Future<void>? _continuousStop;
  bool _continuous = false;
  Completer<void>? _pcmDone;

  Future<MethodResponse> startContinuousRecording({
    required void Function(String path) onChunk,
    required void Function(Object error, StackTrace stack) onError,
  }) async {
    if (_continuous) {
      return MethodResponse(isSuccess: true, message: 'Already capturing');
    }
    if (!(await _recorder.hasPermission())) {
      return MethodResponse(
        isSuccess: false,
        message: 'Microphone permission denied',
      );
    }
    if (_audioDirectory == null) await createRecordingFolder();
    _writer = PcmChunkWriter(_audioDirectory!, onChunk: onChunk);
    _continuousStop = null;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 48000,
        numChannels: 1,
      ),
    );
    _continuous = true;
    _pcmDone = Completer<void>();
    _pcmSubscription = stream.listen(
      (bytes) {
        unawaited(
          _writer!.append(bytes).catchError((Object error, StackTrace stack) {
            if (_continuousStop != null) return;
            onError(error, stack);
            unawaited(
              stopRecording().catchError((Object e, StackTrace st) {
                onError(e, st);
              }),
            );
          }),
        );
      },
      onError: (Object error, StackTrace stack) {
        onError(error, stack);
      },
      onDone: () {
        if (!(_pcmDone?.isCompleted ?? true)) _pcmDone!.complete();
      },
    );
    return MethodResponse(
      isSuccess: true,
      message: 'Continuous PCM capture started',
    );
  }

  Future<MethodResponse> createRecordingFolder() async {
    final directory = await getTemporaryDirectory();
    final folderName =
        'folder_with_audio_${DateTime.now().millisecondsSinceEpoch}';
    _audioDirectory = Directory('${directory.path}/$folderName');

    if (!_audioDirectory!.existsSync()) {
      _audioDirectory!.createSync(recursive: true);

      return MethodResponse(
        isSuccess: true,
        message: 'Folder has been created',
      );
    }

    return MethodResponse(
      isSuccess: false,
      message: 'Folder hasn`t been created',
    );
  }

  Future<String> _getRecordingPath() async {
    return "${_audioDirectory?.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav";
  }

  Future<MethodResponse> startRecording() async {
    if (!(await _recorder.hasPermission())) {
      return MethodResponse(
        isSuccess: false,
        message: 'User does not have microphone permissions',
      );
    }

    final filePath = await _getRecordingPath();

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 48000,
      numChannels: 1,
    );

    await _recorder.start(config, path: filePath);
    return MethodResponse(
      isSuccess: true,
      message: "Recording has started at path: $filePath",
    );
  }

  Future stopRecording() async {
    if (_continuous) {
      return _continuousStop ??= () async {
        try {
          await _recorder.stop();
          await _pcmDone?.future.timeout(const Duration(seconds: 3));
        } finally {
          await _pcmSubscription?.cancel();
          try {
            await _writer?.finish();
          } finally {
            _pcmSubscription = null;
            _writer = null;
            _continuous = false;
          }
        }
      }();
    }
    if (await _recorder.isRecording()) await _recorder.stop();
    return;
  }

  Future<String?> getRecordingFolderPath() async {
    if (_audioDirectory!.existsSync()) {
      return _audioDirectory!.path;
    } else {
      return null;
    }
  }

  Future<MethodResponse> deleteRecordingFolder() async {
    try {
      if (_audioDirectory == null || !_audioDirectory!.existsSync()) {
        return MethodResponse(
          isSuccess: false,
          message: 'Audio directory does not exist or already deleted',
        );
      }

      await _audioDirectory!.delete(recursive: true);

      return MethodResponse(
        isSuccess: true,
        message: 'Audio directory and all files were successfully deleted',
      );
    } catch (e) {
      return MethodResponse(
        isSuccess: false,
        message: 'Failed to delete audio directory: ${e.toString()}',
      );
    }
  }
}
