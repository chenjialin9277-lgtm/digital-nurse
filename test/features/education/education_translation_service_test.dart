import 'package:digital_nurse/features/education/models/education_language_content.dart';
import 'package:digital_nurse/features/education/services/education_translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = EducationLanguageContent(
    title: '出院用药',
    body: '请按医嘱服药，不要自行改变剂量。',
    summary: '按医嘱服药',
    question: '服药时应该怎么做？',
    options: ['按医嘱服药', '自行加量'],
    correctIndex: 0,
    explanation: '自行改变剂量可能影响治疗安全。',
    published: true,
    needsReview: false,
  );

  test('小智返回的两种翻译会转换为待复核草稿', () async {
    late String prompt;
    final service = EducationTranslationService(
      requestText: (value) async {
        prompt = value;
        return '''
```json
{"cantonese":{"title":"出院食药","body":"请跟医嘱食药，唔好自己改变剂量。","summary":"跟医嘱食药","question":"食药嗰阵应该点做？","options":["跟医嘱食药","自己加量"],"correctIndex":0,"explanation":"自己改变剂量可能会影响治疗安全。"},"english":{"title":"Discharge medication","body":"Take your medicine as prescribed. Do not change the dose yourself.","summary":"Follow the prescription","question":"How should you take your medicine?","options":["Follow the prescription","Increase the dose yourself"],"correctIndex":0,"explanation":"Changing the dose yourself may affect treatment safety."}}
```
''';
      },
    );

    final result = await service.translateFromMandarin(source);

    expect(prompt, contains('不要自行改变剂量'));
    expect(result.cantonese.body, contains('唔好自己改变剂量'));
    expect(result.english.title, 'Discharge medication');
    expect(result.cantonese.published, isFalse);
    expect(result.english.published, isFalse);
    expect(result.cantonese.needsReview, isTrue);
    expect(result.english.needsReview, isTrue);
  });

  test('翻译改变正确答案位置时拒绝导入', () async {
    final service = EducationTranslationService(
      requestText:
          (_) async =>
              '{"cantonese":{"title":"A","body":"B","summary":"","question":"Q","options":["1","2"],"correctIndex":1,"explanation":"E"},"english":{"title":"A","body":"B","summary":"","question":"Q","options":["1","2"],"correctIndex":0,"explanation":"E"}}',
    );

    await expectLater(
      service.translateFromMandarin(source),
      throwsA(isA<FormatException>()),
    );
  });
}
