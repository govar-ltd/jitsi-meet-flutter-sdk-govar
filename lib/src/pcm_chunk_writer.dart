import 'dart:io';
import 'dart:typed_data';

/// Splits one continuous PCM16 mono capture without restarting its input.
class PcmChunkWriter {
  PcmChunkWriter(
    this.directory, {
    required this.onChunk,
    this.sampleRate = 48000,
  });
  final Directory directory;
  final void Function(String path) onChunk;
  final int sampleRate;
  RandomAccessFile? _sink;
  File? _file;
  int _bytes = 0;
  int _index = 0;
  int _pending = 0;
  bool _closed = false;
  Future<void> _queue = Future.value();
  int get _limit => sampleRate * 2 * (_index == 0 ? 10 : 60);

  Future<void> append(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return Future.value();
    if (pcm.length.isOdd) return Future.error(StateError('Odd PCM16 packet'));
    if (_pending + pcm.length > 4 * 1024 * 1024) {
      return Future.error(StateError('PCM disk queue exceeded 4MB'));
    }
    _pending += pcm.length;
    final owned = Uint8List.fromList(pcm);
    final next = _queue
        .then((_) async {
          var offset = 0;
          while (offset < owned.length) {
            if (_sink == null) {
              _file = File(
                '${directory.path}/recording_${DateTime.now().microsecondsSinceEpoch}_${_index.toString().padLeft(6, '0')}.wav',
              );
              _sink = await _file!.open(mode: FileMode.write);
              await _sink!.writeFrom(_header(0));
            }
            final count = (_limit - _bytes).clamp(0, owned.length - offset);
            await _sink!.writeFrom(owned, offset, offset + count);
            _bytes += count;
            offset += count;
            if (_bytes == _limit) await _finishChunk();
          }
        })
        .whenComplete(() {
          _pending -= owned.length;
        });
    // Preserve failures so subsequent writes do not silently resume after a hole.
    _queue = next;
    return next;
  }

  Future<void> finish() async {
    _closed = true;
    await _queue;
    await _finishChunk();
  }

  Future<void> _finishChunk() async {
    final sink = _sink;
    final file = _file;
    if (sink == null || file == null) return;
    _sink = null;
    _file = null;
    try {
      await sink.setPosition(0);
      await sink.writeFrom(_header(_bytes));
      await sink.flush();
    } finally {
      await sink.close();
    }
    _bytes = 0;
    _index++;
    onChunk(file.path);
  }

  Uint8List _header(int bytes) {
    final h = ByteData(44);
    final b = h.buffer.asUint8List();
    b.setRange(0, 4, 'RIFF'.codeUnits);
    h.setUint32(4, bytes + 36, Endian.little);
    b.setRange(8, 12, 'WAVE'.codeUnits);
    b.setRange(12, 16, 'fmt '.codeUnits);
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    b.setRange(36, 40, 'data'.codeUnits);
    h.setUint32(40, bytes, Endian.little);
    return b;
  }
}
