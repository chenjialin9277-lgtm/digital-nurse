import 'dart:convert';

import 'package:digital_nurse/features/education/data/native_education_event_repository.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('digital_nurse/education_event_test');
  final saved = <String>[];

  setUp(() {
    saved.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          switch (call.method) {
            case 'saveEducationEvent':
              saved.add(arguments['event'] as String);
              return null;
            case 'loadEducationEvents':
              return List<String>.from(saved);
          }
          throw PlatformException(code: 'UNKNOWN_METHOD');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('原生事件仓库往返保留匿名字段', () async {
    final repository = NativeEducationEventRepository(channel: channel);
    final event = EducationSessionEvent(
      id: 'event-1',
      sessionId: 'session-1',
      departmentId: 'emergency_ward',
      itemId: 'admission',
      itemVersion: 1,
      language: OfflineSpeechLanguage.mandarin,
      type: EducationEventType.answer,
      attempt: 1,
      value: 0,
      occurredAt: DateTime.utc(2026, 7, 19, 8),
    );

    await repository.save(event);
    final restored = await repository.loadBetween(
      DateTime.utc(2026, 7, 19),
      DateTime.utc(2026, 7, 20),
    );

    expect(restored, [event]);
    expect(
      (jsonDecode(saved.single) as Map).keys,
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
  });
}
