enum AppUsageType {
  appLaunch('APP启动'),
  voiceQuestion('语音提问'),
  fixedEducation('固定宣教'),
  contactNurse('联系护士');

  const AppUsageType(this.label);

  final String label;

  static AppUsageType fromName(String? name) {
    return AppUsageType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AppUsageType.appLaunch,
    );
  }
}

class AppUsageRecord {
  const AppUsageRecord({required this.occurredAt, required this.type});

  final DateTime occurredAt;
  final AppUsageType type;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'occurredAt': occurredAt.toIso8601String(),
    'type': type.name,
  };

  factory AppUsageRecord.fromJson(Map<String, dynamic> json) {
    return AppUsageRecord(
      occurredAt:
          DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      type: AppUsageType.fromName(json['type']?.toString()),
    );
  }
}

class AppUsageSummary {
  const AppUsageSummary(this.records);

  final List<AppUsageRecord> records;

  int countOf(AppUsageType type) =>
      records.where((record) => record.type == type).length;

  int get launchCount => countOf(AppUsageType.appLaunch);

  int get serviceCount =>
      records.where((record) => record.type != AppUsageType.appLaunch).length;
}
