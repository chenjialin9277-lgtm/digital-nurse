import 'dart:typed_data';

import 'package:digital_nurse/services/microphone_capture_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('five encoded frames with two voiced PCM frames are valid', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      final frame = Int16List(960);
      if (index < 2) frame[0] = 512;
      tracker.addPcmFrame(Uint8List.view(frame.buffer));
      tracker.markEncodedFrame();
    }

    final result = tracker.finish();
    expect(result.hasValidSpeech, isTrue);
    expect(result.encodedFrameCount, 5);
    expect(result.voicedFrameCount, 2);
    expect(result.peakAmplitude, 512);
  });

  test('silent PCM is rejected even when frame count is sufficient', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      tracker.addPcmFrame(Uint8List(1920));
      tracker.markEncodedFrame();
    }

    final result = tracker.finish();
    expect(result.hasValidSpeech, isFalse);
    expect(result.voicedFrameCount, 0);
    expect(result.peakAmplitude, 0);
  });

  test('short captures are rejected even when they contain speech', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 4; index++) {
      final frame = Int16List(960)..[0] = 512;
      tracker.addPcmFrame(Uint8List.view(frame.buffer));
      tracker.markEncodedFrame();
    }

    expect(tracker.finish().hasValidSpeech, isFalse);
  });

  test('stream errors invalidate otherwise valid speech', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      final frame = Int16List(960)..[0] = 512;
      tracker.addPcmFrame(Uint8List.view(frame.buffer));
      tracker.markEncodedFrame();
    }
    tracker.markStreamError(StateError('stream stopped'));

    final result = tracker.finish();
    expect(result.hasValidSpeech, isFalse);
    expect(result.streamFailed, isTrue);
  });
}
