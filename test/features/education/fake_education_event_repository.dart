import 'package:digital_nurse/features/education/data/education_event_repository.dart';
import 'package:digital_nurse/features/education/models/education_session_event.dart';

class FakeEducationEventRepository implements EducationEventRepository {
  final List<EducationSessionEvent> saved = [];
  EducationEventType? failOnType;

  @override
  Future<void> save(EducationSessionEvent event) async {
    if (event.type == failOnType) throw StateError('模拟本地数据库写入失败');
    saved.add(event);
  }

  @override
  Future<List<EducationSessionEvent>> loadBetween(
    DateTime start,
    DateTime end,
  ) async =>
      saved
          .where(
            (event) =>
                !event.occurredAt.isBefore(start) &&
                event.occurredAt.isBefore(end),
          )
          .toList();
}
