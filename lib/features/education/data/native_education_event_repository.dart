import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/education_session_event.dart';
import 'education_event_repository.dart';

class NativeEducationEventRepository implements EducationEventRepository {
  NativeEducationEventRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'digital_nurse/education_database';
  final MethodChannel _channel;

  @override
  Future<void> save(EducationSessionEvent event) => _channel.invokeMethod(
    'saveEducationEvent',
    {'event': jsonEncode(event.toJson())},
  );

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async {
    final encodedEvents = await _channel
        .invokeMethod<List<dynamic>>('loadEducationEvents', {
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
        });
    if (encodedEvents == null) return const [];
    return List.unmodifiable(
      encodedEvents.map((encoded) {
        if (encoded is! String) {
          throw const FormatException('宣教事件数据格式不正确');
        }
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) {
          throw const FormatException('宣教事件内容不正确');
        }
        return EducationSessionEvent.fromJson(decoded.cast<String, dynamic>());
      }),
    );
  }
}
