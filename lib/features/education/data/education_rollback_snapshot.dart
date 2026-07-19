import '../../../models/nurse_app_config.dart';
import '../../../models/offline_speech_language.dart';
import '../models/education_item.dart';

List<LocalQuickAnswer> buildEducationRollbackSnapshot(
  List<EducationItem> items,
) {
  return items
      .where(
        (item) =>
            item.enabled && item.isAvailableIn(OfflineSpeechLanguage.mandarin),
      )
      .map((item) {
        final mandarin = item.contentFor(OfflineSpeechLanguage.mandarin);
        final cantonese = item.contentFor(OfflineSpeechLanguage.cantonese);
        final english = item.contentFor(OfflineSpeechLanguage.english);
        return LocalQuickAnswer(
          title: mandarin.title,
          answer: mandarin.body,
          cantoneseTitle:
              item.isAvailableIn(OfflineSpeechLanguage.cantonese)
                  ? cantonese.title
                  : mandarin.title,
          cantoneseAnswer:
              item.isAvailableIn(OfflineSpeechLanguage.cantonese)
                  ? cantonese.body
                  : mandarin.body,
          englishTitle:
              item.isAvailableIn(OfflineSpeechLanguage.english)
                  ? english.title
                  : mandarin.title,
          englishAnswer:
              item.isAvailableIn(OfflineSpeechLanguage.english)
                  ? english.body
                  : mandarin.body,
        );
      })
      .toList(growable: false);
}
