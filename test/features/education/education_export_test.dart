import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/services/usage_export_service.dart';
import 'package:digital_nurse/widgets/usage_records_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'education_test_fixtures.dart';
import 'fake_education_event_repository.dart';
import 'fake_education_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导出参数包含三张匿名宣教工作表且不含患者字段', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('digital_nurse/system'), (
          call,
        ) async {
          captured = call;
          return '/download/report.xlsx';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('digital_nurse/system'),
            null,
          ),
    );
    final event = EducationSessionEvent(
      id: 'e1',
      sessionId: 'anonymous-session',
      departmentId: 'emergency_ward',
      itemId: 'admission',
      itemVersion: 2,
      language: OfflineSpeechLanguage.mandarin,
      type: EducationEventType.playbackStarted,
      attempt: null,
      value: null,
      occurredAt: DateTime.utc(2026, 7, 20, 9),
    );

    await const UsageExportService().exportXlsx(
      startDate: DateTime(2026, 7, 20),
      endDate: DateTime(2026, 7, 20),
      records: const [],
      hospitalName: '广州中医药大学第三附属医院',
      wardName: '急诊病房',
      educationEvents: [event],
    );

    final arguments = (captured!.arguments as Map).cast<Object?, Object?>();
    for (final key in const [
      'educationSummaryRows',
      'comprehensionRows',
      'educationEventRows',
    ]) {
      expect(arguments[key], isA<List>());
    }
    final encoded = arguments.toString();
    expect(encoded, contains('床旁宣教汇总'));
    expect(encoded, contains('anonymous-session'));
    expect(encoded, contains('估算'));
    for (final forbidden in const [
      'patientName',
      '患者姓名',
      'hospitalNumber',
      '住院号',
      'bedNumber',
      '床号',
      'phone',
      '电话',
      'diagnosis',
      '诊断',
      'treatment',
      '治疗',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
  });

  testWidgets('使用记录页显示匿名宣教指标且小平板不溢出', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.binding.setSurfaceSize(const Size(1024, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final educationRepository = FakeEducationRepository();
    await educationRepository.replaceAll([reviewedItem]);
    final events = FakeEducationEventRepository();
    final now = DateTime.now().toUtc();
    for (final entry
        in <(EducationEventType, int?, int?)>[
          (EducationEventType.sessionStarted, null, null),
          (EducationEventType.playbackStarted, null, null),
          (EducationEventType.playbackCompleted, null, null),
          (EducationEventType.answer, 1, 1),
          (EducationEventType.sessionCompleted, null, null),
        ].indexed) {
      await events.save(
        EducationSessionEvent(
          id: 'event-${entry.$1}',
          sessionId: 'anonymous-session',
          departmentId: 'emergency_ward',
          itemId:
              entry.$2.$1 == EducationEventType.sessionStarted
                  ? null
                  : 'admission',
          itemVersion:
              entry.$2.$1 == EducationEventType.sessionStarted ? null : 1,
          language: OfflineSpeechLanguage.mandarin,
          type: entry.$2.$1,
          attempt: entry.$2.$2,
          value: entry.$2.$3,
          occurredAt: now.add(Duration(seconds: entry.$1)),
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageRecordsDialog(
            config: NurseAppConfig.defaults('device', 'client'),
            educationRepository: educationRepository,
            educationEventRepository: events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('床旁宣教闭环（匿名统计）'), findsOneWidget);
    expect(find.text('不记录患者姓名、住院号或床号'), findsOneWidget);
    expect(find.text('100.0%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
