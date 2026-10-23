import '../../../models/offline_speech_language.dart';
import 'education_language_content.dart';

enum EducationItemKind {
  text,
  video;

  static EducationItemKind fromStored(Object? value) => values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => EducationItemKind.text,
  );
}

class EducationItem {
  EducationItem({
    required this.id,
    required this.category,
    required Map<OfflineSpeechLanguage, EducationLanguageContent> contents,
    required this.estimatedManualMinutes,
    required this.sortOrder,
    required this.favorite,
    required this.enabled,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.kind = EducationItemKind.text,
    this.videoTitle = '',
    this.videoPath = '',
  }) : contents = Map.unmodifiable(contents);

  final String id;
  final String category;
  final Map<OfflineSpeechLanguage, EducationLanguageContent> contents;
  final int estimatedManualMinutes;
  final int sortOrder;
  final bool favorite;
  final bool enabled;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final EducationItemKind kind;
  final String videoTitle;
  final String videoPath;

  bool get isVideo => kind == EducationItemKind.video;
  bool get isText => kind == EducationItemKind.text;

  String titleFor(OfflineSpeechLanguage language) {
    if (isVideo) return videoTitle.trim();
    return contentFor(language).title.trim();
  }

  EducationLanguageContent contentFor(OfflineSpeechLanguage language) =>
      contents[language] ??
      const EducationLanguageContent(
        title: '',
        body: '',
        summary: '',
        question: '',
        options: [],
        correctIndex: -1,
        explanation: '',
        published: false,
        needsReview: true,
      );

  bool isAvailableIn(OfflineSpeechLanguage language) {
    if (isVideo) {
      return enabled &&
          videoTitle.trim().isNotEmpty &&
          videoPath.trim().isNotEmpty;
    }
    final content = contents[language];
    return enabled &&
        content != null &&
        content.published &&
        content.isComplete;
  }

  EducationItem copyWith({
    String? id,
    String? category,
    Map<OfflineSpeechLanguage, EducationLanguageContent>? contents,
    int? estimatedManualMinutes,
    int? sortOrder,
    bool? favorite,
    bool? enabled,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    EducationItemKind? kind,
    String? videoTitle,
    String? videoPath,
  }) => EducationItem(
    id: id ?? this.id,
    category: category ?? this.category,
    contents: contents ?? this.contents,
    estimatedManualMinutes:
        estimatedManualMinutes ?? this.estimatedManualMinutes,
    sortOrder: sortOrder ?? this.sortOrder,
    favorite: favorite ?? this.favorite,
    enabled: enabled ?? this.enabled,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    kind: kind ?? this.kind,
    videoTitle: videoTitle ?? this.videoTitle,
    videoPath: videoPath ?? this.videoPath,
  );

  factory EducationItem.fromJson(Map<String, dynamic> json) {
    final rawContents = json['contents'] as Map<String, dynamic>? ?? const {};
    final contents = <OfflineSpeechLanguage, EducationLanguageContent>{};
    for (final language in OfflineSpeechLanguage.values) {
      final raw = rawContents[language.name];
      if (raw is Map) {
        contents[language] = EducationLanguageContent.fromJson(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    return EducationItem(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? '未分类',
      contents: contents,
      estimatedManualMinutes:
          (json['estimatedManualMinutes'] as num?)?.toInt() ?? 1,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      favorite: json['favorite'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      kind: EducationItemKind.fromStored(json['kind']),
      videoTitle: json['videoTitle'] as String? ?? '',
      videoPath: json['videoPath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'contents': {
      for (final entry in contents.entries)
        entry.key.name: entry.value.toJson(),
    },
    'estimatedManualMinutes': estimatedManualMinutes,
    'sortOrder': sortOrder,
    'favorite': favorite,
    'enabled': enabled,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'kind': kind.name,
    'videoTitle': videoTitle,
    'videoPath': videoPath,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EducationItem &&
          other.id == id &&
          other.category == category &&
          _mapEquals(other.contents, contents) &&
          other.estimatedManualMinutes == estimatedManualMinutes &&
          other.sortOrder == sortOrder &&
          other.favorite == favorite &&
          other.enabled == enabled &&
          other.version == version &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.kind == kind &&
          other.videoTitle == videoTitle &&
          other.videoPath == videoPath;

  @override
  int get hashCode => Object.hash(
    id,
    category,
    Object.hashAllUnordered(
      contents.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    estimatedManualMinutes,
    sortOrder,
    favorite,
    enabled,
    version,
    createdAt,
    updatedAt,
    kind,
    videoTitle,
    videoPath,
  );
}

bool _mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
