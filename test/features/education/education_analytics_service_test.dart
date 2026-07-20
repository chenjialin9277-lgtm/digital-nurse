import 'package:digital_nurse/features/education/models/education_analytics_summary.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('汇总精确计算首次正确率、播放完成率和护士协助率', () {
    final summary = EducationAnalyticsSummary.fromEvents(
      _sampleEducationEvents(),
    );

    expect(summary.sessionCount, 2);
    expect(summary.playCount, 3);
    expect(summary.playbackCompletedCount, 2);
    expect(summary.completionRate, closeTo(2 / 3, 0.001));
    expect(summary.firstAttemptAnswerCount, 3);
    expect(summary.firstAttemptCorrectCount, 2);
    expect(summary.firstAttemptCorrectRate, closeTo(2 / 3, 0.001));
    expect(summary.replayCount, 1);
    expect(summary.nurseHelpCount, 1);
    expect(summary.completedSessionCount, 2);
    expect(summary.nurseHelpRate, closeTo(1 / 2, 0.001));
    expect(summary.languageCounts[OfflineSpeechLanguage.mandarin], 2);
    expect(summary.languageCounts[OfflineSpeechLanguage.cantonese], 1);
  });

  test('空数据的所有比率均为0而不是NaN', () {
    final summary = EducationAnalyticsSummary.fromEvents(const []);

    expect(summary.completionRate, 0);
    expect(summary.firstAttemptCorrectRate, 0);
    expect(summary.nurseHelpRate, 0);
    expect(summary.completionRate.isNaN, isFalse);
  });
}

List<EducationSessionEvent> _sampleEducationEvents() {
  final time = DateTime.utc(2026, 7, 20, 8);
  EducationSessionEvent event(
    String id,
    String session,
    EducationEventType type, {
    OfflineSpeechLanguage? language,
    int? attempt,
    int? value,
  }) => EducationSessionEvent(
    id: id,
    sessionId: session,
    departmentId: 'emergency_ward',
    itemId: type == EducationEventType.sessionStarted ? null : 'admission',
    itemVersion: type == EducationEventType.sessionStarted ? null : 1,
    language: language,
    type: type,
    attempt: attempt,
    value: value,
    occurredAt: time.add(Duration(minutes: int.parse(id))),
  );

  return [
    event(
      '01',
      's1',
      EducationEventType.sessionStarted,
      language: OfflineSpeechLanguage.mandarin,
    ),
    event(
      '02',
      's1',
      EducationEventType.playbackStarted,
      language: OfflineSpeechLanguage.mandarin,
    ),
    event(
      '03',
      's1',
      EducationEventType.playbackCompleted,
      language: OfflineSpeechLanguage.mandarin,
    ),
    event('04', 's1', EducationEventType.answer, attempt: 1, value: 1),
    event('05', 's1', EducationEventType.replay),
    event(
      '06',
      's1',
      EducationEventType.playbackStarted,
      language: OfflineSpeechLanguage.mandarin,
    ),
    event(
      '07',
      's1',
      EducationEventType.playbackCompleted,
      language: OfflineSpeechLanguage.mandarin,
    ),
    event('08', 's1', EducationEventType.answer, attempt: 1, value: 0),
    event('09', 's1', EducationEventType.nurseHelp),
    event('10', 's1', EducationEventType.sessionCompleted),
    event(
      '11',
      's2',
      EducationEventType.sessionStarted,
      language: OfflineSpeechLanguage.cantonese,
    ),
    event(
      '12',
      's2',
      EducationEventType.playbackStarted,
      language: OfflineSpeechLanguage.cantonese,
    ),
    event('13', 's2', EducationEventType.answer, attempt: 1, value: 1),
    event('14', 's2', EducationEventType.sessionCompleted),
  ];
}
