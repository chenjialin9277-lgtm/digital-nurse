import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/education_item.dart';
import 'education_repository.dart';

class NativeEducationRepository implements EducationRepository {
  NativeEducationRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'digital_nurse/education_database';

  final MethodChannel _channel;

  @override
  Future<List<EducationItem>> loadActive() async {
    final encodedItems = await _channel.invokeMethod<List<dynamic>>(
      'loadActive',
    );
    if (encodedItems == null) return const [];
    final items =
        encodedItems.map((encoded) {
          if (encoded is! String) {
            throw const FormatException('宣教数据格式不正确');
          }
          final decoded = jsonDecode(encoded);
          if (decoded is! Map) {
            throw const FormatException('宣教数据内容不正确');
          }
          return EducationItem.fromJson(decoded.cast<String, dynamic>());
        }).toList();
    items.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return List.unmodifiable(items);
  }

  @override
  Future<void> replaceAll(List<EducationItem> items) =>
      _channel.invokeMethod('replaceAll', {'items': _encodeItems(items)});

  @override
  Future<void> replaceAllAndMarkLegacyMigrated(List<EducationItem> items) =>
      _channel.invokeMethod('replaceAllAndMarkLegacyMigrated', {
        'items': _encodeItems(items),
      });

  @override
  Future<void> save(EducationItem item) =>
      _channel.invokeMethod('save', {'item': jsonEncode(item.toJson())});

  @override
  Future<void> softDelete(String id) =>
      _channel.invokeMethod('softDelete', {'id': id});

  @override
  Future<void> reorder(List<String> orderedIds) => _channel.invokeMethod(
    'reorder',
    {'orderedIds': List<String>.unmodifiable(orderedIds)},
  );

  @override
  Future<bool> isLegacyMigrationCompleted() async =>
      await _channel.invokeMethod<bool>('isLegacyMigrationCompleted') ?? false;

  @override
  Future<void> markLegacyMigrationCompleted() =>
      _channel.invokeMethod('markLegacyMigrationCompleted');

  List<String> _encodeItems(List<EducationItem> items) =>
      List.unmodifiable(items.map((item) => jsonEncode(item.toJson())));
}
