import 'dart:typed_data';

/// Keeps a small amount of decoded online audio before playback starts.
///
/// Xiaozhi sends speech in short real-time frames. Starting Android's
/// AudioTrack from the first frame leaves no protection against ordinary Wi-Fi
/// jitter, which is heard as intermittent silence. Once [minimumFrames] have
/// arrived, the buffered frames are released together and later frames pass
/// through immediately.
class OnlineAudioPrebuffer {
  OnlineAudioPrebuffer({this.minimumFrames = 8}) : assert(minimumFrames > 0);

  final int minimumFrames;
  final List<Uint8List> _pending = [];
  bool _started = false;

  bool get started => _started;
  int get pendingFrameCount => _pending.length;

  List<Uint8List> add(Uint8List frame) {
    if (_started) return <Uint8List>[frame];
    _pending.add(frame);
    if (_pending.length < minimumFrames) return const <Uint8List>[];
    _started = true;
    final ready = List<Uint8List>.unmodifiable(_pending);
    _pending.clear();
    return ready;
  }

  /// Keeps pass-through mode after the native player is recreated. Player
  /// initialization clears stale packets, but the batch already held by the
  /// caller is about to be fed and therefore represents a valid new stream.
  void markStarted() {
    _pending.clear();
    _started = true;
  }

  void reset() {
    _pending.clear();
    _started = false;
  }
}
