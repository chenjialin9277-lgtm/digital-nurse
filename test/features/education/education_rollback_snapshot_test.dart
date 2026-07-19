import 'package:digital_nurse/features/education/data/education_rollback_snapshot.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';

void main() {
  test('回退快照排除未发布草稿', () {
    final draftContent = reviewedItem
        .contentFor(OfflineSpeechLanguage.mandarin)
        .copyWith(published: false, needsReview: true);
    final draft = reviewedItem.copyWith(
      id: 'draft',
      contents: {
        ...reviewedItem.contents,
        OfflineSpeechLanguage.mandarin: draftContent,
      },
    );

    expect(buildEducationRollbackSnapshot([draft]), isEmpty);
  });

  test('回退快照仅收录可播普通话并为未发布翻译兜底', () {
    final mandarinOnly = educationFixture(
      includeCantonese: false,
      includeEnglish: false,
    );

    final snapshot = buildEducationRollbackSnapshot([mandarinOnly]);

    expect(snapshot, hasLength(1));
    expect(snapshot.single.title, '入院注意事项');
    expect(snapshot.single.cantoneseTitle, snapshot.single.title);
    expect(snapshot.single.englishAnswer, snapshot.single.answer);
  });
}
