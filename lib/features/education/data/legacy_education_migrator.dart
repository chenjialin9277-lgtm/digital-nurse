import '../../../models/nurse_app_config.dart';
import '../../../models/offline_speech_language.dart';
import '../models/education_item.dart';
import '../models/education_language_content.dart';
import 'default_education_items.dart';
import 'education_repository.dart';

class LegacyEducationMigrator {
  const LegacyEducationMigrator({required this.repository});

  final EducationRepository repository;

  Future<void> migrateIfNeeded(NurseAppConfig config) async {
    if (await repository.isLegacyMigrationCompleted()) return;

    final timestamp = DateTime.now().toUtc();
    final defaults = buildDefaultEducationItems(now: timestamp);
    final migrated = <EducationItem>[];
    for (var index = 0; index < config.quickAnswers.length; index++) {
      final answer = config.quickAnswers[index];
      if (index < NurseAppConfig.defaultQuickAnswers.length &&
          _sameAnswer(answer, NurseAppConfig.defaultQuickAnswers[index])) {
        migrated.add(defaults[index].copyWith(sortOrder: index));
      } else {
        migrated.add(_migrateCustom(answer, index, timestamp));
      }
    }

    await repository.replaceAllAndMarkLegacyMigrated(migrated);
  }

  EducationItem _migrateCustom(
    LocalQuickAnswer answer,
    int index,
    DateTime timestamp,
  ) => EducationItem(
    id: 'legacy_quick_answer_${(index + 1).toString().padLeft(3, '0')}',
    category: '科室自定义',
    contents: {
      for (final language in OfflineSpeechLanguage.values)
        language: _temporaryContent(answer, language),
    },
    estimatedManualMinutes: 3,
    sortOrder: index,
    favorite: index < 4,
    enabled: true,
    version: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  EducationLanguageContent _temporaryContent(
    LocalQuickAnswer answer,
    OfflineSpeechLanguage language,
  ) {
    final title = answer.titleFor(language);
    final body = answer.answerFor(language);
    final prompt = switch (language) {
      OfflineSpeechLanguage.mandarin => (
        question: '您是否理解以上宣教内容？',
        options: const ['我已理解', '请再播放一次', '请护士进一步解释'],
        explanation: '这是旧版内容自动生成的理解确认，请科室管理员尽快复核。',
      ),
      OfflineSpeechLanguage.cantonese => (
        question: '您係否明白以上宣教内容？',
        options: const ['我已明白', '请再播放一次', '请护士进一步解释'],
        explanation: '呢个係旧版内容自动生成嘅理解确认，请科室管理员尽快复核。',
      ),
      OfflineSpeechLanguage.english => (
        question: 'Do you understand the education above?',
        options: const [
          'I understand',
          'Play it again',
          'Please ask the nurse to explain',
        ],
        explanation:
            'This confirmation was generated from legacy content and requires department review.',
      ),
    };
    return EducationLanguageContent(
      title: title,
      body: body,
      summary: title,
      question: prompt.question,
      options: prompt.options,
      correctIndex: 0,
      explanation: prompt.explanation,
      published: title.trim().isNotEmpty && body.trim().isNotEmpty,
      needsReview: true,
    );
  }

  bool _sameAnswer(LocalQuickAnswer left, LocalQuickAnswer right) =>
      left.title == right.title &&
      left.answer == right.answer &&
      left.cantoneseTitle == right.cantoneseTitle &&
      left.cantoneseAnswer == right.cantoneseAnswer &&
      left.englishTitle == right.englishTitle &&
      left.englishAnswer == right.englishAnswer;
}
