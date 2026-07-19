import '../../../models/offline_speech_language.dart';

class ComprehensionResult {
  const ComprehensionResult({
    required this.itemId,
    required this.itemVersion,
    required this.language,
    required this.selectedIndex,
    required this.correctIndex,
    required this.attempt,
  });

  final String itemId;
  final int itemVersion;
  final OfflineSpeechLanguage language;
  final int selectedIndex;
  final int correctIndex;
  final int attempt;

  bool get isCorrect => selectedIndex == correctIndex;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'itemVersion': itemVersion,
    'language': language.name,
    'selectedIndex': selectedIndex,
    'correctIndex': correctIndex,
    'attempt': attempt,
    'isCorrect': isCorrect,
  };
}
