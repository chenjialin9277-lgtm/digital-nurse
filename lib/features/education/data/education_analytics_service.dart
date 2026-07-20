import '../models/education_analytics_summary.dart';
import '../models/education_item.dart';
import '../models/education_session_event.dart';
import 'education_event_repository.dart';

class EducationAnalyticsResult {
  const EducationAnalyticsResult({required this.events, required this.summary});

  final List<EducationSessionEvent> events;
  final EducationAnalyticsSummary summary;
}

class EducationAnalyticsService {
  const EducationAnalyticsService({required this.events});

  final EducationEventRepository events;

  Future<EducationAnalyticsResult> query({
    required DateTime startDate,
    required DateTime endDate,
    List<EducationItem> items = const [],
  }) async {
    final start =
        DateTime(startDate.year, startDate.month, startDate.day).toUtc();
    final dayAfterEnd =
        DateTime(endDate.year, endDate.month, endDate.day + 1).toUtc();
    final rows = await events.loadBetween(start, dayAfterEnd);
    final estimatedMinutes = {
      for (final item in items) item.id: item.estimatedManualMinutes,
    };
    return EducationAnalyticsResult(
      events: List.unmodifiable(rows),
      summary: EducationAnalyticsSummary.fromEvents(
        rows,
        estimatedMinutesByItem: estimatedMinutes,
      ),
    );
  }
}
