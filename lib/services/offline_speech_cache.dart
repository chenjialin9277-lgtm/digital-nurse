import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/offline_speech_language.dart';

class OfflineSpeechAudio {
  OfflineSpeechAudio({
    required this.sampleRate,
    required this.sampleCount,
    required this.pcm,
  });

  final int sampleRate;
  final int sampleCount;
  final Uint8List pcm;

  Duration get duration =>
      Duration(milliseconds: (sampleCount * 1000 / sampleRate).ceil());

  static OfflineSpeechAudio combine(
    OfflineSpeechAudio first,
    OfflineSpeechAudio second,
  ) {
    if (first.sampleRate != second.sampleRate) {
      throw StateError('Offline speech sample rates do not match');
    }
    final pcm =
        Uint8List(first.pcm.length + second.pcm.length)
          ..setRange(0, first.pcm.length, first.pcm)
          ..setRange(
            first.pcm.length,
            first.pcm.length + second.pcm.length,
            second.pcm,
          );
    return OfflineSpeechAudio(
      sampleRate: first.sampleRate,
      sampleCount: first.sampleCount + second.sampleCount,
      pcm: pcm,
    );
  }
}

class OfflineSpeechCache {
  OfflineSpeechCache(
    this.directory, {
    required this.formatVersion,
    this.maxMemoryEntries = 4,
  });

  static const _magic = 0x444E5453; // DNTS
  static const _headerLength = 16;

  final Directory directory;
  final String formatVersion;
  final int maxMemoryEntries;
  final LinkedHashMap<String, OfflineSpeechAudio> _memory = LinkedHashMap();

  Future<OfflineSpeechAudio?> read({
    required OfflineSpeechLanguage language,
    required String text,
  }) async {
    final key = _key(language, text);
    final memoryAudio = _memory.remove(key);
    if (memoryAudio != null) {
      _memory[key] = memoryAudio;
      return memoryAudio;
    }

    final file = File('${directory.path}${Platform.pathSeparator}$key.pcm');
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < _headerLength) throw const FormatException();
      final header = ByteData.sublistView(bytes, 0, _headerLength);
      if (header.getUint32(0) != _magic || header.getUint32(4) != 1) {
        throw const FormatException();
      }
      final sampleRate = header.getUint32(8);
      final sampleCount = header.getUint32(12);
      if (sampleRate == 0 ||
          sampleCount == 0 ||
          bytes.length != _headerLength + sampleCount * 2) {
        throw const FormatException();
      }
      final audio = OfflineSpeechAudio(
        sampleRate: sampleRate,
        sampleCount: sampleCount,
        pcm: Uint8List.fromList(bytes.sublist(_headerLength)),
      );
      _remember(key, audio);
      return audio;
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<void> write({
    required OfflineSpeechLanguage language,
    required String text,
    required OfflineSpeechAudio audio,
  }) async {
    if (audio.sampleRate <= 0 ||
        audio.sampleCount <= 0 ||
        audio.pcm.length != audio.sampleCount * 2) {
      throw ArgumentError('Invalid offline speech audio');
    }
    final key = _key(language, text);
    await directory.create(recursive: true);
    final bytes = Uint8List(_headerLength + audio.pcm.length);
    ByteData.sublistView(bytes, 0, _headerLength)
      ..setUint32(0, _magic)
      ..setUint32(4, 1)
      ..setUint32(8, audio.sampleRate)
      ..setUint32(12, audio.sampleCount);
    bytes.setRange(_headerLength, bytes.length, audio.pcm);

    final file = File('${directory.path}${Platform.pathSeparator}$key.pcm');
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    _remember(key, audio);
  }

  void _remember(String key, OfflineSpeechAudio audio) {
    if (maxMemoryEntries <= 0) return;
    _memory.remove(key);
    _memory[key] = audio;
    while (_memory.length > maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  String _key(OfflineSpeechLanguage language, String text) {
    final input = utf8.encode(
      '$formatVersion\u0000${language.name}\u0000$text',
    );
    var hash = 0xcbf29ce484222325;
    for (final byte in input) {
      hash ^= byte;
      hash = (hash * 0x100000001b3).toUnsigned(64);
    }
    return '${language.name}_${text.runes.length}_'
        '${hash.toRadixString(16).padLeft(16, '0')}';
  }
}
