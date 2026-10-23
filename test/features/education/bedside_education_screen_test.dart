import 'dart:async';

import 'package:digital_nurse/features/education/controllers/education_session_controller.dart';
import 'package:digital_nurse/features/education/data/education_event_repository.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/features/education/screens/bedside_education_screen.dart';
import 'package:digital_nurse/features/education/screens/education_playback_screen.dart';
import 'package:digital_nurse/features/education/widgets/daily_language_selector.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/theme/nurse_theme.dart';
import 'package:digital_nurse/services/education_video_service.dart';
import 'package:digital_nurse/widgets/nurse_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'fake_education_event_repository.dart';

void main() {
  testWidgets('无需进入设置就能看到三种宣教语言', (tester) async {
    var selected = OfflineSpeechLanguage.mandarin;
    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder:
              (context, setState) => Scaffold(
                body: Center(
                  child: DailyLanguageSelector(
                    value: selected,
                    onChanged: (value) => setState(() => selected = value),
                  ),
                ),
              ),
        ),
      ),
    );

    expect(find.text('普通话'), findsOneWidget);
    expect(find.text('粤语'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    for (final label in const ['普通话', '粤语', 'English']) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ChoiceChip),
      );
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.text('粤语'));
    await tester.pump();
    expect(selected, OfflineSpeechLanguage.cantonese);
  });

  testWidgets('未发布的目标语言会明确标示不可用', (tester) async {
    final base = educationFixture();
    final draftTitle = '未审核英文草稿标题';
    final itemWithEnglishDraft = base.copyWith(
      contents: {
        ...base.contents,
        OfflineSpeechLanguage.english: base
            .contentFor(OfflineSpeechLanguage.english)
            .copyWith(title: draftTitle, published: false),
      },
    );
    final harness = await _bedsideHarness([itemWithEnglishDraft]);
    await tester.pumpWidget(harness.app);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('该语言暂未提供'), findsOneWidget);
    expect(find.text(draftTitle), findsNothing);
    expect(find.text('开始宣教'), findsNothing);
    expect(harness.session.state.selectedItem, isNull);

    await tester.enterText(find.byType(TextField), draftTitle);
    await tester.pump();
    expect(find.text('没有找到匹配的宣教内容'), findsOneWidget);
  });

  testWidgets('语言切换尚未完成时返回不会留下孤立会话', (tester) async {
    final events = _BlockingClearEventRepository();
    final session = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await session.startSession(OfflineSpeechLanguage.mandarin);
    var globalLanguage = OfflineSpeechLanguage.mandarin;
    await tester.pumpWidget(
      _testApp(
        BedsideEducationScreen(
          items: [reviewedItem],
          session: session,
          departmentName: '急诊病房',
          onLanguageChanged: (value) => globalLanguage = value,
        ),
      ),
    );

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回数字护士首页'));
    await tester.pump();
    events.releaseClear();
    await tester.pumpAndSettle();

    expect(session.state.stage, EducationSessionStage.idle);
    expect(globalLanguage, OfflineSpeechLanguage.mandarin);
  });

  testWidgets('连续点击两个项目只会打开第一个', (tester) async {
    final second = educationFixture(id: 'exam', category: '检查宣教', sortOrder: 1);
    final secondWithDistinctTitle = second.copyWith(
      contents: {
        ...second.contents,
        OfflineSpeechLanguage.mandarin: second
            .contentFor(OfflineSpeechLanguage.mandarin)
            .copyWith(title: '检查前准备'),
      },
    );
    final events = _BlockingSelectionEventRepository();
    final session = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await session.startSession(OfflineSpeechLanguage.mandarin);
    await tester.pumpWidget(
      _testApp(
        BedsideEducationScreen(
          items: [reviewedItem, secondWithDistinctTitle],
          session: session,
          departmentName: '急诊病房',
        ),
      ),
    );

    await tester.tap(find.text('入院注意事项'));
    await tester.tap(find.text('检查前准备'));
    events.releaseSelection();
    await tester.pumpAndSettle();

    expect(session.state.selectedItem?.id, reviewedItem.id);
    expect(find.text('开始宣教'), findsOneWidget);
  });

  testWidgets('选择可用内容后进入宣教准备页', (tester) async {
    final harness = await _bedsideHarness([reviewedItem]);
    await tester.pumpWidget(harness.app);

    await tester.tap(find.text('入院注意事项'));
    await tester.pumpAndSettle();

    expect(find.text('开始宣教'), findsOneWidget);
    expect(harness.session.state.selectedItem?.id, reviewedItem.id);
    expect(harness.session.state.stage, EducationSessionStage.ready);
  });

  testWidgets('视频宣教与文字宣教分开展示并直接本地播放', (tester) async {
    final events = FakeEducationEventRepository();
    final session = EducationSessionController(
      events: events,
      departmentId: 'emergency_ward',
    );
    await session.startSession(OfflineSpeechLanguage.mandarin);
    final video = _videoItem();
    final videos = _FakeEducationVideoService();
    var suspended = 0;
    var resumed = 0;
    await tester.pumpWidget(
      _testApp(
        BedsideEducationScreen(
          items: [reviewedItem, video],
          session: session,
          departmentName: '急诊病房',
          videoService: videos,
          onOfflinePlaybackStarting: () async => suspended++,
          onOfflinePlaybackEnded: () async => resumed++,
        ),
      ),
    );

    expect(find.text('文字宣教'), findsOneWidget);
    expect(find.text('视频宣教'), findsWidgets);
    await tester.tap(find.text('出院换药示范'));
    await tester.pump();

    expect(videos.playedPath, '/app/education_videos/discharge.mp4');
    expect(suspended, 1);
    expect(resumed, 1);
    expect(find.byType(EducationPlaybackScreen), findsNothing);
    expect(
      events.saved.map((event) => event.type),
      containsAllInOrder([
        EducationEventType.itemSelected,
        EducationEventType.playbackStarted,
        EducationEventType.playbackCompleted,
      ]),
    );
  });

  testWidgets('工作台向播放页透传数字护士和音频边界', (tester) async {
    final session = EducationSessionController(
      events: FakeEducationEventRepository(),
      departmentId: 'emergency_ward',
    );
    await session.startSession(OfflineSpeechLanguage.mandarin);
    Future<void> onStarting() async {}
    Future<void> onEnded() async {}

    await tester.pumpWidget(
      _testApp(
        BedsideEducationScreen(
          items: [reviewedItem],
          session: session,
          departmentName: '急诊病房',
          nurseAvatarPath: '/tmp/department-nurse.png',
          onOfflinePlaybackStarting: onStarting,
          onOfflinePlaybackEnded: onEnded,
        ),
      ),
    );
    await tester.tap(find.text('入院注意事项'));
    await tester.pumpAndSettle();

    final playback = tester.widget<EducationPlaybackScreen>(
      find.byType(EducationPlaybackScreen),
    );
    expect(playback.nurseAvatarPath, '/tmp/department-nurse.png');
    expect(playback.onOfflinePlaybackStarting, same(onStarting));
    expect(playback.onOfflinePlaybackEnded, same(onEnded));
    final avatar = tester.widget<NurseAvatar>(find.byType(NurseAvatar));
    expect(avatar.imagePath, '/tmp/department-nurse.png');
    expect(avatar.motionEnabled, isFalse);
  });

  testWidgets('搜索、分类和常用筛选可用', (tester) async {
    final second = educationFixture(
      id: 'exam',
      category: '检查宣教',
      sortOrder: 1,
    ).copyWith(favorite: false);
    final harness = await _bedsideHarness([reviewedItem, second]);
    await tester.pumpWidget(harness.app);

    expect(find.text('全部'), findsWidgets);
    expect(find.text('常用'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('入院宣教'), findsOneWidget);
    expect(find.text('检查宣教'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在的内容');
    await tester.pump();
    expect(find.text('没有找到匹配的宣教内容'), findsOneWidget);
  });

  for (final size in const [Size(1024, 600), Size(1920, 1200)]) {
    testWidgets('床旁工作台在 ${size.width.toInt()}×${size.height.toInt()} 不溢出', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _bedsideHarness([
        reviewedItem,
        educationFixture(id: 'exam', category: '检查宣教', sortOrder: 1),
      ]);

      await tester.pumpWidget(harness.app);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('床旁宣教工作台'), findsOneWidget);
      expect(find.text('普通话'), findsOneWidget);
    });
  }
}

