import 'dart:async';

import 'package:digital_nurse/features/education/controllers/education_session_controller.dart';
import 'package:digital_nurse/features/education/data/education_event_repository.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/features/education/screens/education_playback_screen.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/services/local_speech_service.dart';
import 'package:digital_nurse/theme/nurse_theme.dart';
import 'package:digital_nurse/widgets/nurse_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'fake_education_event_repository.dart';

void main() {
  testWidgets(
    'auto-start playback keeps avatar and replaces captions with question',
    (tester) async {
      final speech = _FakeLocalSpeechService();
      final session = await _readySession();
      final boundary = _AudioBoundaryCounter();

      await tester.pumpWidget(
        _playbackApp(
          session,
          speech,
          autoStart: true,
          onOfflinePlaybackStarting: boundary.suspend,
          onOfflinePlaybackEnded: boundary.resume,
        ),
      );
      await tester.pump();

      expect(find.byType(NurseAvatar), findsOneWidget);
      expect(speech.spoken, isNotNull);
      expect(speech.speakCount, 1);
      expect(boundary.suspended, 1);
      await tester.pump();
      expect(speech.speakCount, 1);
      expect(boundary.suspended, 1);

      speech.complete();
      await tester.pump();
      final question =
          reviewedItem.contentFor(OfflineSpeechLanguage.mandarin).question;
      expect(find.text(question), findsOneWidget);
      expect(find.byType(NurseAvatar), findsOneWidget);
      expect(boundary.resumed, 1);
    },
  );

  testWidgets('speech error restores online audio exactly once', (
    tester,
  ) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    speech.fail();
    speech.fail();
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
    expect(session.state.stage, EducationSessionStage.question);
  });

  testWidgets('speak exception restores online audio exactly once', (
    tester,
  ) async {
    final speech = _ThrowingSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
    expect(session.state.stage, EducationSessionStage.question);
  });

  testWidgets('back restores online audio exactly once', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('结束并返回'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
  });

  testWidgets('back waits for offline stop before restoring online audio', (
    tester,
  ) async {
    final speech = _BlockingStopSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('结束并返回'));
    await tester.pump();
    expect(boundary.resumed, 0);

    speech.releaseStop();
    await tester.pump();
    expect(boundary.resumed, 1);
  });

  testWidgets('background privacy clear restores online audio exactly once', (
    tester,
  ) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('timeout restores online audio exactly once', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        inactivityDuration: const Duration(seconds: 5),
        warningDuration: const Duration(seconds: 2),
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
  });

  testWidgets('dispose restores online audio exactly once', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
  });

  testWidgets('dispose waits for offline stop before restoring online audio', (
    tester,
  ) async {
    final speech = _BlockingStopSpeechService();
    final session = await _readySession();
    final boundary = _AudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(boundary.resumed, 0);

    speech.releaseStop();
    await tester.pump();
    expect(boundary.resumed, 1);
  });

  testWidgets('replay waits for prior restore and balances a new boundary', (
    tester,
  ) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final boundary = _BlockingRestoreAudioBoundaryCounter();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        autoStart: true,
        onOfflinePlaybackStarting: boundary.suspend,
        onOfflinePlaybackEnded: boundary.resume,
      ),
    );
    await tester.pump();
    speech.complete();
    await tester.pump();

    await tester.tap(find.text('重新听一遍'));
    await tester.pump();
    expect(boundary.suspended, 1);
    expect(boundary.resumed, 1);
    boundary.releaseRestore();
    await tester.pump();
    expect(boundary.suspended, 2);

    speech.complete();
    speech.complete();
    await tester.pump();
    expect(boundary.resumed, 2);
  });

  testWidgets('播放结束后进入理解题，答错后中性提示并可清屏', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(_playbackApp(session, speech));

    await tester.tap(find.text('开始播放'));
    await tester.pump();
    expect(speech.spoken, reviewedItem.contentFor(session.state.language).body);
    expect(session.state.stage, EducationSessionStage.playing);

    speech.complete();
    await tester.pump();
    final content = reviewedItem.contentFor(OfflineSpeechLanguage.mandarin);
    expect(find.text(content.question), findsOneWidget);

    await tester.tap(find.text(content.options[1]));
    await tester.pump();
    expect(find.text('我们再看一下重点'), findsOneWidget);
    expect(find.text('重新听一遍'), findsOneWidget);
    expect(find.byType(NurseAvatar), findsOneWidget);

    await tester.tap(find.text('结束本次宣教'));
    await tester.pump();
    expect(session.state.selectedItem, isNull);
    expect(find.text(content.body), findsNothing);
  });

  testWidgets('字幕从空白开始跟随播放逐步出现', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    final body = reviewedItem.contentFor(OfflineSpeechLanguage.mandarin).body;
    await tester.pumpWidget(_playbackApp(session, speech));

    await tester.tap(find.text('开始播放'));
    await tester.pump();
    expect(find.text(body), findsNothing);
    await tester.pump(const Duration(milliseconds: 450));
    expect(session.state.visibleCaption, isNotEmpty);
    expect(session.state.visibleCaption, isNot(body));

    speech.complete();
    await tester.pump();
    expect(session.state.visibleCaption, body);
  });

  testWidgets('播放期间禁用语言切换，播放后可切换内容', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(_playbackApp(session, speech));

    await tester.tap(find.text('开始播放'));
    await tester.pump();
    final englishChip = find.ancestor(
      of: find.text('English'),
      matching: find.byType(ChoiceChip),
    );
    expect(tester.widget<ChoiceChip>(englishChip).onSelected, isNull);

    speech.complete();
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(session.state.language, OfflineSpeechLanguage.english);
    expect(find.text('Admission Information'), findsOneWidget);
  });

  testWidgets('应用转入后台会立即停止播放并清空患者端内容', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(_playbackApp(session, speech));
    await tester.tap(find.text('开始播放'));
    await tester.pump(const Duration(milliseconds: 120));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(speech.stopCount, greaterThan(0));
    expect(session.state.stage, EducationSessionStage.idle);
    expect(session.state.visibleCaption, isEmpty);
  });

  testWidgets('无操作前会预警，到时自动结束并清屏', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        inactivityDuration: const Duration(seconds: 5),
        warningDuration: const Duration(seconds: 2),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('长时间无操作'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state.stage, EducationSessionStage.idle);
    expect(session.state.selectedItem, isNull);
  });

  testWidgets('患者持续触摸或滚动阅读会重置无操作计时', (tester) async {
    final speech = _FakeLocalSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(
      _playbackApp(
        session,
        speech,
        inactivityDuration: const Duration(seconds: 5),
        warningDuration: const Duration(seconds: 2),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('长时间无操作'), findsOneWidget);
    await tester.tap(find.textContaining('急诊病房·床旁宣教'));
    await tester.pump();
    expect(find.textContaining('长时间无操作'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state.stage, EducationSessionStage.ready);
  });

  testWidgets('语音停止较慢时后台切换仍立即清空会话', (tester) async {
    final speech = _BlockingStopSpeechService();
    final session = await _readySession();
    await tester.pumpWidget(_playbackApp(session, speech));
    await tester.tap(find.text('开始播放'));
    await tester.pump(const Duration(milliseconds: 300));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(session.state.stage, EducationSessionStage.idle);
    expect(session.state.visibleCaption, isEmpty);
    speech.releaseStop();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('播放事件保存较慢时离页不会重新响起语音', (tester) async {
    final events = _BlockingPlaybackEventRepository();
    final session = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await session.startSession(OfflineSpeechLanguage.mandarin);
    await session.selectItem(reviewedItem);
    events.blockPlayback();
    final speech = _FakeLocalSpeechService();
    await tester.pumpWidget(_playbackApp(session, speech));

    await tester.tap(find.text('开始播放'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    events.releasePlayback();
    await tester.pump();

    expect(session.state.stage, EducationSessionStage.idle);
    expect(speech.spoken, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('长字幕会按实际音频时长推进并自动跟随末尾', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longBody = List.filled(600, '宣').join();
    final item = _itemWithMandarin(body: longBody);
    final speech = _FakeLocalSpeechService(
      playbackDuration: const Duration(seconds: 15),
    );
    final session = await _readySession(item);
    await tester.pumpWidget(_playbackApp(session, speech));

    await tester.tap(find.text('开始播放'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(session.state.visibleCaption.length, inInclusiveRange(250, 380));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('education-caption-scroll')),
    );
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
    expect(
      scroll.controller!.position.pixels,
      closeTo(scroll.controller!.position.maxScrollExtent, 0.1),
    );
  });

  testWidgets('合法上限长度的理解题和解释可滚动且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final options = List.generate(
      4,
      (index) =>
          '${String.fromCharCode(65 + index)}${List.filled(79, '选').join()}',
    );
    final item = _itemWithMandarin(
      question: List.filled(120, '问').join(),
      options: options,
      explanation: List.filled(240, '解').join(),
    );
    final speech = _FakeLocalSpeechService();
    final session = await _readySession(item);
    await tester.pumpWidget(_playbackApp(session, speech));
    await tester.tap(find.text('开始播放'));
    await tester.pump();
    speech.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text(options[1]));
    await tester.pump();
    await tester.tap(find.text(options[1]));
    await tester.pump();
    expect(find.text('我们再看一下重点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1024, 600), Size(1920, 1200)]) {
    testWidgets('播放与理解确认页在 ${size.width.toInt()}×${size.height.toInt()} 不溢出', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final speech = _FakeLocalSpeechService();
      final session = await _readySession();
      await tester.pumpWidget(_playbackApp(session, speech));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('开始播放'));
      speech.complete();
      await tester.pump();

      expect(find.textContaining('办理入院后应该怎么做'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<EducationSessionController> _readySession([EducationItem? item]) async {
  final session = EducationSessionController(
    events: FakeEducationEventRepository(),
    departmentId: 'emergency_ward',
  );
  await session.startSession(OfflineSpeechLanguage.mandarin);
  await session.selectItem(item ?? reviewedItem);
  return session;
}

EducationItem _itemWithMandarin({
  String? body,
  String? question,
  List<String>? options,
  String? explanation,
}) {
  final content = reviewedItem.contentFor(OfflineSpeechLanguage.mandarin);
  return reviewedItem.copyWith(
    contents: {
      ...reviewedItem.contents,
      OfflineSpeechLanguage.mandarin: content.copyWith(
        body: body,
        question: question,
        options: options,
        explanation: explanation,
      ),
    },
  );
}

Widget _playbackApp(
  EducationSessionController session,
  LocalSpeechService speech, {
  Duration inactivityDuration = const Duration(minutes: 5),
  Duration warningDuration = const Duration(seconds: 30),
  bool autoStart = false,
  Future<void> Function()? onOfflinePlaybackStarting,
  Future<void> Function()? onOfflinePlaybackEnded,
}) => MaterialApp(
  theme: NursePalette.forStyle(NurseVisualStyle.clinicalLight).createTheme(),
  home: EducationPlaybackScreen(
    session: session,
    speech: speech,
    departmentName: '急诊病房',
    nurseAvatarPath: '',
    autoStart: autoStart,
    onOfflinePlaybackStarting: onOfflinePlaybackStarting,
    onOfflinePlaybackEnded: onOfflinePlaybackEnded,
    inactivityDuration: inactivityDuration,
    warningDuration: warningDuration,
  ),
);

class _FakeLocalSpeechService extends LocalSpeechService {
  _FakeLocalSpeechService({this.playbackDuration = const Duration(seconds: 3)});

  final _events = StreamController<LocalSpeechEvent>.broadcast(sync: true);
  final _durations = StreamController<Duration>.broadcast(sync: true);
  String? spoken;
  OfflineSpeechLanguage? spokenLanguage;
  int stopCount = 0;
  int speakCount = 0;
  final Duration playbackDuration;

  @override
  Stream<LocalSpeechEvent> get events => _events.stream;

  @override
  Stream<Duration> get playbackDurations => _durations.stream;

  @override
  Future<void> speak(
    String text, {
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  }) async {
    speakCount++;
    spoken = text;
    spokenLanguage = language;
    _durations.add(playbackDuration);
    _events.add(LocalSpeechEvent.started);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void complete() => _events.add(LocalSpeechEvent.completed);

  void fail() => _events.add(LocalSpeechEvent.error);
}

class _ThrowingSpeechService extends _FakeLocalSpeechService {
  @override
  Future<void> speak(
    String text, {
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  }) async {
    throw StateError('synthetic speech failure');
  }
}

class _AudioBoundaryCounter {
  int suspended = 0;
  int resumed = 0;

  Future<void> suspend() async => suspended++;

  Future<void> resume() async => resumed++;
}

class _BlockingRestoreAudioBoundaryCounter extends _AudioBoundaryCounter {
  final _firstRestore = Completer<void>();

  @override
  Future<void> resume() async {
    resumed++;
    if (resumed == 1) await _firstRestore.future;
  }

  void releaseRestore() => _firstRestore.complete();
}

class _BlockingStopSpeechService extends _FakeLocalSpeechService {
  final _stopCompleter = Completer<void>();

  @override
  Future<void> stop() async {
    stopCount++;
    await _stopCompleter.future;
  }

  void releaseStop() {
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
  }
}

class _BlockingPlaybackEventRepository implements EducationEventRepository {
  Completer<void>? _playbackCompleter;

  void blockPlayback() => _playbackCompleter = Completer<void>();

  void releasePlayback() => _playbackCompleter?.complete();

  @override
  Future<void> save(EducationSessionEvent event) async {
    if (event.type == EducationEventType.playbackStarted) {
      await _playbackCompleter?.future;
    }
  }

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
}
