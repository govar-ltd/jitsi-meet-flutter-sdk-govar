import 'dart:async';
import 'pcm_chunk_writer.dart';
import 'growing_wav_reader.dart';
import 'dart:convert';
import 'package:jitsi_meet_govar_flutter_sdk/src/method_response.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class JitsiAudioRecorder {
  final _recorder = AudioRecorder();
  Directory? _audioDirectory;
  PcmChunkWriter? _writer;
  GrowingWavReader? _reader;
  File? _source;
  Timer? _pollTimer;
  StreamSubscription<RecordState>? _stateSubscription;
  Future<void>? _continuousStop;
  Future<void> _pollQueue = Future.value();
  Future<void> _logQueue = Future.value();
  bool _continuous = false;
  bool _pollPending = false;
  DateTime _lastGrowth = DateTime.now();
  bool _stalled = false;
  void Function(Object, StackTrace)? _onError;

  void _log(String event, [Map<String, Object?> details = const {}]) {
    final dir = _audioDirectory;
    if (dir == null) return;
    final line = '${jsonEncode({
          'time': DateTime.now().toUtc().toIso8601String(),
          'event': event,
          ...details
        })}\n';
    _logQueue = _logQueue.then((_) async {
      await File('${dir.path}/capture_diagnostics.jsonl')
          .writeAsString(line, mode: FileMode.append, flush: true);
    }).catchError((Object _) {});
  }

  Future<MethodResponse> startContinuousRecording({
    required void Function(String path) onChunk,
    required void Function(Object error, StackTrace stack) onError,
  }) async {
    if (_continuous) {
      return MethodResponse(isSuccess: true, message: 'Already capturing');
    }
    if (!(await _recorder.hasPermission())) {
      return MethodResponse(
          isSuccess: false, message: 'Microphone permission denied');
    }
    if (_audioDirectory == null) await createRecordingFolder();
    _continuousStop = null;
    _onError = onError;
    _writer = PcmChunkWriter(_audioDirectory!, onChunk: (path) {
      _log('chunk_closed', {'bytes': File(path).lengthSync()});
      onChunk(path);
    });
    _source = File('${_audioDirectory!.path}/capture_source.wav');
    _reader = GrowingWavReader(_source!, _writer!);
    _pollQueue = Future.value();
    _lastGrowth = DateTime.now();
    _stalled = false;
    _stateSubscription = _recorder.onStateChanged().listen((state) {
      _log('recorder_state', {'state': state.name});
    }, onError: (Object error, StackTrace stack) {
      _log('recorder_error', {'error': error.toString()});
      onError(error, stack);
    });
    try {
      // Same native AVAudioRecorder path/configuration as the pre-420 implementation.
      // Keep one file capture running; splitting does not reopen the microphone.
      await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 48000,
            numChannels: 1,
          ),
          path: _source!.path);
      _continuous = true;
      _log('file_capture_started');
      _pollTimer = Timer.periodic(
          const Duration(milliseconds: 500), (_) => _schedulePoll());
      return MethodResponse(
          isSuccess: true, message: 'Continuous native WAV capture started');
    } catch (error, stack) {
      _log('start_failed', {'error': error.toString()});
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      onError(error, stack);
      rethrow;
    }
  }

  void _schedulePoll() {
    if (_pollPending || !_continuous || _continuousStop != null) return;
    _pollPending = true;
    _pollQueue = _pollQueue.then((_) async {
      final before = _reader!.bytesRead;
      await _reader!.poll();
      final after = _reader!.bytesRead;
      if (after > before) {
        if (_stalled) _log('capture_recovered', {'bytes': after});
        _lastGrowth = DateTime.now();
        _stalled = false;
      } else if (!_stalled &&
          DateTime.now().difference(_lastGrowth).inSeconds >= 10) {
        _stalled = true;
        final paused = await _recorder.isPaused();
        final recording = await _recorder.isRecording();
        _log('capture_stalled',
            {'bytes': after, 'paused': paused, 'recording': recording});
        _onError?.call(
            StateError('Native WAV stopped growing'), StackTrace.current);
      }
    }).catchError((Object error, StackTrace stack) {
      _log('read_failed', {'error': error.toString()});
      _onError?.call(error, stack);
      _pollTimer?.cancel();
    }).whenComplete(() {
      _pollPending = false;
    });
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
        _pollTimer?.cancel();
        try {
          await _pollQueue;
          await _recorder.stop();
          await _reader?.poll(finalRead: true);
          await _writer?.finish();
          _log('file_capture_stopped', {'bytes': _reader?.bytesRead});
          // Closed chunks own all captured data; the long source is not uploaded.
          if (await _source!.exists()) await _source!.delete();
        } catch (error, stack) {
          _log('finalize_failed', {'error': error.toString()});
          _onError?.call(error, stack);
          rethrow;
        } finally {
          await _stateSubscription?.cancel();
          _stateSubscription = null;
          _continuous = false;
          _reader = null;
          _writer = null;
          await _logQueue;
        }
      }();
    }
    if (await _recorder.isRecording()) await _recorder.stop();
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