ThemeData _theme() =>
    NursePalette.forStyle(NurseVisualStyle.clinicalLight).createTheme();

Widget _testApp(Widget child) => MaterialApp(theme: _theme(), home: child);

Future<_BedsideHarness> _bedsideHarness(List<EducationItem> items) async {
  final session = EducationSessionController(
    events: FakeEducationEventRepository(),
    departmentId: 'emergency_ward',
  );
  await session.startSession(OfflineSpeechLanguage.mandarin);
  return _BedsideHarness(
    session,
    _testApp(
      BedsideEducationScreen(
        items: items,
        session: session,
        departmentName: '急诊病房',
      ),
    ),
  );
}

class _BedsideHarness {
  const _BedsideHarness(this.session, this.app);

  final EducationSessionController session;
  final Widget app;
}

class _BlockingClearEventRepository implements EducationEventRepository {
  final _clearCompleter = Completer<void>();

  void releaseClear() {
    if (!_clearCompleter.isCompleted) _clearCompleter.complete();
  }

  @override
  Future<void> save(EducationSessionEvent event) async {
    if (event.type == EducationEventType.sessionCleared) {
      await _clearCompleter.future;
    }
  }

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
}

class _BlockingSelectionEventRepository implements EducationEventRepository {
  final _selectionCompleter = Completer<void>();

  void releaseSelection() {
    if (!_selectionCompleter.isCompleted) _selectionCompleter.complete();
  }

  @override
  Future<void> save(EducationSessionEvent event) async {
    if (event.type == EducationEventType.itemSelected) {
      await _selectionCompleter.future;
    }
  }

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async => const [];
}

EducationItem _videoItem() {
  final now = DateTime.utc(2026, 8, 18);
  return EducationItem(
    id: 'discharge-video',
    category: '出院宣教',
    contents: const {},
    estimatedManualMinutes: 3,
    sortOrder: 2,
    favorite: false,
    enabled: true,
    version: 1,
    createdAt: now,
    updatedAt: now,
    kind: EducationItemKind.video,
    videoTitle: '出院换药示范',
    videoPath: '/app/education_videos/discharge.mp4',
  );
}

class _FakeEducationVideoService extends EducationVideoService {
  String? playedPath;

  @override
  Future<bool> playVideo({required String path, required String title}) async {
    playedPath = path;
    return true;
  }
}
