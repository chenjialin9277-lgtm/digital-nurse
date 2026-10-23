enum OfflineSpeechLanguage {
  mandarin,
  cantonese,
  english;

  String get storedValue => name;

  String get label => switch (this) {
    OfflineSpeechLanguage.mandarin => '普通话',
    OfflineSpeechLanguage.cantonese => '粤语',
    OfflineSpeechLanguage.english => 'English',
  };

  String get editorLabel => switch (this) {
    OfflineSpeechLanguage.mandarin => '普通话（简体中文）',
    OfflineSpeechLanguage.cantonese => '粤语（中文）',
    OfflineSpeechLanguage.english => 'English',
  };

  static OfflineSpeechLanguage fromStored(Object? value) => values.firstWhere(
    (language) => language.storedValue == value,
    orElse: () => OfflineSpeechLanguage.mandarin,
  );
}
