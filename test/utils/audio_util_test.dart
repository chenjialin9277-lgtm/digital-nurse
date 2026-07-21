import 'package:digital_nurse/utils/audio_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_pcm_player');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await AudioUtil.stopPlaying();
  });

  test('player initialization failure is reported to the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') {
            throw PlatformException(code: 'init_failed');
          }
          return null;
        });

    await expectLater(
      AudioUtil.initPlayer(),
      throwsA(isA<PlatformException>()),
    );
  });
}
