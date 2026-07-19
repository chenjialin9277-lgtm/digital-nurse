import '../models/education_session_event.dart';

abstract interface class EducationEventRepository {
  Future<void> save(EducationSessionEvent event);

  Future<List<EducationSessionEvent>> loadBetween(DateTime start, DateTime end);
}
