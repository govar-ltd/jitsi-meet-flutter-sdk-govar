import 'dart:io';
import 'dart:typed_data';
import 'pcm_chunk_writer.dart';

/// Reads only complete PCM frames already committed to a growing native WAV.
/// RIFF data length is commonly zero/stale until AVAudioRecorder stops.
class GrowingWavReader {
  GrowingWavReader(this.source, this.writer);
  final File source;
  final PcmChunkWriter writer;
  int? _dataOffset;
  int _read = 0;
  int get bytesRead => _read;

  Future<void> poll({bool finalRead = false}) async {
    if (!await source.exists()) return;
    final input = await source.open();
    try {
      final length = await input.length();
      if (_dataOffset == null && !await _parse(input, length)) {
        if (finalRead && length > 0) throw StateError('Incomplete WAV header');
        return;
      }
      if (_dataOffset == null) return;
      var available = length - _dataOffset!;
      if (finalRead) {
        await input.setPosition(_dataOffset! - 4);
        final size = await input.read(4);
        final declared = ByteData.sublistView(size).getUint32(0, Endian.little);
        if (declared > 0 && declared < available) available = declared;
      }
      // Never consume an incomplete PCM16 frame or re-read previous frames.
      available -= available % 2;
      if (available < _read) throw StateError('Native WAV was truncated');
      await input.setPosition(_dataOffset! + _read);
      while (_read < available) {
        final count = (available - _read).clamp(0, 96000);
        final bytes = await input.read(count);
        if (bytes.isEmpty) break;
        final whole = bytes.length - bytes.length % 2;
        if (whole == 0) break;
        await writer.append(Uint8List.sublistView(bytes, 0, whole));
        _read += whole;
      }
    } finally {
      await input.close();
    }
  }

  Future<bool> _parse(RandomAccessFile input, int length) async {
    if (length < 12) return false;
    final riff = await input.read(12);
    if (String.fromCharCodes(riff.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(riff.sublist(8, 12)) != 'WAVE') {
      throw StateError('Native capture is not a RIFF WAV');
    }
    var offset = 12;
    var validFormat = false;
    while (offset + 8 <= length) {
      await input.setPosition(offset);
      final chunk = await input.read(8);
      final id = String.fromCharCodes(chunk.sublist(0, 4));
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      if (id == 'data') {
        if (!validFormat) {
          throw StateError('WAV data precedes validated format');
        }
        _dataOffset = offset + 8;
        return true;
      }
      if (offset + 8 + size > length) return false;
      if (id == 'fmt ') {
        if (size < 16) throw StateError('Invalid WAV format');
        final fmt = ByteData.sublistView(await input.read(size));
        final code = fmt.getUint16(0, Endian.little);
        var pcm = code == 1;
        if (code == 0xfffe && size >= 40) {
          final expected = [
            1,
            0,
            0,
            0,
            0,
            0,
            16,
            0,
            128,
            0,
            0,
            170,
            0,
            56,
            155,
            113
          ];
          pcm = true;
          for (var i = 0; i < 16; i++) {
            if (fmt.getUint8(24 + i) != expected[i]) pcm = false;
          }
        }
        if (!pcm ||
            fmt.getUint16(2, Endian.little) != 1 ||
            fmt.getUint32(4, Endian.little) != 48000 ||
            fmt.getUint16(12, Endian.little) != 2 ||
            fmt.getUint16(14, Endian.little) != 16) {
          throw StateError('Expected native PCM16 mono 48000Hz WAV');
        }
        validFormat = true;
      }
      offset += 8 + size + size % 2;
    }
    return false;
  }
}
