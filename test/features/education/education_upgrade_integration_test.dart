import 'dart:async';

import 'package:digital_nurse/controllers/nurse_controller.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/main.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/repositories/nurse_config_repository.dart';
import 'package:digital_nurse/screens/nurse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fake_education_event_repository.dart';
import 'fake_education_repository.dart';

void main() {
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
    await tester.tap(find.text('开始床旁宣教'));
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

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    final launch = find.text('开始床旁宣教');
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
    expect(find.text('开始床旁宣教'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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

class _BlockingLoadEducationRepository extends FakeEducationRepository {
  final _loadCompleter = Completer<void>();
  int loadCalls = 0;

  void release() {
    if (!_loadCompleter.isCompleted) _loadCompleter.complete();
  }

  @override
  Future<List<EducationItem>> loadActive() async {
    loadCalls++;
    await _loadCompleter.future;
    return super.loadActive();
  }
}
