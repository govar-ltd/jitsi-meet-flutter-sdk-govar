import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jitsi_meet_govar_flutter_sdk/src/growing_wav_reader.dart';
import 'package:jitsi_meet_govar_flutter_sdk/src/pcm_chunk_writer.dart';

void main() {
  test('growing WAV with odd metadata chunks and stale lengths preserves bytes',
      () async {
    final dir = await Directory.systemTemp.createTemp('growing-wav-');
    try {
      final source = File('${dir.path}/source.wav');
      final files = <String>[];
      final writer = PcmChunkWriter(dir, onChunk: files.add);
      final reader = GrowingWavReader(source, writer);
      // Apple WAVs can include chunks before fmt/data; do not assume a 44-byte header.
      final h = Uint8List(56);
      final d = ByteData.sublistView(h);
      h.setRange(0, 4, 'RIFF'.codeUnits);
      h.setRange(8, 12, 'WAVE'.codeUnits);
      h.setRange(12, 16, 'JUNK'.codeUnits);
      d.setUint32(16, 3, Endian.little);
      h.setRange(24, 28, 'fmt '.codeUnits);
      d.setUint32(28, 16, Endian.little);
      d.setUint16(32, 1, Endian.little);
      d.setUint16(34, 1, Endian.little);
      d.setUint32(36, 48000, Endian.little);
      d.setUint32(40, 96000, Endian.little);
      d.setUint16(44, 2, Endian.little);
      d.setUint16(46, 16, Endian.little);
      h.setRange(48, 52, 'data'.codeUnits);
      await source.writeAsBytes(h.sublist(0, 30));
      await reader.poll();
      expect(reader.bytesRead, 0);
      await source.writeAsBytes(h);
      final pcm = Uint8List.fromList(List.generate(960002, (i) => i % 251));
      await source.writeAsBytes(pcm.sublist(0, 192001), mode: FileMode.append);
      await reader.poll();
      expect(reader.bytesRead, 192000);
      expect(files, isEmpty);
      await source.writeAsBytes(pcm.sublist(192001), mode: FileMode.append);
      await reader.poll();
      await reader.poll();
      expect(reader.bytesRead, 960002);
      expect(files.length, 1);
      expect(await File(files.first).length(), 960044);
      await reader.poll(finalRead: true);
      await writer.finish();
      expect(files.length, 2);
      final joined = BytesBuilder();
      for (final p in files) {
        joined.add((await File(p).readAsBytes()).sublist(44));
      }
      expect(joined.takeBytes(), pcm);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
