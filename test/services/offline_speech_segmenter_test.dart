import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/services/offline_speech_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('普通话长宣教先生成较短首段且不丢失正文', () {
    const text = '办理入院后，请先配合护士完成身份核对和入院评估。请妥善保管贵重物品，并遵守病区安全规定。';

    final segments = splitSpeechForFastStart(
      text,
      OfflineSpeechLanguage.mandarin,
    );

    expect(segments, hasLength(2));
    expect(segments.first.runes.length, lessThanOrEqualTo(34));
    expect(segments.join(), text);
  });

  test('粤语长宣教同样采用快速首段', () {
    const text = '办理入院之后，请先配合护士核对身份同完成评估。请妥善保管贵重物品，并遵守病区安全规定。';

    final segments = splitSpeechForFastStart(
      text,
      OfflineSpeechLanguage.cantonese,
    );

    expect(segments, hasLength(2));
    expect(segments.first.runes.length, lessThanOrEqualTo(34));
    expect(segments.join(), text);
  });

  test('英语长宣教优先在自然标点处分段', () {
    const text =
        'After admission, please cooperate with the identity check and nursing assessment. Keep your valuables safe and follow all ward safety instructions.';

    final segments = splitSpeechForFastStart(
      text,
      OfflineSpeechLanguage.english,
    );

    expect(segments, hasLength(2));
    expect(segments.first, endsWith('.'));
    expect(segments.first.runes.length, lessThanOrEqualTo(100));
    expect(segments.join(), text);
  });

  test('短宣教不进行无意义切分', () {
    const text = '请按呼叫铃联系护士。';

    expect(splitSpeechForFastStart(text, OfflineSpeechLanguage.mandarin), [
      text,
    ]);
  });

  test('很长的宣教会连续切成可流式合成的小段', () {
    final text = List.filled(8, '住院期间请遵守病区安全规定，并在需要帮助时及时联系护士。').join();

    final segments = splitSpeechForFastStart(
      text,
      OfflineSpeechLanguage.mandarin,
    );

    expect(segments.length, greaterThan(2));
    expect(segments.every((segment) => segment.runes.length <= 28), isTrue);
    expect(segments.join(), text);
  });
}
