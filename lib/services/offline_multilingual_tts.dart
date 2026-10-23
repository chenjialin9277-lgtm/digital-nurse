import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_pcm_player/flutter_pcm_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../models/offline_speech_language.dart';
import 'local_speech_event.dart';
import 'offline_speech_cache.dart';
import 'offline_speech_segmenter.dart';

/// Bundled, network-independent speech synthesis for fixed education answers.
///
/// Only one model is resident in memory at a time. Switching languages frees
/// the previous model before loading the selected one, which keeps the tablet's
/// memory usage predictable despite bundling three voices in the APK.
class OfflineMultilingualTts {
  OfflineMultilingualTts._();

  static final OfflineMultilingualTts instance = OfflineMultilingualTts._();

  static const _specs = <OfflineSpeechLanguage, _OfflineModelSpec>{
    OfflineSpeechLanguage.mandarin: _OfflineModelSpec(
      assetRoot: 'assets/tts/vits-piper-zh_CN-xiao_ya-medium',
      versionDirectory: 'mandarin_xiao_ya_int8_v2',
    ),
    OfflineSpeechLanguage.cantonese: _OfflineModelSpec(
      assetRoot: 'assets/tts/vits-cantonese-hf-xiaomaiiwn',
      versionDirectory: 'cantonese_xiaomaiiwn_v1',
    ),
    OfflineSpeechLanguage.english: _OfflineModelSpec(
      assetRoot: 'assets/tts/vits-piper-en_US-amy-low',
      versionDirectory: 'english_amy_low_v1',
    ),
  };

  final _events = StreamController<LocalSpeechEvent>.broadcast(sync: true);
  final _playbackDurations = StreamController<Duration>.broadcast(sync: true);
  final Map<int, Completer<Map<Object?, Object?>>> _requests = {};
  final Map<OfflineSpeechLanguage, Future<Directory>> _modelCopies = {};
  Future<OfflineSpeechCache>? _cachePreparing;
  Future<void>? _workerPreparing;
  SendPort? _workerPort;
  FlutterPcmPlayer? _player;
  Timer? _completionTimer;
  int _requestId = 0;
  int _playbackTicket = 0;

  Stream<LocalSpeechEvent> get events => _events.stream;
  Stream<Duration> get playbackDurations => _playbackDurations.stream;

  Future<void> prepare(OfflineSpeechLanguage language) async {
    if (!Platform.isAndroid) return;
    final directory =
        await (_modelCopies[language] ??= _copyBundledModel(
          language,
        ).catchError((Object error) {
          _modelCopies.remove(language);
          throw error;
        }));
    await _ensureWorker();
    await _sendRequest(<String, Object?>{
      'command': 'load',
      'language': language.name,
      'modelDirectory': directory.path,
    }).timeout(const Duration(minutes: 2));
  }

  Future<void> _ensureWorker() {
    if (_workerPort != null) return Future<void>.value();
    return _workerPreparing ??= _prepareWorker().catchError((Object error) {
      _workerPreparing = null;
      throw error;
    });
  }

  Future<void> _prepareWorker() async {
    final messages = ReceivePort();
    final ready = Completer<void>();
    messages.listen((dynamic message) {
      if (message is SendPort) {
        _workerPort = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is Map) {
        final normalized = Map<Object?, Object?>.from(message);
        final startupError = normalized['startupError'];
        if (startupError != null && !ready.isCompleted) {
          ready.completeError(StateError(startupError.toString()));
          return;
        }
        final id = normalized['id'];
        if (id is int) _requests.remove(id)?.complete(normalized);
      }
    });
    await Isolate.spawn<SendPort>(
      _offlineTtsWorker,
      messages.sendPort,
      errorsAreFatal: true,
    );
    await ready.future.timeout(const Duration(seconds: 45));
  }

