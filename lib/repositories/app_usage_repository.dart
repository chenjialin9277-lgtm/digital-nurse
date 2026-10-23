import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_usage_record.dart';

class AppUsageRepository {
  static const _recordsKey = 'digital_nurse_usage_records_v1';
  static const _maximumRecords = 50000;
  static Future<void> _writeQueue = Future<void>.value();

  Future<void> record(AppUsageType type, {DateTime? occurredAt}) {
    final record = AppUsageRecord(
      occurredAt: occurredAt ?? DateTime.now(),
      type: type,
    );
    _writeQueue = _writeQueue.then((_) => _writeRecord(record)).catchError((_) {
      // 使用记录不能影响数字护士的问答、宣教或启动流程。
    });
    return _writeQueue;
  }

  Future<void> _writeRecord(AppUsageRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = _decode(prefs.getString(_recordsKey));
      records.add(record);
      if (records.length > _maximumRecords) {
        records.removeRange(0, records.length - _maximumRecords);
      }
      await prefs.setString(
        _recordsKey,
        jsonEncode(records.map((record) => record.toJson()).toList()),
      );
    } catch (_) {
      // 使用记录不能影响数字护士的问答、宣教或启动流程。
    }
  }

  Future<List<AppUsageRecord>> query({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _writeQueue;
    final prefs = await SharedPreferences.getInstance();
    final start = _startOfDay(startDate);
    final endExclusive = _startOfDay(endDate).add(const Duration(days: 1));
    final records = _decode(prefs.getString(_recordsKey));
    return records
        .where(
          (record) =>
              !record.occurredAt.isBefore(start) &&
              record.occurredAt.isBefore(endExclusive),
        )
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  List<AppUsageRecord> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <AppUsageRecord>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppUsageRecord.fromJson)
          .where((record) => record.occurredAt.millisecondsSinceEpoch > 0)
          .toList();
    } catch (_) {
      return <AppUsageRecord>[];
    }
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
