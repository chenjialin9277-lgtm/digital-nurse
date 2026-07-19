# Bedside Education Closed-Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first hospital-wide rollout increment: department-managed multilingual bedside education, an always-visible daily language selector, one-question comprehension confirmation, anonymous session events, automatic session clearing, and migration of existing fixed education without losing data.

**Architecture:** Move structured education content out of `NurseAppConfig.quickAnswers` into an Android system SQLite repository exposed through a focused Flutter method channel, while retaining the legacy JSON as a migration and rollback source. This avoids downloadable database dependencies and keeps Android 7+ deployment self-contained. Add a focused `EducationSessionController` for the bedside state machine, separate workbench/playback/settings widgets, and anonymous event persistence. Keep Xiaozhi AI, encrypted credentials, offline TTS, department branding, and current usage records intact.

**Tech Stack:** Flutter 3.44, Dart 3.7, Material 3, Provider, Android `SQLiteOpenHelper`, Flutter `MethodChannel`, SharedPreferences migration source, existing sherpa-onnx offline TTS, Android API 24–36.

## Global Constraints

- Minimum Android version remains Android 7.0 / API 24.
- Supported release ABIs remain `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- Never collect patient name, hospital number, bed number, phone number, face, diagnosis, or treatment data.
- Language selection remains directly visible in normal nurse workflows and never requires administrator authentication.
- Department administrators can edit education content only after settings-password verification.
- Mandarin is required; Cantonese and English are displayed only when their reviewed content is published.
- Network or Xiaozhi failure must not block local education, comprehension, or session completion.
- A correct answer is labeled “本次理解确认完成”, never “患者已充分理解”.
- Every patient-facing session clears transient content when completed, timed out, or backgrounded.
- Preserve current department binding, logo, nurse image, settings password, usage history, and legacy quick answers during upgrade.
- Do not reintroduce synthetic eye or mouth overlays.

---

### Task 1: Add Structured Education Domain Models

**Files:**
- Create: `lib/features/education/models/education_language_content.dart`
- Create: `lib/features/education/models/education_item.dart`
- Create: `lib/features/education/models/comprehension_result.dart`
- Test: `test/features/education/education_item_test.dart`
- Test support: `test/features/education/education_test_fixtures.dart`

**Interfaces:**
- Consumes: `OfflineSpeechLanguage` from `lib/models/offline_speech_language.dart`.
- Produces: `EducationLanguageContent`, `EducationItem`, `ComprehensionResult`, `EducationItem.contentFor()`, `EducationItem.isAvailableIn()`, `EducationItem.copyWith()`, JSON round-trip APIs, and shared `educationFixture()`／`reviewedItem` test fixtures used by all later tasks.

- [x] **Step 1: Write failing model tests**

```dart
test('education item round-trips multilingual content and question', () {
  final item = EducationItem(
    id: 'admission',
    category: '入院宣教',
    contents: {
      OfflineSpeechLanguage.mandarin: EducationLanguageContent(
        title: '入院注意事项',
        body: '请配合护士完成身份核对。',
        summary: '配合身份核对',
        question: '办理入院后应该怎么做？',
        options: const ['配合护士核对身份', '自行离开病区'],
        correctIndex: 0,
        explanation: '应配合护士完成身份核对。',
        published: true,
        needsReview: false,
      ),
    },
    estimatedManualMinutes: 3,
    sortOrder: 0,
    favorite: true,
    enabled: true,
    version: 1,
    createdAt: DateTime.utc(2026, 7, 19),
    updatedAt: DateTime.utc(2026, 7, 19),
  );

  final restored = EducationItem.fromJson(item.toJson());
  expect(restored, item);
  expect(restored.isAvailableIn(OfflineSpeechLanguage.mandarin), isTrue);
  expect(restored.isAvailableIn(OfflineSpeechLanguage.cantonese), isFalse);
});

