import 'package:flutter/services.dart';

import '../features/education/models/education_analytics_summary.dart';
import '../features/education/models/education_session_event.dart';
import '../models/app_usage_record.dart';

class UsageExportService {
  const UsageExportService();

  static const _channel = MethodChannel('digital_nurse/system');

  Future<String?> exportXlsx({
    required DateTime startDate,
    required DateTime endDate,
    required List<AppUsageRecord> records,
    required String hospitalName,
    required String wardName,
    List<EducationSessionEvent> educationEvents = const [],
    int estimatedSavedMinutes = 0,
  }) async {
    final summary = AppUsageSummary(records);
    final summaryRows = <List<Object>>[
      <Object>['数字护士使用记录统计汇总'],
      <Object>['医院', hospitalName],
      <Object>['病区', wardName],
      <Object>['统计开始日期', _date(startDate)],
      <Object>['统计结束日期', _date(endDate)],
      <Object>['导出时间', _dateTime(DateTime.now())],
      <Object>['统计项目', '次数'],
      <Object>['APP启动', summary.launchCount],
      <Object>['服务使用合计', summary.serviceCount],
      <Object>['语音提问', summary.countOf(AppUsageType.voiceQuestion)],
      <Object>['固定宣教', summary.countOf(AppUsageType.fixedEducation)],
      <Object>['联系护士', summary.countOf(AppUsageType.contactNurse)],
    ];
    final detailRows = <List<Object>>[
      <Object>['序号', '日期', '时间', '使用类型'],
      ...List<List<Object>>.generate(records.length, (index) {
        final record = records[index];
        return <Object>[
          index + 1,
          _date(record.occurredAt),
          _time(record.occurredAt),
          record.type.label,
        ];
      }),
    ];
    final education = EducationAnalyticsSummary.fromEvents(educationEvents);
    final educationSummaryRows = <List<Object>>[
      <Object>['床旁宣教汇总'],
      <Object>['统计项目', '结果'],
      <Object>['宣教会话数', education.sessionCount],
      <Object>['播放次数', education.playCount],
      <Object>['播放完成数', education.playbackCompletedCount],
      <Object>['播放完成率', _percent(education.completionRate)],
      <Object>['重播次数', education.replayCount],
      <Object>['首次理解题正确率', _percent(education.firstAttemptCorrectRate)],
      <Object>['请护士解释次数', education.nurseHelpCount],
      <Object>[
        '普通话播放',
        education.languageCounts.entries
            .firstWhere((e) => e.key.name == 'mandarin')
            .value,
      ],
      <Object>[
        '粤语播放',
        education.languageCounts.entries
            .firstWhere((e) => e.key.name == 'cantonese')
            .value,
      ],
      <Object>[
        '英语播放',
        education.languageCounts.entries
            .firstWhere((e) => e.key.name == 'english')
            .value,
      ],
      <Object>['预计节省护士宣教时间（估算）', '$estimatedSavedMinutes分钟'],
      <Object>['说明', '节省时间为估算值，不代表实际工时。'],
    ];
    final comprehensionRows = <List<Object>>[
      <Object>['序号', '匿名会话ID', '日期时间', '宣教项目ID', '版本', '语言', '作答次数', '是否正确'],
      ...educationEvents
          .where((event) => event.type == EducationEventType.answer)
          .toList()
          .asMap()
          .entries
          .map((entry) {
            final event = entry.value;
            return <Object>[
              entry.key + 1,
              event.sessionId,
              _dateTime(event.occurredAt.toLocal()),
              event.itemId ?? '',
              event.itemVersion ?? '',
              event.language?.label ?? '',
              event.attempt ?? '',
              event.value == 1 ? '是' : '否',
            ];
          }),
    ];
    final educationEventRows = <List<Object>>[
      <Object>['序号', '匿名会话ID', '日期时间', '科室标识', '宣教项目ID', '版本', '语言', '事件'],
      ...educationEvents.asMap().entries.map((entry) {
        final event = entry.value;
        return <Object>[
          entry.key + 1,
          event.sessionId,
          _dateTime(event.occurredAt.toLocal()),
          event.departmentId,
          event.itemId ?? '',
          event.itemVersion ?? '',
          event.language?.label ?? '',
          _eventLabel(event.type),
        ];
      }),
    ];
    final now = DateTime.now();
    final fileName =
        '数字护士使用记录_${_date(startDate)}_${_date(endDate)}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.xlsx';
    return _channel.invokeMethod<String>('saveUsageXlsx', <String, Object>{
      'fileName': fileName,
      'summaryRows': summaryRows,
      'detailRows': detailRows,
      'educationSummaryRows': educationSummaryRows,
      'comprehensionRows': comprehensionRows,
      'educationEventRows': educationEventRows,
    });
  }

  static String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';

  static String _eventLabel(EducationEventType type) => switch (type) {
    EducationEventType.sessionStarted => '开始宣教会话',
    EducationEventType.itemSelected => '选择宣教项目',
    EducationEventType.playbackStarted => '开始播放',
    EducationEventType.playbackCompleted => '播放完成',
    EducationEventType.answer => '理解确认作答',
    EducationEventType.replay => '重新播放',
    EducationEventType.nurseHelp => '请护士解释',
    EducationEventType.sessionCompleted => '宣教会话完成',
    EducationEventType.sessionCleared => '会话清屏',
  };

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  static String _dateTime(DateTime value) => '${_date(value)} ${_time(value)}';
}
