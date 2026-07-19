import 'package:digital_nurse/features/education/data/legacy_education_migrator.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'fake_education_repository.dart';

void main() {
  test('应用内置宣教迁移后保留已复核理解题', () async {
    final config = NurseAppConfig.defaults('device', 'client');
    final repository = FakeEducationRepository();
    final migrator = LegacyEducationMigrator(repository: repository);

    await migrator.migrateIfNeeded(config);

    final first = (await repository.loadActive()).first;
    final content = first.contentFor(OfflineSpeechLanguage.mandarin);
    expect(content.needsReview, isFalse);
    expect(content.question, isNot('您是否理解以上宣教内容？'));
    expect(content.options, hasLength(greaterThanOrEqualTo(2)));
  });

  test('旧版自定义宣教全部保留并生成待复核理解题', () async {
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(quickAnswers: List.generate(12, customLegacyAnswer));
    final repository = FakeEducationRepository();
    final migrator = LegacyEducationMigrator(repository: repository);

    await migrator.migrateIfNeeded(config);
    final items = await repository.loadActive();

    expect(items, hasLength(12));
    expect(
      items.first.contentFor(OfflineSpeechLanguage.mandarin).body,
      config.quickAnswers.first.answer,
    );
    expect(
      items.first.contentFor(OfflineSpeechLanguage.mandarin).needsReview,
      isTrue,
    );
    expect(items.first.isAvailableIn(OfflineSpeechLanguage.mandarin), isTrue);
    expect(repository.atomicMigrationWrites, 1);
  });

  test('迁移重复执行不会产生重复宣教', () async {
    final config = NurseAppConfig.defaults('device', 'client');
    final repository = FakeEducationRepository();
    final migrator = LegacyEducationMigrator(repository: repository);

    await migrator.migrateIfNeeded(config);
    await migrator.migrateIfNeeded(config);

    expect(
      await repository.loadActive(),
      hasLength(config.quickAnswers.length),
    );
    expect(repository.atomicMigrationWrites, 1);
  });
}
