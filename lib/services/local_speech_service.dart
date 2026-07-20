import '../models/offline_speech_language.dart';
import 'local_speech_event.dart';
import 'offline_multilingual_tts.dart';

export 'local_speech_event.dart';

class LocalSpeechService {
  const LocalSpeechService();

  Stream<LocalSpeechEvent> get events => OfflineMultilingualTts.instance.events;

  Stream<Duration> get playbackDurations =>
      OfflineMultilingualTts.instance.playbackDurations;

  Future<void> prepare([
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  ]) => OfflineMultilingualTts.instance.prepare(language);

  Future<void> speak(
    String text, {
    OfflineSpeechLanguage language = OfflineSpeechLanguage.mandarin,
  }) => OfflineMultilingualTts.instance.speak(text, language: language);

  Future<void> stop() => OfflineMultilingualTts.instance.stop();
}
