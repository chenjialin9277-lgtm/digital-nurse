import '../models/education_item.dart';

abstract interface class EducationRepository {
  Future<List<EducationItem>> loadActive();

  Future<List<EducationItem>> loadAll();

  Future<void> replaceAll(List<EducationItem> items);

  Future<void> replaceAllAndMarkLegacyMigrated(List<EducationItem> items);

  Future<void> save(EducationItem item);

  Future<void> softDelete(String id);

  Future<void> reorder(List<String> orderedIds);

  Future<bool> isLegacyMigrationCompleted();

  Future<void> markLegacyMigrationCompleted();
}
