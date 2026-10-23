import 'dart:async';
import 'dart:typed_data';

import 'online_playback_gate.dart';

class PushToTalkAudioSession {
  PushToTalkAudioSession({
    required this.playback,
    required this.microphoneFrames,
    required this.startMicrophone,
    required this.stopMicrophone,
    required this.sendStart,
    required this.sendAudio,
    required this.sendStop,
  });

  final OnlinePlaybackGate playback;
  final Stream<Uint8List> microphoneFrames;
  final Future<void> Function() startMicrophone;
  final Future<void> Function() stopMicrophone;
  final void Function() sendStart;
  final void Function(Uint8List) sendAudio;
  final void Function() sendStop;

  StreamSubscription<Uint8List>? _microphoneSubscription;
  bool _started = false;

  Future<void> start() async {
    if (_started || _microphoneSubscription != null) return;

    await playback.suspend();
    _microphoneSubscription = microphoneFrames.listen(sendAudio);
    try {
      sendStart();
      await startMicrophone();
      _started = true;
    } catch (_) {
      await _microphoneSubscription?.cancel();
      _microphoneSubscription = null;
      try {
        await playback.resume();
      } finally {
        sendStop();
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_started && _microphoneSubscription == null) return;

    try {
      if (_started) await stopMicrophone();
    } finally {
      _started = false;
      await _microphoneSubscription?.cancel();
      _microphoneSubscription = null;
      try {
        await playback.resume();
      } finally {
        sendStop();
      }
    }
  }
}
