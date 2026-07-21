import 'dart:async';

import 'package:digital_nurse/features/education/controllers/education_session_controller.dart';
import 'package:digital_nurse/features/education/data/education_event_repository.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'fake_education_event_repository.dart';

void main() {
  test(
    'playback-start persistence failure leaves session ready to retry',
    () async {
      final events =
          FakeEducationEventRepository()
            ..failOnType = EducationEventType.playbackStarted;
      final controller = EducationSessionController(
        events: events,
        departmentId: 'emergency_ward',
      );
      await controller.startSession(OfflineSpeechLanguage.mandarin);
      await controller.selectItem(reviewedItem);

      await expectLater(controller.beginPlayback(), throwsStateError);

      expect(controller.state.stage, EducationSessionStage.ready);
      expect(controller.state.selectedItem, reviewedItem);
    },
  );

  test(
    'exit while playback-start event is saving cannot re-enter playing',
    () async {
      final events = _BlockingPlaybackStartRepository();
      final controller = EducationSessionController(
        events: events,
        departmentId: 'emergency_ward',
      );
      await controller.startSession(OfflineSpeechLanguage.mandarin);
      await controller.selectItem(reviewedItem);

      final playback = controller.beginPlayback();
      await Future<void>.delayed(Duration.zero);
      await controller.clearTransientState();
      events.releasePlaybackStart();
      await playback;

      expect(controller.state.stage, EducationSessionStage.idle);
      expect(controller.state.selectedItem, isNull);
    },
  );

  test('播报结束后显示理解题，答对后完成本次理解确认', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );

    await controller.startSession(OfflineSpeechLanguage.mandarin);
    await controller.selectItem(reviewedItem);
    await controller.beginPlayback();
    await controller.markSpeechComplete();
    expect(controller.state.stage, EducationSessionStage.question);

    await controller.submitAnswer(0);
    expect(controller.state.result?.isCorrect, isTrue);
    expect(controller.state.feedbackTitle, '本次理解确认完成');
    expect(
      events.saved.map((event) => event.type),
      contains(EducationEventType.answer),
    );
  });

  test('不理解时可重播，也可请护士进一步解释', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await controller.startSession(OfflineSpeechLanguage.cantonese);
    await controller.selectItem(reviewedItem);
    await controller.beginPlayback();
    await controller.markSpeechComplete();

    await controller.submitAnswer(1);
    expect(controller.state.result?.isCorrect, isFalse);
    await controller.replay();
    expect(controller.state.stage, EducationSessionStage.ready);

    await controller.requestNurseHelp();
    expect(controller.state.nurseHelpRequested, isTrue);
    expect(controller.state.feedbackTitle, '请护士进一步解释');
    expect(
      events.saved.map((event) => event.type),
      containsAll([EducationEventType.replay, EducationEventType.nurseHelp]),
    );
  });

  test('结束会话清空患者端内容，仅保留匿名事件', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await controller.startSession(OfflineSpeechLanguage.english);
    await controller.selectItem(reviewedItem);
    await controller.beginPlayback();
    controller.updateVisibleCaption('请配合护士');
    expect(controller.state.visibleCaption, isNotEmpty);

    await controller.finishSession();

    expect(controller.state.stage, EducationSessionStage.idle);
    expect(controller.state.selectedItem, isNull);
    expect(controller.state.visibleCaption, isEmpty);
    expect(events.saved, isNotEmpty);
    for (final event in events.saved) {
      expect(
        event.toJson().keys,
        everyElement(
          isNot(
            isIn([
              'patientName',
              'hospitalNumber',
              'bedNumber',
              'phone',
              'diagnosis',
              'treatment',
            ]),
          ),
        ),
      );
    }
  });

  test('不允许跳过播报直接提交理解题', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await controller.startSession(OfflineSpeechLanguage.mandarin);
    await controller.selectItem(reviewedItem);

    await expectLater(controller.submitAnswer(0), throwsStateError);

    expect(
      events.saved.map((event) => event.type),
      isNot(contains(EducationEventType.answer)),
    );
    expect(controller.state.stage, EducationSessionStage.ready);
  });

  test('不允许未开始播放就标记播报完成', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await controller.startSession(OfflineSpeechLanguage.mandarin);
    await controller.selectItem(reviewedItem);

    await expectLater(controller.markSpeechComplete(), throwsStateError);

    expect(controller.state.stage, EducationSessionStage.ready);
    expect(
      events.saved.map((event) => event.type),
      isNot(contains(EducationEventType.playbackCompleted)),
    );
  });

  test('结束事件写入失败也必须立即清屏', () async {
    final events = FakeEducationEventRepository();
    final controller = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await controller.startSession(OfflineSpeechLanguage.mandarin);
    await controller.selectItem(reviewedItem);
    await controller.beginPlayback();
    events.failOnType = EducationEventType.sessionCompleted;

    await controller.finishSession();

    expect(controller.state.stage, EducationSessionStage.idle);
    expect(controller.state.visibleCaption, isEmpty);
    expect(controller.lastPersistenceError, isA<StateError>());
  });
}

class _BlockingPlaybackStartRepository implements EducationEventRepository {
  final _playbackStart = Completer<void>();

  void releasePlaybackStart() => _playbackStart.complete();

  @override
  Future<void> save(EducationSessionEvent event) async {
    if (event.type == EducationEventType.playbackStarted) {
      await _playbackStart.future;
    }
  }

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
}