test('answer returns first-attempt comprehension result without patient data', () {
  final result = ComprehensionResult(
    itemId: 'admission',
    itemVersion: 1,
    language: OfflineSpeechLanguage.mandarin,
    selectedIndex: 0,
    correctIndex: 0,
    attempt: 1,
  );
  expect(result.isCorrect, isTrue);
  expect(result.toJson().keys, isNot(contains('patientName')));
});
```

Create the shared fixture with this public signature:

```dart
EducationItem educationFixture({
  String id = 'admission',
  String category = '入院宣教',
  int sortOrder = 0,
  bool includeCantonese = true,
  bool includeEnglish = true,
});

final EducationItem reviewedItem = educationFixture();

LocalQuickAnswer customLegacyAnswer(int index) => LocalQuickAnswer(
  title: '旧版自定义宣教${index + 1}',
  answer: '旧版普通话内容${index + 1}',
  cantoneseTitle: '旧版粤语宣教${index + 1}',
  cantoneseAnswer: '旧版粤语内容${index + 1}',
  englishTitle: 'Legacy Education ${index + 1}',
  englishAnswer: 'Legacy English content ${index + 1}',
);
```

- [x] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_item_test.dart
```

Expected: FAIL because the education domain classes do not exist.

- [x] **Step 3: Implement immutable models and validation**

Implement `EducationLanguageContent` with these exact fields and guards:

```dart
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
      correctIndex >= 0 &&
      correctIndex < options.length &&
      explanation.trim().isNotEmpty;
}
```

`EducationItem.isAvailableIn(language)` returns true only when the item is enabled and the selected language content is published and complete. `needsReview` produces an administrator warning badge but does not make migrated clinical content disappear. New or edited translations cannot be published while `needsReview` is true. JSON language keys use `OfflineSpeechLanguage.name`.

- [x] **Step 4: Run model tests and full analyzer**

Run:

```bash
flutter test --no-pub test/features/education/education_item_test.dart
dart analyze lib test
```

Expected: both commands exit 0.

- [x] **Step 5: Commit the model slice**

```bash
git add lib/features/education/models test/features/education/education_item_test.dart
git commit -m "feat: add structured bedside education models"
```

### Task 2: Add Native Android SQLite Repository and Lossless Legacy Migration

**Files:**
- Create: `lib/features/education/data/education_repository.dart`
- Create: `lib/features/education/data/native_education_repository.dart`
- Create: `lib/features/education/data/legacy_education_migrator.dart`
- Create: `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseHelper.kt`
- Create: `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseChannel.kt`
- Modify: `android/app/src/main/kotlin/com/digitalnurse/app/MainActivity.kt`
- Test: `test/features/education/education_repository_test.dart`
- Test: `test/features/education/legacy_education_migrator_test.dart`
- Test support: `test/features/education/fake_education_repository.dart`

**Interfaces:**
- Consumes: `EducationItem`, `LocalQuickAnswer`, and `NurseAppConfig.quickAnswers`.
- Produces: `NativeEducationRepository`, `EducationRepository.loadActive()`, `save()`, `replaceAll()`, `replaceAllAndMarkLegacyMigrated()`, `softDelete()`, `reorder()`, `LegacyEducationMigrator.migrateIfNeeded()`, and `FakeEducationRepository` for widget tests.

- [x] **Step 1: Add repository channel contract tests**

```dart
test('repository saves, orders, versions, and soft deletes education', () async {
  final repository = NativeEducationRepository(channel: mockedChannel);
  final itemA = educationFixture(id: 'a', sortOrder: 0);
  final itemB = educationFixture(id: 'b', sortOrder: 1);
  await repository.replaceAll([itemB.copyWith(sortOrder: 1), itemA]);
  expect((await repository.loadActive()).map((e) => e.id), ['a', 'b']);

  await repository.save(itemA.copyWith(version: 2));
  expect((await repository.loadActive()).first.version, 2);

  await repository.softDelete('a');
  expect((await repository.loadActive()).map((e) => e.id), ['b']);
});
```

