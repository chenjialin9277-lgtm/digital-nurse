import '../models/offline_speech_language.dart';

/// Splits a long education script into a short natural opening and the
/// remaining body. The opening can be synthesized and played first so the user
/// hears speech without waiting for the whole paragraph to finish generating.
List<String> splitSpeechForFastStart(
  String text,
  OfflineSpeechLanguage language,
) {
  final runes = text.runes.toList(growable: false);
  final isEnglish = language == OfflineSpeechLanguage.english;
  final minimum = isEnglish ? 36 : 10;
  final maximum = isEnglish ? 90 : 28;
  if (runes.length <= maximum) return [text];

  final strongPunctuation = (isEnglish ? '.?!;:' : '。！？；：').runes.toSet();
  final softPunctuation = (isEnglish ? ',' : '，、,').runes.toSet();
  final segments = <String>[];
  var remaining = runes;

  while (remaining.length > maximum) {
    final boundary = _findBoundary(
      remaining,
      minimum: minimum,
      maximum: maximum,
      isEnglish: isEnglish,
      strongPunctuation: strongPunctuation,
      softPunctuation: softPunctuation,
    );
    segments.add(String.fromCharCodes(remaining.take(boundary)));
    remaining = remaining.skip(boundary).toList(growable: false);
  }
  if (remaining.isNotEmpty) segments.add(String.fromCharCodes(remaining));
  return segments;
}

int _findBoundary(
  List<int> runes, {
  required int minimum,
  required int maximum,
  required bool isEnglish,
  required Set<int> strongPunctuation,
  required Set<int> softPunctuation,
}) {
  int? softBoundary;
  int? whitespaceBoundary;

  for (var index = minimum - 1; index < maximum; index++) {
    final rune = runes[index];
    if (strongPunctuation.contains(rune)) {
      return index + 1;
    }
    if (softPunctuation.contains(rune)) softBoundary = index + 1;
    if (isEnglish && _isWhitespace(rune)) whitespaceBoundary = index + 1;
  }

  return softBoundary ?? whitespaceBoundary ?? maximum;
}

bool _isWhitespace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
