import 'dart:async';

import 'package:digital_nurse/controllers/nurse_controller.dart';
import 'package:digital_nurse/features/education/models/education_language_content.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/features/education/screens/education_playback_screen.dart';
import 'package:digital_nurse/main.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/repositories/nurse_config_repository.dart';
import 'package:digital_nurse/screens/nurse_screen.dart';
import 'package:digital_nurse/services/local_speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fake_education_event_repository.dart';
import 'fake_education_repository.dart';

void main() {
  testWidgets('首页只展示管理员星标宣教并保留更多宣教入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(id: 'favorite', title: '标星宣教', favorite: true),
      _educationItem(id: 'ordinary', title: '未标星宣教', favorite: false),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    expect(find.text('标星宣教'), findsOneWidget);
    expect(find.text('未标星宣教'), findsNothing);
    expect(find.text('更多宣教'), findsOneWidget);
  });

  testWidgets('设置关闭后刷新星标宣教缓存并立即更新首页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    final itemA = _educationItem(
      id: 'favorite-a',
      title: '星标A',
      favorite: true,
    );
    final itemB = _educationItem(
      id: 'favorite-b',
      title: '星标B',
      favorite: false,
    );
    await educationRepository.replaceAll([itemA, itemB]);
    await educationRepository.markLegacyMigrationCompleted();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    expect(find.text('星标A'), findsOneWidget);
    expect(find.text('星标B'), findsNothing);

    await educationRepository.save(itemA.copyWith(favorite: false));
    await educationRepository.save(itemB.copyWith(favorite: true));
    await controller.loadActiveEducation();
    await tester.pump();

    expect(find.text('星标A'), findsNothing);
    expect(find.text('星标B'), findsOneWidget);
  });

  testWidgets('刷新宣教库失败时清空星标缓存并显示旧版应急入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = _FailingRefreshEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(id: 'stale-favorite', title: '过期星标宣教', favorite: true),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();
    expect(controller.favoriteEducationItems, hasLength(1));

    educationRepository.failLoads = true;
    await expectLater(controller.loadActiveEducation(), throwsStateError);

    expect(controller.educationFallbackActive, isTrue);
    expect(controller.educationInitializationError, contains('宣教库加载失败'));
    expect(controller.activeEducationItems, isEmpty);
    expect(controller.favoriteEducationItems, isEmpty);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    expect(find.text('宣教库异常，已启用旧版应急宣教'), findsOneWidget);
    expect(find.text('入院注意事项'), findsOneWidget);
    expect(find.text('过期星标宣教'), findsNothing);
  });

  testWidgets('首页星标宣教直接进入播放页并自动语音播放', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    final favorite = _educationItem(
      id: 'favorite-direct',
      title: '直接播放宣教',
      favorite: true,
    );
    await educationRepository.replaceAll([favorite]);
    await educationRepository.markLegacyMigrationCompleted();
    final speech = _FakeLocalSpeechService();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: speech,
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    await tester.tap(find.text('直接播放宣教'));
    await tester.pump();
    await tester.pump();

    final playback = tester.widget<EducationPlaybackScreen>(
      find.byType(EducationPlaybackScreen),
    );
    expect(playback.session.state.selectedItem, favorite);
    expect(speech.spoken, '直接播放宣教播报正文');
  });

  testWidgets('星标宣教选中事件保存失败时清理已创建会话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(
        id: 'favorite-select-fails',
        title: '故障宣教',
        favorite: true,
      ),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final events =
        FakeEducationEventRepository()
          ..failOnType = EducationEventType.itemSelected;
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: _FakeLocalSpeechService(),
      educationRepository: educationRepository,
      educationEventRepository: events,
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    await tester.tap(find.text('故障宣教'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(EducationPlaybackScreen), findsNothing);
    expect(
      events.saved.map((event) => event.type),
      contains(EducationEventType.sessionCleared),
    );
  });

  testWidgets('星标宣教路由接管失败时清理已创建会话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(
        id: 'favorite-route-fails',
        title: '路由故障宣教',
        favorite: true,
      ),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final events = FakeEducationEventRepository();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: _FakeLocalSpeechService(),
      educationRepository: educationRepository,
      educationEventRepository: events,
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: _ThrowingPushNavigator(child: const NurseScreen()),
        ),
      ),
    );

    await tester.tap(find.text('路由故障宣教'));
    await tester.pump();
    await tester.pump();

    expect(
      events.saved.map((event) => event.type),
      contains(EducationEventType.sessionCleared),
    );
  });

  testWidgets('星标宣教正常路由返回后不重复清理会话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(
        id: 'favorite-normal-route',
        title: '正常路由宣教',
        favorite: true,
      ),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final events = FakeEducationEventRepository();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: _FakeLocalSpeechService(),
      educationRepository: educationRepository,
      educationEventRepository: events,
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    await tester.tap(find.text('正常路由宣教'));
    await tester.pump();
    await tester.pump();
    Navigator.of(
      tester.element(find.byType(EducationPlaybackScreen)),
    ).pop<void>();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      events.saved.where(
        (event) => event.type == EducationEventType.sessionCleared,
      ),
      hasLength(1),
    );
  });

  testWidgets('首页星标宣教快速连点只打开一个播放路由', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(id: 'favorite-once', title: '防连点宣教', favorite: true),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: _FakeLocalSpeechService(),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const NurseScreen(),
        ),
      ),
    );

    final favoriteButton = find.byKey(
      const ValueKey('favorite-education-favorite-once'),
    );
    final button = tester.widget<OutlinedButton>(favoriteButton);
    button.onPressed!.call();
    button.onPressed!.call();
    await tester.pump();
    await tester.pump();

    expect(observer.openedRoutes, 1);
  });

  testWidgets('首页星标宣教在目标语言未发布时明确禁用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([
      _educationItem(
        id: 'favorite-unavailable',
        title: '未发布语言宣教',
        favorite: true,
      ),
    ]);
    await educationRepository.markLegacyMigrationCompleted();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(
        NurseAppConfig.defaults(
          'device',
          'client',
        ).copyWith(departmentConfigured: false),
      ),
      localSpeechService: _FakeLocalSpeechService(),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    await tester.tap(find.text('English'));
    await tester.pump();

    expect(
      controller.config.offlineSpeechLanguage,
      OfflineSpeechLanguage.english,
    );
    expect(find.text('该语言暂未提供'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('favorite-education-favorite-unavailable')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('旧版自定义宣教启动时无损迁移并可进入床旁工作台', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final legacyAnswer = LocalQuickAnswer(
      title: '旧版自定义宣教',
      answer: '这是科室旧版本保存的宣教内容。',
      cantoneseTitle: '舊版自定義宣教',
      cantoneseAnswer: '呢個係科室舊版本保存嘅宣教內容。',
      englishTitle: 'Legacy custom education',
      englishAnswer: 'This is the department legacy education content.',
    );
    final legacyConfig = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: false, quickAnswers: [legacyAnswer]);
    final educationRepository = FakeEducationRepository();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(legacyConfig),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );

    await controller.initialize();

    expect(educationRepository.migrationCompleted, isTrue);
    expect(
      (await educationRepository.loadActive()).single
          .contentFor(controller.config.offlineSpeechLanguage)
          .title,
      legacyAnswer.title,
    );
    expect(controller.config.quickAnswers.single.title, legacyAnswer.title);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    await tester.tap(find.text('更多宣教'));
    await tester.pumpAndSettle();

    expect(find.text('旧版自定义宣教'), findsOneWidget);
    expect(controller.config.quickAnswers.single.title, legacyAnswer.title);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页快速连点只会打开一个床旁工作台', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: false);
    final educationRepository = _BlockingLoadEducationRepository();
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(config),
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initialize();
    educationRepository.blockNextLoad();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    final launch = find.text('更多宣教');
    await tester.tap(launch);
    await tester.tap(launch);
    await tester.pump();

    expect(educationRepository.loadCalls, 1);
    expect(find.text('正在打开'), findsOneWidget);
    educationRepository.release();
    await tester.pumpAndSettle();
    expect(find.text('床旁宣教工作台'), findsOneWidget);
    expect(educationRepository.loadCalls, 1);
  });

  test('本地启动阶段必须先读取旧配置再执行宣教迁移', () async {
    final legacyAnswer = LocalQuickAnswer(
      title: '启动竞态保留内容',
      answer: '这条内容不能被默认值覆盖。',
      cantoneseTitle: '啟動競態保留內容',
      cantoneseAnswer: '呢條內容唔能被預設值覆蓋。',
      englishTitle: 'Preserved legacy content',
      englishAnswer: 'This content must not be replaced by defaults.',
    );
    final delayedConfig = _DelayedNurseConfigRepository();
    final educationRepository = FakeEducationRepository();
    final controller = NurseController(
      repository: delayedConfig,
      educationRepository: educationRepository,
      educationEventRepository: FakeEducationEventRepository(),
    );

    final initialization = controller.initializeLocalState();
    await Future<void>.delayed(Duration.zero);
    expect(educationRepository.migrationCompleted, isFalse);

    delayedConfig.release(
      NurseAppConfig.defaults(
        'device',
        'client',
      ).copyWith(departmentConfigured: false, quickAnswers: [legacyAnswer]),
    );
    await initialization;

    final migrated = await educationRepository.loadActive();
    expect(migrated.single.contents.values.first.title, legacyAnswer.title);
    expect(controller.config.quickAnswers.single.title, legacyAnswer.title);
  });

  testWidgets('宣教库初始化失败时保留旧版应急宣教入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: false);
    final controller = NurseController(
      repository: _FakeNurseConfigRepository(config),
      educationRepository: _FailingEducationRepository(),
      educationEventRepository: FakeEducationEventRepository(),
    );
    await controller.initializeLocalState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );

    expect(find.text('宣教库异常，已启用旧版应急宣教'), findsOneWidget);
    expect(find.text('入院注意事项'), findsOneWidget);
    expect(find.text('更多宣教'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

EducationItem _educationItem({
  required String id,
  required String title,
  required bool favorite,
}) {
  final now = DateTime.utc(2026, 7, 21);
  return EducationItem(
    id: id,
    category: '入院宣教',
    contents: {
      OfflineSpeechLanguage.mandarin: EducationLanguageContent(
        title: title,
        body: '$title播报正文',
        summary: '$title摘要',
        question: '是否理解？',
        options: const ['是', '否'],
        correctIndex: 0,
        explanation: '已理解',
        published: true,
        needsReview: false,
      ),
    },
    estimatedManualMinutes: 1,
    sortOrder: id == 'favorite' ? 0 : 1,
    favorite: favorite,
    enabled: true,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeNurseConfigRepository extends NurseConfigRepository {
  _FakeNurseConfigRepository(this.value);

  NurseAppConfig value;

  @override
  Future<NurseAppConfig> load() async => value;

  @override
  Future<void> save(NurseAppConfig config) async {
    value = config;
  }
}

class _DelayedNurseConfigRepository extends NurseConfigRepository {
  final _completer = Completer<NurseAppConfig>();

  void release(NurseAppConfig config) {
    if (!_completer.isCompleted) _completer.complete(config);
  }

  @override
  Future<NurseAppConfig> load() => _completer.future;

  @override
  Future<void> save(NurseAppConfig config) async {}
}

class _FailingEducationRepository extends FakeEducationRepository {
  @override
  Future<bool> isLegacyMigrationCompleted() async => throw StateError('db');
}

class _FailingRefreshEducationRepository extends FakeEducationRepository {
  bool failLoads = false;

  @override
  Future<List<EducationItem>> loadActive() {
    if (failLoads) throw StateError('refresh failed');
    return super.loadActive();
  }
}

class _FakeLocalSpeechService extends LocalSpeechService {
  final _events = StreamController<LocalSpeechEvent>.broadcast(sync: true);
  String? spoken;

  @override
  Stream<LocalSpeechEvent> get events => _events.stream;

  @override
  Stream<Duration> get playbackDurations => const Stream.empty();

  @override
  Future<void> prepare([
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  ]) async {}

  @override
  Future<void> speak(
    String text, {
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  }) async {
    spoken = text;
    _events.add(LocalSpeechEvent.started);
  }

  @override
  Future<void> stop() async {}
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int openedRoutes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) openedRoutes++;
    super.didPush(route, previousRoute);
  }
}

class _ThrowingPushNavigator extends Navigator {
  _ThrowingPushNavigator({required Widget child})
    : super(
        onGenerateRoute:
            (_) => MaterialPageRoute<void>(builder: (context) => child),
      );

  @override
  NavigatorState createState() => _ThrowingPushNavigatorState();
}

class _ThrowingPushNavigatorState extends NavigatorState {
  @override
  Future<T?> push<T extends Object?>(Route<T> route) =>
      Future<T?>.error(StateError('navigation failed'));
}

class _BlockingLoadEducationRepository extends FakeEducationRepository {
  final _loadCompleter = Completer<void>();
  int loadCalls = 0;
  bool _blocking = false;

  void blockNextLoad() {
    _blocking = true;
    loadCalls = 0;
  }

  void release() {
    if (!_loadCompleter.isCompleted) _loadCompleter.complete();
  }

  @override
  Future<List<EducationItem>> loadActive() async {
    if (!_blocking) return super.loadActive();
    loadCalls++;
    await _loadCompleter.future;
    return super.loadActive();
  }
}