- [x] **Step 2: Run repository tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_repository_test.dart
```

Expected: FAIL because the native repository and database channel do not exist.

- [x] **Step 3: Add the native database channel and schema**

Use Android's built-in `SQLiteOpenHelper`; do not add any Flutter database dependency. Create database version 1 with:

```sql
CREATE TABLE education_items (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  contents_json TEXT NOT NULL,
  estimated_minutes INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  favorite INTEGER NOT NULL,
  enabled INTEGER NOT NULL,
  version INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

Create `education_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)` and store `legacy_migration_completed=1` only after all legacy rows commit successfully inside one native transaction. Dart calls this atomic operation through `replaceAllAndMarkLegacyMigrated()`.

- [x] **Step 4: Write legacy migration tests**

```dart
test('migration keeps every custom quick answer and marks generated questions for review', () async {
  final config = NurseAppConfig.defaults('device', 'client').copyWith(
    quickAnswers: List.generate(12, customLegacyAnswer),
  );
  final repository = FakeEducationRepository();
  final migrator = LegacyEducationMigrator(repository: repository);

  await migrator.migrateIfNeeded(config);
  final items = await repository.loadActive();

  expect(items, hasLength(12));
  expect(items.first.contentFor(OfflineSpeechLanguage.mandarin).body,
      config.quickAnswers.first.answer);
  expect(items.first.contentFor(OfflineSpeechLanguage.mandarin).needsReview, isTrue);
  await migrator.migrateIfNeeded(config);
  expect(await repository.loadActive(), hasLength(12));
});
```

- [x] **Step 5: Implement transactional migration**

For each `LocalQuickAnswer`, preserve all three titles and bodies. Generate a safe temporary self-check in each language, set `needsReview: true`, and keep the item playable. The generated Mandarin question is “您是否理解以上宣教内容？”, options are “我已理解”, “请再播放一次”, and “请护士进一步解释”; it is not scored as a knowledge check. Default bundled items receive reviewed knowledge-check fixtures stored in `lib/features/education/data/default_education_items.dart`.

- [x] **Step 6: Run repository, migration, and existing configuration tests**

Run:

```bash
flutter test --no-pub test/features/education/education_repository_test.dart test/features/education/legacy_education_migrator_test.dart test/widget_test.dart
```

Expected: all tests pass and existing quick-answer migration tests remain green.

- [ ] **Step 7: Commit persistence and migration**

```bash
git add android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseHelper.kt android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseChannel.kt android/app/src/main/kotlin/com/digitalnurse/app/MainActivity.kt lib/features/education/data test/features/education
git commit -m "feat: persist and migrate bedside education content"
```

### Task 3: Implement the Anonymous Bedside Session State Machine

**Files:**
- Create: `lib/features/education/models/education_session_event.dart`
- Create: `lib/features/education/data/education_event_repository.dart`
- Create: `lib/features/education/data/native_education_event_repository.dart`
- Modify: `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseHelper.kt`
- Modify: `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseChannel.kt`
- Create: `lib/features/education/controllers/education_session_controller.dart`
- Test: `test/features/education/education_session_controller_test.dart`
- Test support: `test/features/education/fake_education_event_repository.dart`

**Interfaces:**
- Consumes: `EducationItem`, `LocalSpeechService`, `OfflineSpeechLanguage`, and `EducationEventRepository`.
- Produces: `EducationSessionStage`, `EducationSessionState`, controller methods `startSession()`, `selectItem()`, `beginPlayback()`, `markSpeechComplete()`, `submitAnswer()`, `requestNurseHelp()`, `replay()`, `finishSession()`, `clearTransientState()`, and `FakeEducationEventRepository.saved` for tests.

- [ ] **Step 1: Write failing state-machine tests**

```dart
test('speech completion opens question and correct answer completes item', () async {
  final events = FakeEducationEventRepository();
  final controller = EducationSessionController(events: events);
  controller.startSession(OfflineSpeechLanguage.mandarin);
  controller.selectItem(reviewedItem);
  controller.beginPlayback();
  controller.markSpeechComplete();
  expect(controller.state.stage, EducationSessionStage.question);

  controller.submitAnswer(0);
  expect(controller.state.result?.isCorrect, isTrue);
  expect(controller.state.feedbackTitle, '本次理解确认完成');
  expect(events.saved.map((e) => e.type), contains(EducationEventType.answer));
});

test('finish clears patient-facing text but preserves anonymous events', () async {
  controller.startSession(OfflineSpeechLanguage.cantonese);
  controller.selectItem(reviewedItem);
  await controller.finishSession();
  expect(controller.state.stage, EducationSessionStage.idle);
  expect(controller.state.selectedItem, isNull);
  expect(controller.state.visibleCaption, isEmpty);
  expect(events.saved, isNotEmpty);
});
```

- [ ] **Step 2: Run controller tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_session_controller_test.dart
```

Expected: FAIL because the session controller does not exist.

- [ ] **Step 3: Implement explicit session stages**

```dart
enum EducationSessionStage {
  idle,
  selecting,
  ready,
  playing,
  question,
  feedback,
}
```

Generate session IDs from secure random bytes. Persist only session ID, department ID, item ID, item version, language, event type, attempt, integer value, and timestamp. Do not add patient fields. `requestNurseHelp()` records the event and sets a prominent nurse-help state without ending the session.

- [ ] **Step 4: Add native database event table**

Upgrade the Android system database to version 2 and create:

```sql
CREATE TABLE education_events (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  department_id TEXT NOT NULL,
  item_id TEXT,
  item_version INTEGER,
  language TEXT,
  event_type TEXT NOT NULL,
  attempt INTEGER,
  value INTEGER,
  occurred_at TEXT NOT NULL
)
```

- [ ] **Step 5: Run controller and database migration tests**

Run:

```bash
flutter test --no-pub test/features/education/education_session_controller_test.dart test/features/education/education_repository_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit the state machine**

```bash
git add lib/features/education/controllers lib/features/education/models/education_session_event.dart lib/features/education/data test/features/education
git commit -m "feat: add anonymous bedside education sessions"
```

### Task 4: Add Department Education Management UI

**Files:**
- Create: `lib/features/education/widgets/education_management_dialog.dart`
- Create: `lib/features/education/widgets/education_item_editor.dart`
- Create: `lib/features/education/widgets/language_content_editor.dart`
- Create: `lib/features/education/widgets/comprehension_question_editor.dart`
- Modify: `lib/widgets/nurse_config_dialog.dart`
- Test: `test/features/education/education_management_dialog_test.dart`
- Test support: `test/features/education/education_widget_harness.dart`

**Interfaces:**
- Consumes: `EducationRepository`, `EducationItem`, and administrator-authenticated settings context.
- Produces: validated create, edit, copy, soft-delete, enable, favorite, reorder, multilingual publish operations, `educationTestApp(Widget child)`, and `fillKnowledgeQuestion(WidgetTester tester)` test helpers.

- [ ] **Step 1: Write failing administrator UI tests**

```dart
testWidgets('administrator can add an item and publish Mandarin only', (tester) async {
  final repository = FakeEducationRepository();
  await tester.pumpWidget(educationTestApp(EducationManagementDialog(repository: repository)));
  await tester.tap(find.text('新增宣教'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('education-title-mandarin')), '骨科术后活动');
  await tester.enterText(find.byKey(const Key('education-body-mandarin')), '请在护士指导下活动。');
  await fillKnowledgeQuestion(tester);
  await tester.tap(find.text('保存并发布普通话'));
  await tester.pumpAndSettle();

  final saved = (await repository.loadActive()).single;
  expect(saved.isAvailableIn(OfflineSpeechLanguage.mandarin), isTrue);
  expect(saved.isAvailableIn(OfflineSpeechLanguage.english), isFalse);
});
```

- [ ] **Step 2: Run the UI test and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_management_dialog_test.dart
```

Expected: FAIL because management widgets do not exist.

- [ ] **Step 3: Build modular editors with validation**

Validation rules are exact: title 1–40 characters; body 1–1200; summary 0–120; question 1–120; 2–4 non-empty unique options; correct index in range; explanation 1–240; estimated minutes 1–30. Publishing Cantonese or English requires every field in that language to pass. Draft saving is allowed, but drafts never appear to patients.

- [ ] **Step 4: Replace the large inline fixed-answer editor**

Remove `_quickTitles`, `_quickAnswers`, `_cantoneseTitles`, `_cantoneseAnswers`, `_englishTitles`, and `_englishAnswers` from `NurseConfigDialog`. Replace the old expansion list with a summary card showing active item count and a password-context-safe “管理本科室宣教内容” button that opens `EducationManagementDialog`.

Keep `NurseAppConfig.quickAnswers` serialization unchanged as a rollback source until v1.0 migration is proven on real devices.

- [ ] **Step 5: Run settings and large-font tests**

Run:

```bash
flutter test --no-pub test/features/education/education_management_dialog_test.dart test/widget_test.dart --plain-name '设置'
```

Expected: all tests pass with no overflow at 1.3× font scale.

- [ ] **Step 6: Commit the management UI**

```bash
git add lib/features/education/widgets lib/widgets/nurse_config_dialog.dart test/features/education/education_management_dialog_test.dart
git commit -m "feat: add department education management"
```

### Task 5: Add Always-Visible Language Selection and Bedside Workbench

**Files:**
- Create: `lib/features/education/widgets/daily_language_selector.dart`
- Create: `lib/features/education/screens/bedside_education_screen.dart`
- Create: `lib/features/education/widgets/education_catalog.dart`
- Modify: `lib/controllers/nurse_controller.dart`
- Modify: `lib/screens/nurse_screen.dart`
- Test: `test/features/education/bedside_education_screen_test.dart`

**Interfaces:**
- Consumes: active `EducationItem` list, `OfflineSpeechLanguage`, `EducationSessionController`, and `NurseController.setOfflineSpeechLanguage()`.
- Produces: normal-workflow language switching, category/search/favorite/recent filtering, selection of a playable item, and test-local builders `buildNurseAppWithEducation(List<EducationItem>)` and `buildBedsideScreen(List<EducationItem>)` defined in `bedside_education_screen_test.dart`.

- [ ] **Step 1: Write failing language and workbench tests**

```dart
testWidgets('language switch is visible without opening settings', (tester) async {
  await tester.pumpWidget(buildNurseAppWithEducation(items));
  expect(find.text('普通话'), findsOneWidget);
  expect(find.text('粤语'), findsOneWidget);
  expect(find.text('English'), findsOneWidget);
  expect(find.byType(NurseConfigDialog), findsNothing);
});

testWidgets('unpublished target-language item is marked unavailable', (tester) async {
  await tester.pumpWidget(buildBedsideScreen(items));
  await tester.tap(find.text('English'));
  await tester.pump();
  expect(find.text('该语言暂未提供'), findsOneWidget);
  expect(find.text('开始宣教'), findsNothing);
});
```

- [ ] **Step 2: Run workbench tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/bedside_education_screen_test.dart
```

Expected: FAIL because the shared language selector and workbench do not exist.

- [ ] **Step 3: Implement a shared language selector**

`DailyLanguageSelector` accepts `value`, `onChanged`, and `compact`. It uses three `ChoiceChip`s with fixed visible labels `普通话`, `粤语`, and `English`. It is rendered both on the main interaction panel and at the top of `BedsideEducationScreen`; it never checks administrator state.

- [ ] **Step 4: Implement the workbench**

The screen includes a back button, selected language, category chips, local search, favorites, recent items, and a scrollable list. Selecting an unavailable translation shows the reason and does not silently fall back to Mandarin. Selecting an available item calls `session.selectItem(item)` and navigates to playback.

- [ ] **Step 5: Run 1024×600 and 1920×1200 widget tests**

Run:

```bash
flutter test --no-pub test/features/education/bedside_education_screen_test.dart test/widget_test.dart --plain-name '不同尺寸'
```

Expected: all tests pass with zero overflow exceptions.

- [ ] **Step 6: Commit the workbench**

```bash
git add lib/features/education/screens lib/features/education/widgets/daily_language_selector.dart lib/features/education/widgets/education_catalog.dart lib/controllers/nurse_controller.dart lib/screens/nurse_screen.dart test/features/education/bedside_education_screen_test.dart
git commit -m "feat: add bedside education workbench"
```

### Task 6: Add Patient Playback, Comprehension, and Automatic Clearing

**Files:**
- Create: `lib/features/education/screens/education_playback_screen.dart`
- Create: `lib/features/education/widgets/comprehension_card.dart`
- Create: `lib/features/education/widgets/education_feedback_card.dart`
- Modify: `lib/features/education/controllers/education_session_controller.dart`
- Modify: `lib/services/local_speech_service.dart`
- Test: `test/features/education/education_playback_screen_test.dart`

**Interfaces:**
- Consumes: `EducationSessionController`, `LocalSpeechEvent`, and `DailyLanguageSelector`.
- Produces: synchronized playback/captions, question transition, replay, nurse-help path, session completion, transient-state clearing, and test-local `buildSessionController()`／`buildPlaybackApp()` builders defined in `education_playback_screen_test.dart`.

- [ ] **Step 1: Write failing end-to-end widget flow**

```dart
testWidgets('playback opens question, gives neutral correction, and clears on finish', (tester) async {
  final speech = FakeLocalSpeechService();
  final session = buildSessionController(speech: speech, item: reviewedItem);
  await tester.pumpWidget(buildPlaybackApp(session));
  await tester.tap(find.text('开始播放'));
  speech.complete();
  await tester.pump();
  final mandarin = reviewedItem.contentFor(OfflineSpeechLanguage.mandarin);
  expect(find.text(mandarin.question), findsOneWidget);

  await tester.tap(find.text(mandarin.options[1]));
  await tester.pump();
  expect(find.text('我们再看一下重点'), findsOneWidget);
  expect(find.text('重新听一遍'), findsOneWidget);

  await tester.tap(find.text('结束本次宣教'));
  await tester.pumpAndSettle();
  expect(session.state.selectedItem, isNull);
  expect(find.text(mandarin.body), findsNothing);
});
```

- [ ] **Step 2: Run playback test and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_playback_screen_test.dart
```

Expected: FAIL because playback and comprehension widgets do not exist.

- [ ] **Step 3: Implement patient-facing playback**

Use the existing offline TTS and progressive caption mechanism. The patient page shows department header, AI-assistance label, language selector, large caption, summary, progress, playback controls, and “请护士进一步解释”. Disable language switching while audio is actively playing; after pause or completion, switching reloads the reviewed content for the selected language.

- [ ] **Step 4: Implement comprehension and feedback copy**

Correct title: `本次理解确认完成`. Incorrect title: `我们再看一下重点`. Nurse-help title: `请责任护士进一步解释`. Never display red failure language, scores, ranks, or claims of full understanding.

- [ ] **Step 5: Implement lifecycle clearing**

Observe `AppLifecycleState.paused`, `inactive`, and `detached`; stop local audio and call `clearTransientState()`. Add a configurable inactivity timer with a default of 5 minutes during a bedside session. Display a 30-second warning before clearing. Explicit finish clears immediately.

- [ ] **Step 6: Run playback, lifecycle, and existing TTS tests**

Run:

```bash
flutter test --no-pub test/features/education/education_playback_screen_test.dart test/features/education/education_session_controller_test.dart test/widget_test.dart --plain-name '英语模式播放英语内容'
```

Expected: all tests pass.

- [ ] **Step 7: Commit patient playback**

```bash
git add lib/features/education/screens/education_playback_screen.dart lib/features/education/widgets/comprehension_card.dart lib/features/education/widgets/education_feedback_card.dart lib/features/education/controllers/education_session_controller.dart lib/services/local_speech_service.dart test/features/education/education_playback_screen_test.dart
git commit -m "feat: complete bedside education comprehension flow"
```

### Task 7: Add Anonymous Phase-One Education Summary

**Files:**
- Create: `lib/features/education/models/education_analytics_summary.dart`
- Create: `lib/features/education/data/education_analytics_service.dart`
- Modify: `lib/widgets/usage_records_dialog.dart`
- Modify: `lib/services/usage_export_service.dart`
- Test: `test/features/education/education_analytics_service_test.dart`
- Test: `test/features/education/education_export_test.dart`

**Interfaces:**
- Consumes: `education_events` rows and existing usage report date range.
- Produces: session count, play count, completion rate, replay count, first-attempt correct rate, nurse-help count, language distribution, additional Excel sheets, and `sampleEducationEvents` in the shared test fixtures.

- [ ] **Step 1: Write failing analytics formula tests**

```dart
test('summary calculates first-attempt accuracy and nurse-help rate', () {
  final summary = EducationAnalyticsSummary.fromEvents(sampleEducationEvents);
  expect(summary.sessionCount, 2);
  expect(summary.playCount, 3);
  expect(summary.firstAttemptCorrectCount, 2);
  expect(summary.firstAttemptCorrectRate, closeTo(2 / 3, 0.001));
  expect(summary.nurseHelpCount, 1);
});
```

- [ ] **Step 2: Run analytics tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_analytics_service_test.dart
```

Expected: FAIL because the summary does not exist.

- [ ] **Step 3: Implement exact metric denominators**

Completion rate denominator is playback-start events; first-attempt accuracy denominator is items with a submitted first attempt; nurse-help rate denominator is completed bedside sessions. Zero denominators return 0, never NaN.

- [ ] **Step 4: Add education sections to usage UI and Excel**

Add read-only cards for the selected date range and Excel worksheets named `床旁宣教汇总`, `理解确认`, and `宣教事件明细`. Event detail contains random session ID but no patient fields. The report includes a note that estimated saved time is an estimate.

- [ ] **Step 5: Run export and existing usage tests**

Run:

```bash
flutter test --no-pub test/features/education/education_analytics_service_test.dart test/features/education/education_export_test.dart test/widget_test.dart --plain-name 'Excel报表'
```

Expected: all tests pass and existing worksheets remain present.

- [ ] **Step 6: Commit analytics**

```bash
git add lib/features/education/models/education_analytics_summary.dart lib/features/education/data/education_analytics_service.dart lib/widgets/usage_records_dialog.dart lib/services/usage_export_service.dart test/features/education
git commit -m "feat: report anonymous bedside education outcomes"
```

### Task 8: Integrate Startup Migration and Preserve Existing Behavior

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/controllers/nurse_controller.dart`
- Modify: `lib/screens/nurse_screen.dart`
- Modify: `lib/models/nurse_app_config.dart`
- Test: `test/features/education/education_upgrade_integration_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: repository, migrator, session controller, current `NurseController`, and current configuration.
- Produces: initialized education repository before the home screen becomes interactive, with legacy rollback data untouched; the test file defines `legacyV014Preferences()`, `UpgradeHarness`, and `buildUpgradeHarness()` against temporary preferences and a mocked native repository channel.

- [ ] **Step 1: Write failing upgrade integration test**

```dart
testWidgets('v0.14 custom content migrates and remains playable after upgrade', (tester) async {
  SharedPreferences.setMockInitialValues(legacyV014Preferences());
  final harness = await buildUpgradeHarness();
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();

  expect(find.text('开始床旁宣教'), findsOneWidget);
  await tester.tap(find.text('开始床旁宣教'));
  await tester.pumpAndSettle();
  expect(find.text('旧版自定义宣教'), findsOneWidget);
  expect(harness.config.quickAnswers, isNotEmpty);
});
```

- [ ] **Step 2: Run the upgrade test and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_upgrade_integration_test.dart
```

Expected: FAIL because startup does not initialize or migrate the education database.

- [ ] **Step 3: Wire dependency initialization**

Open the database, run migration, load active education, and then notify the UI. If database initialization fails, keep the current v0.14 fixed-answer UI available and show an administrator-visible diagnostic message; do not present an empty catalog.

- [ ] **Step 4: Preserve quick-answer rollback source**

Do not remove `quickAnswers` from `NurseAppConfig`, JSON, `copyWith`, or SharedPreferences. When administrators save new education, write a compatibility snapshot back to `quickAnswers` using only the currently published three-language title/body fields so rollback to v0.14 does not produce an empty fixed-answer list.

- [ ] **Step 5: Run the complete automated suite**

Run:

```bash
flutter test --no-pub
dart analyze lib test
```

Expected: all tests pass and analyzer reports `No issues found!`.

- [ ] **Step 6: Commit integration**

```bash
git add lib/main.dart lib/controllers/nurse_controller.dart lib/screens/nurse_screen.dart lib/models/nurse_app_config.dart test/features/education/education_upgrade_integration_test.dart test/widget_test.dart
git commit -m "feat: integrate bedside education upgrade path"
```

### Task 9: Release Verification and APK Delivery

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_CHECKLIST.md`
- Create: `outputs/数字护士-v0.15.0-床旁宣教闭环版-更新说明.md`
- Create: `outputs/数字护士-v0.15.0-SHA256校验值.txt`
- Create: `outputs/数字护士-v0.15.0-床旁宣教闭环版.apk`

**Interfaces:**
- Consumes: completed Phase One implementation and release signing key.
- Produces: signed universal APK, source backup, checksums, and user-facing update notes.

- [ ] **Step 1: Bump version**

Set:

```yaml
version: 0.15.0+17
```

- [ ] **Step 2: Run fresh verification**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze lib test
flutter test --no-pub
```

Expected: format exits 0, analyzer reports no issues, and every test passes.

- [ ] **Step 3: Build signed universal release APK**

Build from a temporary path without spaces, preserving the existing signing configuration:

```bash
flutter build apk --release --no-pub
```

Expected: `app-release.apk` is created and contains `armeabi-v7a`, `arm64-v8a`, and `x86_64` libraries.

- [ ] **Step 4: Verify identity and signature**

Verify package `com.digitalnurse.app`, version code `17`, version name `0.15.0`, minimum SDK `24`, target SDK `36`, v2 signature validity, and certificate SHA-256 `4baff6b7d01271a1bbc8627696540616c2223ca3dc02690d7e00f37214517c47`.

- [ ] **Step 5: Document installation and release blockers**

Update notes must instruct users to install over v0.14.1 without uninstalling. Keep the explicit release blocker that ordinary Mandarin “小雅”, Cantonese, and English model commercial rights must be resolved before hospital-wide formal publication.

- [ ] **Step 6: Package source and calculate checksums**

Create a private source/material/model/signing backup excluding build caches, calculate SHA-256 for APK and backup, and place all deliverables under `/Users/jialeisi/Desktop/数字人/outputs`.

- [ ] **Step 7: Commit release metadata**

```bash
git add pubspec.yaml README.md RELEASE_CHECKLIST.md
git commit -m "release: prepare bedside education closed-loop v0.15.0"
```
