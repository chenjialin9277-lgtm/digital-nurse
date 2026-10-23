import 'package:flutter/services.dart';

enum PCMType { pcm8, pcm16, pcm32 }

enum PlayState { stopped, playing, paused }

class FlutterPcmPlayer {
  static const MethodChannel _channel = MethodChannel('flutter_pcm_player');

  bool _isInitialized = false;
  PlayState _playState = PlayState.stopped;

  bool get isInited => _isInitialized;
  PlayState get playState => _playState;

  Future<void> initialize({
    int nChannels = 1,
    int sampleRate = 16000,
    PCMType pcmType = PCMType.pcm16,
  }) async {
    if (_isInitialized) await release();
    await _channel.invokeMethod<void>('initialize', <String, int>{
      'nChannels': nChannels,
      'sampleRate': sampleRate,
      'pcmType': pcmType.index,
    });
    _playState = PlayState.stopped;
    _isInitialized = true;
  }

  Future<void> play() async {
    _ensureInitialized();
    _playState = await _invokeState('play');
  }

  Future<void> stop() async {
    if (!_isInitialized) return;
    _playState = await _invokeState('stop');
  }

  Future<void> pause() async {
    _ensureInitialized();
    _playState = await _invokeState('pause');
  }

  Future<void> resume() async {
    _ensureInitialized();
    _playState = await _invokeState('resume');
  }

  Future<void> feed(Uint8List data) async {
    _ensureInitialized();
    final state = await _channel.invokeMethod<int>(
      'feed',
      <String, Object>{'data': data},
    );
    if (state != null) _playState = PlayState.values[state];
  }

  Future<void> release() async {
    if (!_isInitialized) return;
    await _channel.invokeMethod<void>('release');
    _playState = PlayState.stopped;
    _isInitialized = false;
  }

  Future<PlayState> _invokeState(String method) async {
    final state = await _channel.invokeMethod<int>(method);
    return PlayState.values[state ?? PlayState.stopped.index];
  }

  void _ensureInitialized() {
    if (!_isInitialized) throw StateError('PCM player is not initialized');
  }
}
