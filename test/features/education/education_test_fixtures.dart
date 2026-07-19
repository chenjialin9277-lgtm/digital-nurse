import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_language_content.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';

EducationItem educationFixture({
  String id = 'admission',
  String category = '入院宣教',
  int sortOrder = 0,
  bool includeCantonese = true,
  bool includeEnglish = true,
}) {
  final contents = <OfflineSpeechLanguage, EducationLanguageContent>{
    OfflineSpeechLanguage.mandarin: const EducationLanguageContent(
      title: '入院注意事项',
      body: '请配合护士完成身份核对。',
      summary: '配合身份核对',
      question: '办理入院后应该怎么做？',
      options: ['配合护士核对身份', '自行离开病区'],
      correctIndex: 0,
      explanation: '应配合护士完成身份核对。',
      published: true,
      needsReview: false,
    ),
  };
  if (includeCantonese) {
    contents[OfflineSpeechLanguage.cantonese] = const EducationLanguageContent(
      title: '入院须知',
      body: '请配合护士核对身份。',
      summary: '配合身份核对',
      question: '办理入院之后应该点做？',
      options: ['配合护士核对身份', '自行离开病区'],
      correctIndex: 0,
      explanation: '应该配合护士完成身份核对。',
      published: true,
      needsReview: false,
    );
  }
  if (includeEnglish) {
    contents[OfflineSpeechLanguage.english] = const EducationLanguageContent(
      title: 'Admission Information',
      body: 'Please cooperate with identity verification.',
      summary: 'Complete identity verification',
      question: 'What should you do after admission?',
      options: ['Cooperate with the nurse', 'Leave the ward alone'],
      correctIndex: 0,
      explanation: 'Please cooperate with the nurse.',
      published: true,
      needsReview: false,
    );
  }
  return EducationItem(
    id: id,
    category: category,
    contents: contents,
    estimatedManualMinutes: 3,
    sortOrder: sortOrder,
    favorite: true,
    enabled: true,
    version: 1,
    createdAt: DateTime.utc(2026, 7, 19),
    updatedAt: DateTime.utc(2026, 7, 19),
  );
}

final EducationItem reviewedItem = educationFixture();

LocalQuickAnswer customLegacyAnswer(int index) => LocalQuickAnswer(
  title: '旧版自定义宣教${index + 1}',
  answer: '旧版普通话内容${index + 1}',
  cantoneseTitle: '旧版粤语宣教${index + 1}',
  cantoneseAnswer: '旧版粤语内容${index + 1}',
  englishTitle: 'Legacy Education ${index + 1}',
  englishAnswer: 'Legacy English content ${index + 1}',
);
