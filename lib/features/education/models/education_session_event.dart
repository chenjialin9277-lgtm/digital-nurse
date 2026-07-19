import '../../../models/offline_speech_language.dart';

enum EducationEventType {
  sessionStarted,
  itemSelected,
  playbackStarted,
  playbackCompleted,
  answer,
  replay,
  nurseHelp,
  sessionCompleted,
  sessionCleared,
}

class EducationSessionEvent {
  const EducationSessionEvent({
    required this.id,
    required this.sessionId,
    required this.departmentId,
    required this.itemId,
    required this.itemVersion,
    required this.language,
    required this.type,
    required this.attempt,
    required this.value,
    required this.occurredAt,
  });

  final String id;
  final String sessionId;
  final String departmentId;
  final String? itemId;
  final int? itemVersion;
  final OfflineSpeechLanguage? language;
  final EducationEventType type;
  final int? attempt;
  final int? value;
  final DateTime occurredAt;

  factory EducationSessionEvent.fromJson(Map<String, dynamic> json) =>
      EducationSessionEvent(
        id: json['id'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        departmentId: json['departmentId'] as String? ?? '',
        itemId: json['itemId'] as String?,
        itemVersion: (json['itemVersion'] as num?)?.toInt(),
        language:
            json['language'] == null
                ? null
                : OfflineSpeechLanguage.fromStored(json['language']),
        type: EducationEventType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => EducationEventType.sessionCleared,
        ),
        attempt: (json['attempt'] as num?)?.toInt(),
        value: (json['value'] as num?)?.toInt(),
        occurredAt:
            DateTime.tryParse(json['occurredAt'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'departmentId': departmentId,
    'itemId': itemId,
    'itemVersion': itemVersion,
    'language': language?.storedValue,
    'type': type.name,
    'attempt': attempt,
    'value': value,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EducationSessionEvent &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.departmentId == departmentId &&
          other.itemId == itemId &&
          other.itemVersion == itemVersion &&
          other.language == language &&
          other.type == type &&
          other.attempt == attempt &&
          other.value == value &&
          other.occurredAt == occurredAt;

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    departmentId,
    itemId,
    itemVersion,
    language,
    type,
    attempt,
    value,
    occurredAt,
  );
}
