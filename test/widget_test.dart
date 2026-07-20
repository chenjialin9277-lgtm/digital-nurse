import 'dart:async';

import 'package:digital_nurse/main.dart';
import 'package:digital_nurse/controllers/nurse_controller.dart';
import 'package:digital_nurse/models/app_usage_record.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/repositories/app_usage_repository.dart';
import 'package:digital_nurse/repositories/nurse_config_repository.dart';
import 'package:digital_nurse/screens/nurse_screen.dart';
import 'package:digital_nurse/services/local_speech_service.dart';
import 'package:digital_nurse/services/usage_export_service.dart';
import 'package:digital_nurse/services/xiaozhi_service.dart';
import 'package:digital_nurse/theme/nurse_theme.dart';
import 'package:digital_nurse/widgets/nurse_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/education/fake_education_repository.dart';

void main() {
  test('使用记录可以按指定日期查询并统计各类次数', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = AppUsageRepository();
    await repository.record(
      AppUsageType.appLaunch,
      occurredAt: DateTime(2026, 7, 17, 8, 30),
    );
    await repository.record(
      AppUsageType.voiceQuestion,
      occurredAt: DateTime(2026, 7, 17, 9, 15),
    );
    await repository.record(
      AppUsageType.fixedEducation,
      occurredAt: DateTime(2026, 7, 18, 10),
    );

    final records = await repository.query(
      startDate: DateTime(2026, 7, 17),
      endDate: DateTime(2026, 7, 17),
    );
    final summary = AppUsageSummary(records);

    expect(records, hasLength(2));
    expect(summary.launchCount, 1);
    expect(summary.serviceCount, 1);
    expect(summary.countOf(AppUsageType.voiceQuestion), 1);
    expect(records.first.occurredAt.hour, 9);
  });

  testWidgets('Excel报表包含汇总和使用明细两个工作表的数据', (tester) async {
    MethodCall? captured;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('digital_nurse/system'),
      (call) async {
        captured = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('digital_nurse/system'),
        null,
      ),
    );

    await const UsageExportService().exportXlsx(
      startDate: DateTime(2026, 7, 17),
      endDate: DateTime(2026, 7, 17),
      records: <AppUsageRecord>[
        AppUsageRecord(
          occurredAt: DateTime(2026, 7, 17, 9, 15),
          type: AppUsageType.voiceQuestion,
        ),
      ],
      hospitalName: '广州中医药大学第三附属医院',
      wardName: '急诊病房',
    );

    expect(captured?.method, 'saveUsageXlsx');
    final arguments = captured?.arguments as Map<Object?, Object?>;
    expect(arguments['fileName'], endsWith('.xlsx'));
    final summaryRows = (arguments['summaryRows'] as List<Object?>).map(
      (row) => (row as List<Object?>).join('|'),
    );
    final detailRows = (arguments['detailRows'] as List<Object?>).map(
      (row) => (row as List<Object?>).join('|'),
    );
    expect(summaryRows, contains('统计开始日期|2026-07-17'));
    expect(summaryRows, contains('语音提问|1'));
    expect(detailRows, contains('1|2026-07-17|09:15:00|语音提问'));
  });

  test('八项固定回答每次点击内容一致且不需要小智连接', () async {
    final speech = _FakeLocalSpeechService();
    final controller =
        NurseController(localSpeechService: speech)
          ..config = NurseAppConfig.defaults('', '')
          ..state = NurseUiState.offline;
    final item = controller.config.quickAnswers[3];

    await controller.playLocalQuickAnswer(item);
    expect(controller.userText, item.title);
    expect(speech.spoken, item.answer);
    expect(controller.assistantText, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.assistantText, isNotEmpty);
    expect(controller.assistantText, isNot(item.answer));

    speech.complete();
    expect(controller.assistantText, item.answer);

    await controller.playLocalQuickAnswer(item);
    expect(controller.assistantText, isEmpty);
    speech.complete();
    expect(controller.assistantText, item.answer);
    expect(speech.spoken, item.answer);
    expect(controller.config.quickAnswers, hasLength(8));
    expect(controller.verifySettingsPassword('123456'), isTrue);
    expect(controller.verifySettingsPassword('654321'), isFalse);
  });

  test('固定回答完成后恢复在线音频', () async {
    final speech = _FakeLocalSpeechService();
    final online = _FakeXiaozhiService();
    final controller = NurseController(
      localSpeechService: speech,
      xiaozhiService: online,
    )..config = NurseAppConfig.defaults('', '');

    await controller.playLocalQuickAnswer(controller.config.quickAnswers.first);
    expect(online.suspendCalls, 1);

    speech.complete();
    await Future<void>.delayed(Duration.zero);

    expect(online.resumeCalls, 1);
  });

  test('固定回答错误后恢复在线音频', () async {
    final speech = _FakeLocalSpeechService();
    final online = _FakeXiaozhiService();
    final controller = NurseController(
      localSpeechService: speech,
      xiaozhiService: online,
    )..config = NurseAppConfig.defaults('', '');

    await controller.playLocalQuickAnswer(controller.config.quickAnswers.first);
    speech.fail();
    await Future<void>.delayed(Duration.zero);

    expect(online.resumeCalls, 1);
  });

  test('固定回答异常后恢复在线音频', () async {
    final speech = _FakeLocalSpeechService()..throwOnSpeak = true;
    final online = _FakeXiaozhiService();
    final controller = NurseController(
      localSpeechService: speech,
      xiaozhiService: online,
    )..config = NurseAppConfig.defaults('', '');

    await controller.playLocalQuickAnswer(controller.config.quickAnswers.first);

    expect(online.resumeCalls, 1);
  });

  test('显式停止固定回答后恢复在线音频', () async {
    final speech = _FakeLocalSpeechService();
    final online = _FakeXiaozhiService();
    final controller =
        NurseController(localSpeechService: speech, xiaozhiService: online)
          ..config = NurseAppConfig.defaults(
            '02:11:22:33:44:55',
            '11111111-2222-4333-8444-555555555555',
          ).copyWith(
            websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
            token: 'test-token',
          )
          ..state = NurseUiState.idle;

    await controller.playLocalQuickAnswer(controller.config.quickAnswers.first);
    await controller.startPushToTalk();

    expect(online.resumeCalls, 1);
  });

  test('旧版普通话固定回答保留并自动补全粤语英语', () {
    final defaults = NurseAppConfig.defaults('', '');
    final oldAnswers =
        defaults.quickAnswers
            .map(
              (item) => <String, dynamic>{
                'title': '旧版-${item.title}',
                'answer': '旧版-${item.answer}',
              },
            )
            .toList();
    final migrated = NurseAppConfig.fromJson(<String, dynamic>{
      'quickAnswers': oldAnswers,
    });

    expect(migrated.offlineSpeechLanguage, OfflineSpeechLanguage.mandarin);
    expect(migrated.departmentConfigured, isTrue);
    expect(migrated.quickAnswers.first.title, '旧版-入院注意事项');
    expect(migrated.quickAnswers.first.answer, startsWith('旧版-'));
    expect(migrated.quickAnswers.first.cantoneseTitle, '入院须知');
    expect(migrated.quickAnswers.first.englishTitle, 'Admission Information');
  });

  test('首次安装需要科室配置，旧设备升级不被打断', () {
    final fresh = NurseAppConfig.defaults('device-a', 'client-a');
    final migrated = NurseAppConfig.fromJson(<String, dynamic>{
      'hospitalName': NurseAppConfig.defaultHospitalName,
      'wardName': NurseAppConfig.defaultWardName,
      'deviceId': 'device-old',
      'clientId': 'client-old',
    });

    expect(fresh.departmentConfigured, isFalse);
    expect(migrated.departmentConfigured, isTrue);
  });

  test('固定宣教可超过8项并保留三语离线内容', () async {
    final defaults = NurseAppConfig.defaultQuickAnswers;
    final expanded = List<LocalQuickAnswer>.generate(12, (index) {
      final source = defaults[index % defaults.length];
      return LocalQuickAnswer(
        title: '${source.title}-${index + 1}',
        answer: '${source.answer}（第${index + 1}项）',
        cantoneseTitle: '${source.cantoneseTitle}-${index + 1}',
        cantoneseAnswer: '${source.cantoneseAnswer}（第${index + 1}项）',
        englishTitle: '${source.englishTitle}-${index + 1}',
        englishAnswer: '${source.englishAnswer} Item ${index + 1}.',
      );
    });
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(quickAnswers: expanded);
    final restored = NurseAppConfig.fromJson(config.toJson());

    expect(restored.quickAnswers, hasLength(12));
    expect(restored.quickAnswers.last.englishTitle, endsWith('-12'));

    final speech = _FakeLocalSpeechService();
    final controller =
        NurseController(localSpeechService: speech)
          ..config = restored.copyWith(
            offlineSpeechLanguage: OfflineSpeechLanguage.english,
          )
          ..state = NurseUiState.offline;
    await controller.playLocalQuickAnswer(restored.quickAnswers.last);
    expect(speech.spoken, restored.quickAnswers.last.englishAnswer);
    expect(speech.spokenLanguage, OfflineSpeechLanguage.english);
  });

  testWidgets('较多固定宣教在小尺寸平板可滚动且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final defaults = NurseAppConfig.defaultQuickAnswers;
    final controller =
        NurseController()
          ..config = NurseAppConfig.defaults('device', 'client').copyWith(
            departmentConfigured: true,
            quickAnswers: List<LocalQuickAnswer>.generate(
              20,
              (index) => defaults[index % defaults.length],
            ),
          )
          ..state = NurseUiState.offline;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('开始床旁宣教'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页面通过独立入口管理科室宣教', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NurseConfigDialog(
            initial: config,
            educationRepository: FakeEducationRepository(),
          ),
        ),
      ),
    );
    final managementEntry = find.text('管理本科室宣教内容');
    await tester.ensureVisible(managementEntry);

    expect(managementEntry, findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页顶部字段在大字体下为浮动标签保留完整显示空间', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: true);

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
        home: Scaffold(body: NurseConfigDialog(initial: config)),
      ),
    );
    await tester.pumpAndSettle();

    final scrollRect = tester.getRect(find.byType(SingleChildScrollView).first);
    final hospitalLabelRect = tester.getRect(find.text('医院名称'));
    final wardLabelRect = tester.getRect(find.text('科室/病区名称'));

    expect(hospitalLabelRect.top, greaterThanOrEqualTo(scrollRect.top + 8));
    expect(wardLabelRect.top, greaterThanOrEqualTo(scrollRect.top + 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页所有输入框为中文浮动标签提供足够行高', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: true);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NurseConfigDialog(initial: config))),
    );
    await tester.pumpAndSettle();

    final decorators = tester.widgetList<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(decorators, isNotEmpty);
    for (final decorator in decorators) {
      expect(
        decorator.decoration.floatingLabelStyle?.height,
        greaterThanOrEqualTo(1.3),
        reason: '每个设置输入框的浮动标签都必须保留完整中文字符高度',
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('重新绑定会生成全新的设备身份并清除旧Token', () {
    final repository = NurseConfigRepository();
    final original = NurseAppConfig.defaults(
      '02:11:22:33:44:55',
      '11111111-2222-4333-8444-555555555555',
    ).copyWith(
      departmentConfigured: true,
      websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
      token: 'old-token',
    );

    final reset = repository.withFreshDeviceIdentity(original);

    expect(reset.deviceId, isNot(original.deviceId));
    expect(reset.clientId, isNot(original.clientId));
    expect(reset.token, isEmpty);
    expect(reset.websocketUrl, isEmpty);
    expect(reset.officialPlatform, isTrue);
  });

  test('英语模式播放英语内容而不是读中文', () async {
    final speech = _FakeLocalSpeechService();
    final controller =
        NurseController(localSpeechService: speech)
          ..config = NurseAppConfig.defaults(
            '',
            '',
          ).copyWith(offlineSpeechLanguage: OfflineSpeechLanguage.english)
          ..state = NurseUiState.offline;
    final item = controller.config.quickAnswers.first;

    await controller.playLocalQuickAnswer(item);

    expect(controller.userText, item.englishTitle);
    expect(speech.spoken, item.englishAnswer);
    expect(speech.spokenLanguage, OfflineSpeechLanguage.english);
  });

  testWidgets('应用标题可用', (tester) async {
    await tester.pumpWidget(
      const DigitalNurseApp(home: Scaffold(body: Text('数字护士'))),
    );
    expect(find.text('数字护士'), findsWidgets);
  });

  testWidgets('不同尺寸安卓平板横屏品牌界面无布局溢出', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in <Size>[
      const Size(1024, 600),
      const Size(1280, 800),
      const Size(1920, 1200),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final controller =
          NurseController()
            ..config = NurseAppConfig.defaults(
              '02:11:22:33:44:55',
              '11111111-2222-4333-8444-555555555555',
            ).copyWith(
              departmentConfigured: true,
              websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
              token: 'test-token',
            )
            ..state = NurseUiState.idle;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const DigitalNurseApp(home: NurseScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.bySemanticsLabel('广州中医药大学第三附属医院'), findsOneWidget);
      expect(find.bySemanticsLabel('急诊病房科室标志'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('开始床旁宣教'), findsOneWidget);
      expect(find.text('怎么办理出院？'), findsNothing);
      expect(find.text('普通话'), findsOneWidget);
      expect(find.text('粤语'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '平板尺寸：$size');
    }
  });

  testWidgets('四套主题均可显示长字幕且无布局溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longCaption = List.generate(
      16,
      (index) => '第${index + 1}条：这是用于验证长回答持续显示、自动换行和滚动查看的急诊宣教字幕。',
    ).join('\n');

    for (final style in NurseVisualStyle.values) {
      final controller =
          NurseController()
            ..config = NurseAppConfig.defaults(
              '02:11:22:33:44:55',
              '11111111-2222-4333-8444-555555555555',
            ).copyWith(
              websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
              token: 'test-token',
              visualStyle: style,
            )
            ..state = NurseUiState.speaking
            ..assistantText = longCaption;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const DigitalNurseApp(home: NurseScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('实时字幕'), findsOneWidget);
      expect(find.textContaining('第16条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('新静态真人形象在说话状态下无布局异常', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller =
        NurseController()
          ..config = NurseAppConfig.defaults(
            '02:11:22:33:44:55',
            '11111111-2222-4333-8444-555555555555',
          ).copyWith(
            websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
            token: 'test-token',
          )
          ..state = NurseUiState.speaking
          ..assistantText = '这是新的静态数字护士形象测试。';

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 3900));

    expect(find.text('正在为您讲解'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeLocalSpeechService extends LocalSpeechService {
  String? spoken;
  OfflineSpeechLanguage? spokenLanguage;
  bool throwOnSpeak = false;
  final _controller = StreamController<LocalSpeechEvent>.broadcast(sync: true);

  @override
  Stream<LocalSpeechEvent> get events => _controller.stream;

  @override
  Future<void> speak(
    String text, {
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  }) async {
    if (throwOnSpeak) throw StateError('speech failed');
    spoken = text;
    spokenLanguage = language;
    _controller.add(LocalSpeechEvent.started);
  }

  void complete() {
    _controller.add(LocalSpeechEvent.completed);
  }

  void fail() {
    _controller.add(LocalSpeechEvent.error);
  }

  @override
  Future<void> stop() async {}
}

class _FakeXiaozhiService extends XiaozhiService {
  _FakeXiaozhiService()
    : super(
        websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
        macAddress: '02:11:22:33:44:55',
        clientId: '11111111-2222-4333-8444-555555555555',
        token: 'test-token',
      );

  int suspendCalls = 0;
  int resumeCalls = 0;

  @override
  Future<void> suspendOnlinePlayback() async {
    suspendCalls++;
  }

  @override
  Future<void> resumeOnlinePlayback() async {
    resumeCalls++;
  }

  @override
  Future<void> startListening({String mode = 'manual'}) async {}
}
