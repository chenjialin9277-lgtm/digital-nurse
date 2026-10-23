import 'dart:typed_data';

import 'package:digital_nurse/services/online_audio_prebuffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('在线音频先积累安全帧数再一次释放', () {
    final buffer = OnlineAudioPrebuffer(minimumFrames: 3);

    expect(buffer.add(Uint8List.fromList([1])), isEmpty);
    expect(buffer.add(Uint8List.fromList([2])), isEmpty);
    expect(buffer.pendingFrameCount, 2);

    final ready = buffer.add(Uint8List.fromList([3]));
    expect(ready.map((frame) => frame.first), [1, 2, 3]);
    expect(buffer.started, isTrue);
    expect(buffer.pendingFrameCount, 0);
    expect(buffer.add(Uint8List.fromList([4])).single.first, 4);
  });

  test('重置后重新等待完整预缓冲', () {
    final buffer = OnlineAudioPrebuffer(minimumFrames: 2);
    buffer.add(Uint8List.fromList([1]));
    buffer.add(Uint8List.fromList([2]));

    buffer.reset();

    expect(buffer.started, isFalse);
    expect(buffer.add(Uint8List.fromList([3])), isEmpty);
    expect(buffer.add(Uint8List.fromList([4])).map((frame) => frame.first), [
      3,
      4,
    ]);
  });
}
