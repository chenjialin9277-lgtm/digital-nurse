import 'dart:io';
import 'dart:typed_data';

import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/services/offline_speech_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('已合成宣教音频可持久缓存并按语言和正文读取', () async {
    final directory = await Directory.systemTemp.createTemp(
      'digital_nurse_speech_cache_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = OfflineSpeechCache(directory, formatVersion: 'test-v1');
    final audio = OfflineSpeechAudio(
      sampleRate: 22050,
      sampleCount: 4,
      pcm: Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]),
    );

    await cache.write(
      language: OfflineSpeechLanguage.mandarin,
      text: '入院宣教正文',
      audio: audio,
    );
    final restored = await cache.read(
      language: OfflineSpeechLanguage.mandarin,
      text: '入院宣教正文',
    );

    expect(restored?.sampleRate, 22050);
    expect(restored?.sampleCount, 4);
    expect(restored?.pcm, audio.pcm);
    expect(
      await cache.read(
        language: OfflineSpeechLanguage.cantonese,
        text: '入院宣教正文',
      ),
      isNull,
    );
    expect(
      await cache.read(
        language: OfflineSpeechLanguage.mandarin,
        text: '已修改的入院宣教正文',
      ),
      isNull,
    );
  });

  test('损坏缓存自动视为未命中而不会阻断宣教', () async {
    final directory = await Directory.systemTemp.createTemp(
      'digital_nurse_speech_cache_corrupt_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final writer = OfflineSpeechCache(directory, formatVersion: 'test-v1');
    await writer.write(
      language: OfflineSpeechLanguage.english,
      text: 'Any education content',
      audio: OfflineSpeechAudio(
        sampleRate: 22050,
        sampleCount: 2,
        pcm: Uint8List.fromList([1, 0, 2, 0]),
      ),
    );
    final cachedFile =
        await directory
            .list()
            .where((entry) => entry is File && entry.path.endsWith('.pcm'))
            .cast<File>()
            .single;
    await cachedFile.writeAsBytes([1, 2, 3], flush: true);
    final reader = OfflineSpeechCache(directory, formatVersion: 'test-v1');

    expect(
      await reader.read(
        language: OfflineSpeechLanguage.english,
        text: 'Any education content',
      ),
      isNull,
    );
  });
}
