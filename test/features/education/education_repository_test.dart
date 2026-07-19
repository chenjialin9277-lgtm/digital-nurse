import 'dart:convert';

import 'package:digital_nurse/features/education/data/native_education_repository.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('digital_nurse/education_database_test');
  final items = <String, EducationItem>{};
  final deletedIds = <String>{};
  var migrationCompleted = false;

  setUp(() {
    items.clear();
    deletedIds.clear();
    migrationCompleted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
          switch (call.method) {
            case 'loadActive':
              final active =
                  items.values
                      .where(
                        (item) => !deletedIds.contains(item.id) && item.enabled,
                      )
                      .toList()
                    ..sort(
                      (left, right) =>
                          left.sortOrder.compareTo(right.sortOrder),
                    );
              return active.map((item) => jsonEncode(item.toJson())).toList();
            case 'replaceAll':
            case 'replaceAllAndMarkLegacyMigrated':
              final encodedItems =
                  (arguments?['items'] as List?)?.cast<String>() ?? const [];
              items
                ..clear()
                ..addEntries(
                  encodedItems.map((encoded) {
                    final item = EducationItem.fromJson(
                      (jsonDecode(encoded) as Map).cast<String, dynamic>(),
                    );
                    return MapEntry(item.id, item);
                  }),
                );
              deletedIds.clear();
              if (call.method == 'replaceAllAndMarkLegacyMigrated') {
                migrationCompleted = true;
              }
              return null;
            case 'save':
              final item = EducationItem.fromJson(
                (jsonDecode(arguments!['item'] as String) as Map)
                    .cast<String, dynamic>(),
              );
              items[item.id] = item;
              deletedIds.remove(item.id);
              return null;
            case 'softDelete':
              deletedIds.add(arguments!['id'] as String);
              return null;
            case 'reorder':
              final orderedIds =
                  (arguments?['orderedIds'] as List?)?.cast<String>() ??
                  const [];
              for (var index = 0; index < orderedIds.length; index++) {
                final item = items[orderedIds[index]];
                if (item != null) {
                  items[item.id] = item.copyWith(sortOrder: index);
                }
              }
              return null;
            case 'isLegacyMigrationCompleted':
              return migrationCompleted;
            case 'markLegacyMigrationCompleted':
              migrationCompleted = true;
              return null;
          }
          throw PlatformException(code: 'UNKNOWN_METHOD');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('数据库按顺序保存、更新并软删除宣教项目', () async {
    final repository = NativeEducationRepository(channel: channel);
    final itemA = educationFixture(id: 'a', sortOrder: 0);
    final itemB = educationFixture(id: 'b', sortOrder: 1);
    await repository.replaceAll([itemB, itemA]);

    expect((await repository.loadActive()).map((item) => item.id), ['a', 'b']);

    await repository.save(itemA.copyWith(version: 2));
    expect((await repository.loadActive()).first.version, 2);

    await repository.softDelete('a');
    expect((await repository.loadActive()).map((item) => item.id), ['b']);
  });

  test('调整排序后读取顺序保持一致', () async {
    final repository = NativeEducationRepository(channel: channel);
    await repository.replaceAll([
      educationFixture(id: 'a', sortOrder: 0),
      educationFixture(id: 'b', sortOrder: 1),
    ]);

    await repository.reorder(['b', 'a']);

    expect((await repository.loadActive()).map((item) => item.id), ['b', 'a']);
  });

  test('旧版内容和迁移标记通过同一原子操作写入', () async {
    final repository = NativeEducationRepository(channel: channel);
    expect(await repository.isLegacyMigrationCompleted(), isFalse);

    await repository.replaceAllAndMarkLegacyMigrated([
      educationFixture(id: 'legacy'),
    ]);

    expect(await repository.isLegacyMigrationCompleted(), isTrue);
    expect((await repository.loadActive()).single.id, 'legacy');
  });
}
