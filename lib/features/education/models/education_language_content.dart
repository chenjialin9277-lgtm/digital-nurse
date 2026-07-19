class EducationLanguageContent {
  const EducationLanguageContent({
    required this.title,
    required this.body,
    required this.summary,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.published,
    required this.needsReview,
  });

  final String title;
  final String body;
  final String summary;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final bool published;
  final bool needsReview;

  bool get isComplete =>
      title.trim().isNotEmpty &&
      body.trim().isNotEmpty &&
      question.trim().isNotEmpty &&
      options.length >= 2 &&
      options.length <= 4 &&
      options.every((option) => option.trim().isNotEmpty) &&
      options.map((option) => option.trim()).toSet().length == options.length &&
      correctIndex >= 0 &&
      correctIndex < options.length &&
      explanation.trim().isNotEmpty;

  EducationLanguageContent copyWith({
    String? title,
    String? body,
    String? summary,
    String? question,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    bool? published,
    bool? needsReview,
  }) => EducationLanguageContent(
    title: title ?? this.title,
    body: body ?? this.body,
    summary: summary ?? this.summary,
    question: question ?? this.question,
    options: List.unmodifiable(options ?? this.options),
    correctIndex: correctIndex ?? this.correctIndex,
    explanation: explanation ?? this.explanation,
    published: published ?? this.published,
    needsReview: needsReview ?? this.needsReview,
  );

  factory EducationLanguageContent.fromJson(Map<String, dynamic> json) =>
      EducationLanguageContent(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        question: json['question'] as String? ?? '',
        options: List.unmodifiable(
          (json['options'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList(),
        ),
        correctIndex: (json['correctIndex'] as num?)?.toInt() ?? -1,
        explanation: json['explanation'] as String? ?? '',
        published: json['published'] as bool? ?? false,
        needsReview: json['needsReview'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'summary': summary,
    'question': question,
    'options': options,
    'correctIndex': correctIndex,
    'explanation': explanation,
    'published': published,
    'needsReview': needsReview,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EducationLanguageContent &&
          other.title == title &&
          other.body == body &&
          other.summary == summary &&
          other.question == question &&
          _listEquals(other.options, options) &&
          other.correctIndex == correctIndex &&
          other.explanation == explanation &&
          other.published == published &&
          other.needsReview == needsReview;

  @override
  int get hashCode => Object.hash(
    title,
    body,
    summary,
    question,
    Object.hashAll(options),
    correctIndex,
    explanation,
    published,
    needsReview,
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
