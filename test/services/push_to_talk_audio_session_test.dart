import 'dart:async';
import 'dart:typed_data';

import 'package:digital_nurse/services/online_playback_gate.dart';
import 'package:digital_nurse/services/push_to_talk_audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按住说话会先释放播放器并保留完整麦克风音频', () async {
    final events = <String>[];
    final microphone = StreamController<Uint8List>.broadcast(sync: true);
    addTearDown(microphone.close);
    final playback = OnlinePlaybackGate(
      playFrame: (_) async {},
      stopPlayer: () async => events.add('player-stop'),
      startPlayer: () async => events.add('player-start'),
    );
    final session = PushToTalkAudioSession(
      playback: playback,
      microphoneFrames: microphone.stream,
      startMicrophone: () async {
        events.add('microphone-start');
        microphone.add(Uint8List.fromList(<int>[1, 2, 3]));
      },
      stopMicrophone: () async => events.add('microphone-stop'),
      sendStart: () => events.add('listen-start'),
      sendAudio: (frame) => events.add('audio:${frame.length}'),
      sendStop: () => events.add('listen-stop'),
    );

    await session.start();
    await session.stop();

    expect(events, <String>[
      'player-stop',
      'listen-start',
      'microphone-start',
      'audio:3',
      'microphone-stop',
      'player-start',
      'listen-stop',
    ]);
  });
}