  Future<Directory> _copyBundledModel(OfflineSpeechLanguage language) async {
    final spec = _specs[language]!;
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}offline_tts'
      '${Platform.pathSeparator}${spec.versionDirectory}',
    );
    await directory.create(recursive: true);
    final readyMarker = File(
      '${directory.path}${Platform.pathSeparator}.ready',
    );
    if (await readyMarker.exists()) return directory;

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = '${spec.assetRoot}/';
    final assets =
        manifest
            .listAssets()
            .where((asset) => asset.startsWith(prefix))
            .toList()
          ..sort();
    if (assets.isEmpty) {
      throw StateError('Bundled ${language.label} speech model is missing');
    }

    for (final asset in assets) {
      final relativePath = asset.substring(prefix.length);
      final target = File(
        '${directory.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await target.writeAsBytes(bytes, flush: true);
    }
    await readyMarker.writeAsString('complete', flush: true);
    return directory;
  }

  Future<void> speak(
    String text, {
    required OfflineSpeechLanguage language,
  }) async {
    await stop();
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      _events.add(LocalSpeechEvent.error);
      return;
    }

    final ticket = ++_playbackTicket;
    try {
      final cache = await _speechCache();
      final cached = await cache.read(language: language, text: normalizedText);
      if (ticket != _playbackTicket) return;
      if (cached != null) {
        await _playCachedAudio(cached, ticket);
        return;
      }

      await prepare(language);
      if (ticket != _playbackTicket) return;
      final directory = await _modelCopies[language]!;
      final segments = splitSpeechForFastStart(normalizedText, language);
      final firstGenerationWatch = Stopwatch()..start();
      final first = await _generateSpeech(
        text: segments.first,
        language: language,
        directory: directory,
      );
      firstGenerationWatch.stop();
      if (ticket != _playbackTicket) return;

      // A single short synthesized segment is not enough to hide the time
      // needed to generate the next segment on mid-range tablets, especially
      // with the Cantonese model. Build an adaptive safety buffer before
      // starting AudioTrack, then continue synthesizing ahead of playback.
      var completeAudio = first;
      var nextSegmentIndex = 1;
      final prebufferTarget = _offlinePrebufferTarget(
        language,
        firstGenerationWatch.elapsed,
      );
      while (nextSegmentIndex < segments.length &&
          completeAudio.duration < prebufferTarget) {
        final bufferedSegment = await _generateSpeech(
          text: segments[nextSegmentIndex],
          language: language,
          directory: directory,
        );
        if (ticket != _playbackTicket) return;
        completeAudio = OfflineSpeechAudio.combine(
          completeAudio,
          bufferedSegment,
        );
        nextSegmentIndex++;
      }

      final player = FlutterPcmPlayer();
      _player = player;
      await player.initialize(
        nChannels: 1,
        sampleRate: first.sampleRate,
        pcmType: PCMType.pcm16,
      );
      await player.play();
      if (ticket != _playbackTicket) return;
      final playbackWatch = Stopwatch()..start();
      await _feedAudio(player, completeAudio.pcm, ticket);
      if (ticket != _playbackTicket) return;

      final estimatedDuration = Duration(
        milliseconds:
            (first.duration.inMilliseconds *
                    normalizedText.runes.length /
                    math.max(1, segments.first.runes.length))
                .ceil(),
      );
      _playbackDurations.add(estimatedDuration);
      _events.add(LocalSpeechEvent.started);

      OfflineSpeechAudio? lastSegment;
      for (final segment in segments.skip(nextSegmentIndex)) {
        lastSegment = await _generateSpeech(
          text: segment,
          language: language,
          directory: directory,
        );
        if (ticket != _playbackTicket) return;
        await _feedAudio(player, lastSegment.pcm, ticket);
        if (ticket != _playbackTicket) return;
        completeAudio = OfflineSpeechAudio.combine(completeAudio, lastSegment);
      }

      unawaited(
        cache
            .write(
              language: language,
              text: normalizedText,
              audio: completeAudio,
            )
            .catchError((_) {}),
      );
      final elapsed = playbackWatch.elapsed;
      playbackWatch.stop();
      final remainingFromTotal = completeAudio.duration - elapsed;
      final safeRemaining = _maxDuration(
        remainingFromTotal,
        lastSegment?.duration ?? completeAudio.duration,
      );
      _completionTimer = Timer(
        safeRemaining + const Duration(milliseconds: 300),
        () => unawaited(_completePlayback(ticket)),
      );
    } catch (_) {
      if (ticket == _playbackTicket) {
        await _releasePlayer();
        _events.add(LocalSpeechEvent.error);
      }
    }
  }

  Future<OfflineSpeechCache> _speechCache() {
    return _cachePreparing ??= () async {
      final support = await getApplicationSupportDirectory();
      return OfflineSpeechCache(
        Directory(
          '${support.path}${Platform.pathSeparator}offline_tts'
          '${Platform.pathSeparator}audio_cache_v1',
        ),
        formatVersion: 'models_v3_speed_1_silence_022_pcm16',
      );
    }();
  }

  Future<OfflineSpeechAudio> _generateSpeech({
    required String text,
    required OfflineSpeechLanguage language,
    required Directory directory,
  }) async {
    final result = await _sendRequest(<String, Object?>{
      'command': 'generate',
      'language': language.name,
      'modelDirectory': directory.path,
      'text': text,
    }).timeout(const Duration(minutes: 3));
    final transferable = result['pcm'];
    final sampleRate = result['sampleRate'];
    final sampleCount = result['sampleCount'];
    if (transferable is! TransferableTypedData ||
        sampleRate is! int ||
        sampleCount is! int ||
        sampleRate <= 0 ||
        sampleCount <= 0) {
      throw StateError('Offline speech generation returned no audio');
    }
    return OfflineSpeechAudio(
      sampleRate: sampleRate,
      sampleCount: sampleCount,
      pcm: transferable.materialize().asUint8List(),
    );
  }

  Future<void> _playCachedAudio(OfflineSpeechAudio audio, int ticket) async {
    final player = FlutterPcmPlayer();
    _player = player;
    await player.initialize(
      nChannels: 1,
      sampleRate: audio.sampleRate,
      pcmType: PCMType.pcm16,
    );
    await player.play();
    if (ticket != _playbackTicket) return;
    await _feedAudio(player, audio.pcm, ticket);
    if (ticket != _playbackTicket) return;
    _playbackDurations.add(audio.duration);
    _events.add(LocalSpeechEvent.started);
    _completionTimer = Timer(
      audio.duration + const Duration(milliseconds: 300),
      () => unawaited(_completePlayback(ticket)),
    );
  }

  Future<void> _feedAudio(
    FlutterPcmPlayer player,
    Uint8List pcm,
    int ticket,
  ) async {
    const chunkBytes = 64 * 1024;
    for (var offset = 0; offset < pcm.length; offset += chunkBytes) {
      if (ticket != _playbackTicket) return;
      final end = math.min(offset + chunkBytes, pcm.length);
      await player.feed(Uint8List.sublistView(pcm, offset, end));
    }
  }

  Duration _maxDuration(Duration left, Duration right) =>
      left > right ? left : right;

  Duration _offlinePrebufferTarget(
    OfflineSpeechLanguage language,
    Duration firstGenerationTime,
  ) {
    final minimumMilliseconds =
        language == OfflineSpeechLanguage.cantonese ? 9000 : 6000;
    final measuredMilliseconds = firstGenerationTime.inMilliseconds * 3 + 1500;
    return Duration(
      milliseconds: measuredMilliseconds.clamp(minimumMilliseconds, 18000),
    );
  }

  Future<Map<Object?, Object?>> _sendRequest(
    Map<String, Object?> message,
  ) async {
    final worker = _workerPort;
    if (worker == null) throw StateError('Offline speech worker is not ready');
    final id = ++_requestId;
    final completer = Completer<Map<Object?, Object?>>();
    _requests[id] = completer;
    worker.send(<String, Object?>{...message, 'id': id});
    late final Map<Object?, Object?> result;
    try {
      result = await completer.future;
    } finally {
      _requests.remove(id);
    }
    final error = result['error'];
    if (error != null) throw StateError(error.toString());
    return result;
  }

  Future<void> _completePlayback(int ticket) async {
    if (ticket != _playbackTicket) return;
    _completionTimer = null;
    await _releasePlayer();
    if (ticket == _playbackTicket) {
      _events.add(LocalSpeechEvent.completed);
    }
  }

  Future<void> stop() async {
    _playbackTicket++;
    _completionTimer?.cancel();
    _completionTimer = null;
    await _releasePlayer();
  }

  Future<void> _releasePlayer() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.release();
    } catch (_) {}
  }
}

