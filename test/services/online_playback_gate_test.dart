import 'dart:typed_data';

import 'package:digital_nurse/services/online_playback_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frames and audio ownership transitions run in strict order', () async {
    final calls = <String>[];
    final gate = OnlinePlaybackGate(
      playFrame: (frame) async => calls.add('frame:${frame.first}'),
      stopPlayer: () async => calls.add('stop'),
      startPlayer: () async => calls.add('start'),
    );

    await gate.enqueueFrame(Uint8List.fromList([1]));
    await gate.suspend();
    await gate.enqueueFrame(Uint8List.fromList([2]));
    await gate.resume();
    await gate.enqueueFrame(Uint8List.fromList([3]));

    expect(calls, ['frame:1', 'stop', 'start', 'frame:3']);
  });

  test(
    'concurrent suspend and resume calls transition ownership once',
    () async {
      final calls = <String>[];
      final gate = OnlinePlaybackGate(
        playFrame: (_) async {},
        stopPlayer: () async => calls.add('stop'),
        startPlayer: () async => calls.add('start'),
      );

      await Future.wait([gate.suspend(), gate.suspend()]);
      await Future.wait([gate.resume(), gate.resume()]);

      expect(calls, ['stop', 'start']);
    },
  );
}
