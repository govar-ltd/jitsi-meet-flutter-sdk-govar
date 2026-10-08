import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jitsi_meet_govar_flutter_sdk/src/pcm_chunk_writer.dart';

void main() {
  test('10s then 60s boundaries preserve every sample including crossing packets', () async {
    final dir = await Directory.systemTemp.createTemp('jitsi-pcm-');
    final paths = <String>[];
    try {
      final writer = PcmChunkWriter(dir, onChunk: paths.add, sampleRate: 8000);
      final source = Uint8List(8000 * 2 * 75);
      for (var i = 0; i < source.length; i++) { source[i] = i % 251; }
      for (var offset = 0; offset < source.length; offset += 24682) {
        final end = (offset + 24682).clamp(0, source.length);
        await writer.append(Uint8List.sublistView(source, offset, end));
      }
      await writer.finish();
      await writer.finish();
      expect(paths.length, 3);
      final payload = <int>[];
      final lengths = <int>[];
      for (final p in paths) {
        final wav = await File(p).readAsBytes();
        lengths.add(wav.length);
        final header = ByteData.sublistView(wav);
        expect(header.getUint32(40, Endian.little), wav.length - 44);
        expect(header.getUint16(34, Endian.little), 16);
        payload.addAll(wav.sublist(44));
      }
      expect(lengths, [160044, 960044, 80044]);
      expect(payload, source);
    } finally { await dir.delete(recursive: true); }
  });
  test('first 10 seconds at 48kHz exceeds existing upload size filter', () async {
    final dir = await Directory.systemTemp.createTemp('jitsi-pcm-size-');
    try {
      final paths = <String>[];
      final writer = PcmChunkWriter(dir, onChunk: paths.add);
      await writer.append(Uint8List(48000 * 2 * 10));
      expect(File(paths.single).lengthSync(), 960044);
      await writer.finish();
      expect(paths.length, 1);
    } finally { await dir.delete(recursive: true); }
  });
}