class _OfflineModelSpec {
  const _OfflineModelSpec({
    required this.assetRoot,
    required this.versionDirectory,
  });

  final String assetRoot;
  final String versionDirectory;
}

void _offlineTtsWorker(SendPort mainPort) {
  sherpa_onnx.OfflineTts? tts;
  String? loadedLanguage;

  try {
    sherpa_onnx.initBindings();
  } catch (error) {
    mainPort.send(<String, Object?>{'startupError': error.toString()});
    return;
  }

  final commands = ReceivePort();
  mainPort.send(commands.sendPort);

  void ensureModel(String language, String modelDirectory) {
    if (loadedLanguage == language && tts != null) return;
    tts?.free();
    tts = null;
    loadedLanguage = null;

    final separator = Platform.pathSeparator;
    late final sherpa_onnx.OfflineTtsVitsModelConfig vits;
    var ruleFsts = '';
    switch (language) {
      case 'mandarin':
        vits = sherpa_onnx.OfflineTtsVitsModelConfig(
          model: '$modelDirectory${separator}zh_CN-xiao_ya-medium.onnx',
          lexicon: '$modelDirectory${separator}lexicon.txt',
          tokens: '$modelDirectory${separator}tokens.txt',
          lengthScale: 1.0,
        );
        ruleFsts = <String>[
          '$modelDirectory${separator}phone.fst',
          '$modelDirectory${separator}date.fst',
          '$modelDirectory${separator}number.fst',
        ].join(',');
      case 'cantonese':
        vits = sherpa_onnx.OfflineTtsVitsModelConfig(
          model: '$modelDirectory${separator}vits-cantonese-hf-xiaomaiiwn.onnx',
          lexicon: '$modelDirectory${separator}lexicon.txt',
          tokens: '$modelDirectory${separator}tokens.txt',
          lengthScale: 1.0,
        );
        ruleFsts = '$modelDirectory${separator}rule.fst';
      case 'english':
        vits = sherpa_onnx.OfflineTtsVitsModelConfig(
          model: '$modelDirectory${separator}en_US-amy-low.onnx',
          tokens: '$modelDirectory${separator}tokens.txt',
          dataDir: '$modelDirectory${separator}espeak-ng-data',
          lengthScale: 1.0,
        );
      default:
        throw StateError('Unsupported offline language: $language');
    }

    final model = sherpa_onnx.OfflineTtsModelConfig(
      vits: vits,
      numThreads: 4,
      debug: false,
      provider: 'cpu',
    );
    tts = sherpa_onnx.OfflineTts(
      sherpa_onnx.OfflineTtsConfig(
        model: model,
        ruleFsts: ruleFsts,
        maxNumSenetences: 1,
        silenceScale: 0.22,
      ),
    );
    loadedLanguage = language;
  }

  commands.listen((dynamic raw) {
    if (raw is! Map) return;
    final message = Map<Object?, Object?>.from(raw);
    final command = message['command'];
    if (command == 'dispose') {
      tts?.free();
      commands.close();
      return;
    }
    if (command != 'load' && command != 'generate') return;
    final id = message['id'];
    final language = message['language'];
    final modelDirectory = message['modelDirectory'];
    if (id is! int || language is! String || modelDirectory is! String) return;

    try {
      ensureModel(language, modelDirectory);
      if (command == 'load') {
        mainPort.send(<String, Object?>{'id': id, 'loaded': true});
        return;
      }
      final text = message['text'];
      if (text is! String) throw StateError('Missing speech text');
      final audio = tts!.generateWithConfig(
        text: text,
        config: const sherpa_onnx.OfflineTtsGenerationConfig(
          sid: 0,
          speed: 1.0,
          silenceScale: 0.22,
        ),
      );
      final pcm = Int16List(audio.samples.length);
      for (var index = 0; index < audio.samples.length; index++) {
        final sample = audio.samples[index].clamp(-1.0, 1.0);
        pcm[index] = (sample * 32767).round();
      }
      mainPort.send(<String, Object?>{
        'id': id,
        'sampleRate': audio.sampleRate,
        'sampleCount': pcm.length,
        'pcm': TransferableTypedData.fromList(<Uint8List>[
          pcm.buffer.asUint8List(),
        ]),
      });
    } catch (error) {
      mainPort.send(<String, Object?>{'id': id, 'error': error.toString()});
    }
  });
}
