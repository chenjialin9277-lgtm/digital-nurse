import 'dart:collection';

import '../../../models/offline_speech_language.dart';
import 'education_session_event.dart';

class EducationAnalyticsSummary {
  EducationAnalyticsSummary({
    required this.sessionCount,
    required this.playCount,
    required this.playbackCompletedCount,
    required this.completedSessionCount,
    required this.replayCount,
    required this.firstAttemptAnswerCount,
    required this.firstAttemptCorrectCount,
    required this.nurseHelpCount,
    required Map<OfflineSpeechLanguage, int> languageCounts,
    this.estimatedSavedMinutes = 0,
  }) : languageCounts = UnmodifiableMapView(languageCounts);

  final int sessionCount;
  final int playCount;
  final int playbackCompletedCount;
  final int completedSessionCount;
  final int replayCount;
  final int firstAttemptAnswerCount;
  final int firstAttemptCorrectCount;
  final int nurseHelpCount;
  final Map<OfflineSpeechLanguage, int> languageCounts;
  final int estimatedSavedMinutes;

  double get completionRate =>
      playCount == 0 ? 0 : playbackCompletedCount / playCount;

  double get firstAttemptCorrectRate =>
      firstAttemptAnswerCount == 0
          ? 0
          : firstAttemptCorrectCount / firstAttemptAnswerCount;

  double get nurseHelpRate =>
      completedSessionCount == 0 ? 0 : nurseHelpCount / completedSessionCount;

  factory EducationAnalyticsSummary.fromEvents(
    List<EducationSessionEvent> events, {
    Map<String, int> estimatedMinutesByItem = const {},
  }) {
    final sessions = <String>{};
    final completedSessions = <String>{};
    final nurseHelpSessions = <String>{};
    final languages = {
      for (final language in OfflineSpeechLanguage.values) language: 0,
    };
    var plays = 0;
    var playbackCompleted = 0;
    var replays = 0;
    var firstAnswers = 0;
    var firstCorrect = 0;
    var estimatedMinutes = 0;

    for (final event in events) {
      switch (event.type) {
        case EducationEventType.sessionStarted:
          sessions.add(event.sessionId);
        case EducationEventType.playbackStarted:
          plays++;
          final language = event.language;
          if (language != null) languages[language] = languages[language]! + 1;
        case EducationEventType.playbackCompleted:
          playbackCompleted++;
          estimatedMinutes += estimatedMinutesByItem[event.itemId] ?? 0;
        case EducationEventType.answer:
          if (event.attempt == 1) {
            firstAnswers++;
            if (event.value == 1) firstCorrect++;
          }
        case EducationEventType.replay:
          replays++;
        case EducationEventType.nurseHelp:
          nurseHelpSessions.add(event.sessionId);
        case EducationEventType.sessionCompleted:
          completedSessions.add(event.sessionId);
        case EducationEventType.itemSelected:
        case EducationEventType.sessionCleared:
          break;
      }
    }

    return EducationAnalyticsSummary(
      sessionCount: sessions.length,
      playCount: plays,
      playbackCompletedCount: playbackCompleted,
      completedSessionCount: completedSessions.length,
      replayCount: replays,
      firstAttemptAnswerCount: firstAnswers,
      firstAttemptCorrectCount: firstCorrect,
      nurseHelpCount: nurseHelpSessions.length,
      languageCounts: languages,
      estimatedSavedMinutes: estimatedMinutes,
    );
  }
}
