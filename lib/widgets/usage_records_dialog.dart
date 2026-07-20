import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/education/data/education_analytics_service.dart';
import '../features/education/data/education_event_repository.dart';
import '../features/education/data/education_repository.dart';
import '../features/education/data/native_education_event_repository.dart';
import '../features/education/data/native_education_repository.dart';
import '../features/education/models/education_analytics_summary.dart';
import '../features/education/models/education_session_event.dart';
import '../models/app_usage_record.dart';
import '../models/nurse_app_config.dart';
import '../repositories/app_usage_repository.dart';
import '../services/usage_export_service.dart';

class UsageRecordsDialog extends StatefulWidget {
  const UsageRecordsDialog({
    super.key,
    required this.config,
    this.repository,
    this.educationRepository,
    this.educationEventRepository,
    this.exportService = const UsageExportService(),
  });

  final NurseAppConfig config;
  final AppUsageRepository? repository;
  final EducationRepository? educationRepository;
  final EducationEventRepository? educationEventRepository;
  final UsageExportService exportService;

  @override
  State<UsageRecordsDialog> createState() => _UsageRecordsDialogState();
}

class _UsageRecordsDialogState extends State<UsageRecordsDialog> {
  late final AppUsageRepository _repository;
  late final EducationRepository _educationRepository;
  late final EducationAnalyticsService _educationAnalytics;
  late DateTime _startDate;
  late DateTime _endDate;
  List<AppUsageRecord> _records = const [];
  List<EducationSessionEvent> _educationEvents = const [];
  EducationAnalyticsSummary _educationSummary =
      EducationAnalyticsSummary.fromEvents(const []);
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AppUsageRepository();
    _educationRepository =
        widget.educationRepository ?? NativeEducationRepository();
    _educationAnalytics = EducationAnalyticsService(
      events:
          widget.educationEventRepository ?? NativeEducationEventRepository(),
    );
    final today = DateTime.now();
    _startDate = DateTime(today.year, today.month, today.day);
    _endDate = _startDate;
    _query();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = AppUsageSummary(_records);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 80).clamp(360.0, 820.0).toDouble();
    final dialogHeight = (screen.height - 190).clamp(300.0, 610.0).toDouble();
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.history_outlined),
          SizedBox(width: 10),
          Text('使用记录查询与导出'),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '每次启动APP、语音提问、固定宣教和联系护士都会自动记录在本机。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DateButton(
                  label: '开始日期',
                  value: _startDate,
                  onPressed: () => _pickDate(isStart: true),
                ),
                _DateButton(
                  label: '结束日期',
                  value: _endDate,
                  onPressed: () => _pickDate(isStart: false),
                ),
                OutlinedButton(
                  onPressed: () => _usePreset(0),
                  child: const Text('今天'),
                ),
                OutlinedButton(
                  onPressed: () => _usePreset(6),
                  child: const Text('近7天'),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _query,
                  icon: const Icon(Icons.search),
                  label: const Text('查询'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryCard(
                  label: 'APP启动',
                  count: summary.launchCount,
                  icon: Icons.power_settings_new,
                ),
                _SummaryCard(
                  label: '语音提问',
                  count: summary.countOf(AppUsageType.voiceQuestion),
                  icon: Icons.mic_none_outlined,
                ),
                _SummaryCard(
                  label: '固定宣教',
                  count: summary.countOf(AppUsageType.fixedEducation),
                  icon: Icons.campaign_outlined,
                ),
                _SummaryCard(
                  label: '联系护士',
                  count: summary.countOf(AppUsageType.contactNurse),
                  icon: Icons.notifications_active_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  '床旁宣教闭环（匿名统计）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '不记录患者姓名、住院号或床号',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 66,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _MetricCard(
                      label: '宣教会话',
                      value: '${_educationSummary.sessionCount}次',
                    ),
                    _MetricCard(
                      label: '播放完成率',
                      value: _percent(_educationSummary.completionRate),
                    ),
                    _MetricCard(
                      label: '首次理解正确率',
                      value: _percent(
                        _educationSummary.firstAttemptCorrectRate,
                      ),
                    ),
                    _MetricCard(
                      label: '重播',
                      value: '${_educationSummary.replayCount}次',
                    ),
                    _MetricCard(
                      label: '请护士解释',
                      value: '${_educationSummary.nurseHelpCount}次',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _records.isEmpty
                        ? const Center(child: Text('所选日期内暂无使用记录'))
                        : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _records.length,
                          separatorBuilder:
                              (_, __) => const Divider(height: 1, indent: 18),
                          itemBuilder: (context, index) {
                            final record = _records[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(_iconFor(record.type)),
                              title: Text(record.type.label),
                              subtitle: Text(_date(record.occurredAt)),
                              trailing: Text(
                                _time(record.occurredAt),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: _loading || _exporting ? null : _export,
          icon:
              _exporting
                  ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.download_outlined),
          label: const Text('导出Excel表格'),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: isStart ? '选择开始日期' : '选择结束日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_startDate.isAfter(picked)) _startDate = picked;
      }
    });
    await _query();
  }

  Future<void> _usePreset(int daysBeforeToday) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _endDate = today;
      _startDate = today.subtract(Duration(days: daysBeforeToday));
    });
    await _query();
  }

  Future<void> _query() async {
    setState(() => _loading = true);
    try {
      final recordsFuture = _repository.query(
        startDate: _startDate,
        endDate: _endDate,
      );
      EducationAnalyticsResult educationResult;
      try {
        final items = await _educationRepository.loadActive();
        educationResult = await _educationAnalytics.query(
          startDate: _startDate,
          endDate: _endDate,
          items: items,
        );
      } catch (_) {
        educationResult = EducationAnalyticsResult(
          events: const [],
          summary: EducationAnalyticsSummary.fromEvents(const []),
        );
      }
      final records = await recordsFuture;
      if (!mounted) return;
      setState(() {
        _records = records;
        _educationEvents = educationResult.events;
        _educationSummary = educationResult.summary;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await widget.exportService.exportXlsx(
        startDate: _startDate,
        endDate: _endDate,
        records: _records,
        hospitalName: widget.config.hospitalName,
        wardName: widget.config.wardName,
        educationEvents: _educationEvents,
        estimatedSavedMinutes: _educationSummary.estimatedSavedMinutes,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel表格已保存到：$path'),
          duration: const Duration(seconds: 5),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法导出Excel表格：${error.message ?? error.code}')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  IconData _iconFor(AppUsageType type) => switch (type) {
    AppUsageType.appLaunch => Icons.power_settings_new,
    AppUsageType.voiceQuestion => Icons.mic_none_outlined,
    AppUsageType.fixedEducation => Icons.campaign_outlined,
    AppUsageType.contactNurse => Icons.notifications_active_outlined,
  };

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final date =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label：$date'),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 185,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(label)),
          Text(
            '$count次',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 166,
      height: 62,
      margin: const EdgeInsets.only(right: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
