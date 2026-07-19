import 'package:digital_nurse/features/education/data/education_repository.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';

class FakeEducationRepository implements EducationRepository {
  final Map<String, EducationItem> _items = {};
  bool migrationCompleted = false;
  int atomicMigrationWrites = 0;

  @override
  Future<List<EducationItem>> loadActive() async {
    final values =
        _items.values.where((item) => item.enabled).toList()
          ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return List.unmodifiable(values);
  }

  @override
  Future<List<EducationItem>> loadAll() async {
    final values =
        _items.values.toList()
          ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return List.unmodifiable(values);
  }

  @override
  Future<void> replaceAll(List<EducationItem> items) async {
    _items
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
  }

  @override
  Future<void> replaceAllAndMarkLegacyMigrated(
    List<EducationItem> items,
  ) async {
    await replaceAll(items);
    migrationCompleted = true;
    atomicMigrationWrites += 1;
  }

  @override
  Future<void> save(EducationItem item) async => _items[item.id] = item;

  @override
  Future<void> softDelete(String id) async {
    _items.remove(id);
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final item = _items[orderedIds[index]];
      if (item != null) _items[item.id] = item.copyWith(sortOrder: index);
    }
  }

  @override
  Future<bool> isLegacyMigrationCompleted() async => migrationCompleted;

  @override
  Future<void> markLegacyMigrationCompleted() async {
    migrationCompleted = true;
  }
}
