import 'dart:typed_data';

class OnlinePlaybackGate {
  OnlinePlaybackGate({
    required this.playFrame,
    required this.stopPlayer,
    required this.startPlayer,
  });

  final Future<void> Function(Uint8List) playFrame;
  final Future<void> Function() stopPlayer;
  final Future<void> Function() startPlayer;
  Future<void> _tail = Future<void>.value();
  bool _suspended = false;

  Future<void> enqueueFrame(Uint8List frame) => _serial(() async {
    if (!_suspended) await playFrame(frame);
  });

  Future<void> suspend() => _serial(() async {
    if (_suspended) return;
    _suspended = true;
    await stopPlayer();
  });

  Future<void> resume() => _serial(() async {
    if (!_suspended) return;
    await startPlayer();
    _suspended = false;
  });

  Future<void> stop() => _serial(stopPlayer);

  /// Starts a fresh server utterance with an empty native player and jitter
  /// buffer. Binary frames queued immediately afterwards remain ordered behind
  /// this reset.
  Future<void> beginUtterance() => _serial(() async {
    if (!_suspended) await stopPlayer();
  });

  Future<void> _serial(Future<void> Function() operation) {
    final current = _tail.then((_) => operation());
    _tail = current.then<void>((_) {}, onError: (_, __) {});
    return current;
  }
}
