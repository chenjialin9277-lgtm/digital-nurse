# 首页星标宣教、数字护士播放页与音频恢复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让星标宣教在首页一次点击即播放，在宣教与答题页保留数字护士形象，并彻底修复离线宣教后小智回答无声的音频所有权冲突。

**Architecture:** 新增纯 Dart `OnlinePlaybackGate` 串行化在线音频帧及暂停/恢复转换，`XiaozhiService` 仅通过该门面访问 PCM 播放器。`EducationPlaybackScreen` 通过注入的音频边界回调与小智协调，并在同一页面中用左侧数字护士+右侧阶段内容完成播放到理解题的转换。`NurseController` 缓存活动宣教，首页只渲染星标项并复用同一会话控制器直达播放页。

**Tech Stack:** Flutter 3.44, Dart, Provider, Android `AudioTrack`, `flutter_pcm_player`, Flutter widget/unit tests.

## Global Constraints

- 当前语言未发布时不得默认回退普通话。
- 不新增任何患者姓名、住院号、床号、电话、诊断、治疗或人脸字段。
- 数字护士使用已有静态形象，不恢复不自然的眼嘴叠加动效。
- 首页星标与二级工作台共用 `EducationItem.favorite` 和同一匿名事件统计口径。
- 保持 Android API 24 及 `armeabi-v7a` / `arm64-v8a` / `x86_64` 通用 APK 支持。

---

### Task 1: Serialise Online PCM Ownership and Restore It After Offline Speech

**Files:**
- Create: `lib/services/online_playback_gate.dart`
- Modify: `lib/services/xiaozhi_service.dart`
- Modify: `lib/controllers/nurse_controller.dart`
- Test: `test/services/online_playback_gate_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `AudioUtil.playOpusData`, `AudioUtil.stopPlaying`, `AudioUtil.initPlayer`, `LocalSpeechEvent`.
- Produces: `OnlinePlaybackGate.enqueueFrame(Uint8List)`, `suspend()`, `resume()`, `stop()`; `XiaozhiService.suspendOnlinePlayback()` / `resumeOnlinePlayback()`; `NurseController.suspendOnlineAudioForEducation()` / `resumeOnlineAudioAfterEducation()`.

- [ ] **Step 1: Write failing serialisation and suspend/resume tests**

```dart
test('frames and audio ownership transitions run in strict order', () async {
  final calls = <String>[];
  final gate = OnlinePlaybackGate(
    playFrame: (frame) async => calls.add('frame:${frame.first}'),
    stopPlayer: () async => calls.add('stop'),
    startPlayer: () async => calls.add('start'),
  );

  await gate.enqueueFrame(Uint8List.fromList([1]));
  await gate.suspend();
  await gate.enqueueFrame(Uint8List.fromList([2]));
  await gate.resume();
  await gate.enqueueFrame(Uint8List.fromList([3]));

  expect(calls, ['frame:1', 'stop', 'start', 'frame:3']);
});
```

Add a second test calling `suspend()` and `resume()` twice concurrently; expect exactly one `stop` and one `start`.

- [ ] **Step 2: Run the gate test and verify RED**

Run:

```bash
flutter test --no-pub test/services/online_playback_gate_test.dart
```

Expected: FAIL because `OnlinePlaybackGate` does not exist.

- [ ] **Step 3: Implement the minimal serial gate**

```dart
class OnlinePlaybackGate {
  OnlinePlaybackGate({
    required this.playFrame,
    required this.stopPlayer,
    required this.startPlayer,
  });

  final Future<void> Function(Uint8List) playFrame;
  final Future<void> Function() stopPlayer;
  final Future<void> Function() startPlayer;
  Future<void> _tail = Future<void>.value();
  bool _suspended = false;

  Future<void> enqueueFrame(Uint8List frame) =>
      _serial(() async { if (!_suspended) await playFrame(frame); });

  Future<void> suspend() => _serial(() async {
    if (_suspended) return;
    _suspended = true;
    await stopPlayer();
  });

  Future<void> resume() => _serial(() async {
    if (!_suspended) return;
    await startPlayer();
    _suspended = false;
  });

  Future<void> stop() => _serial(stopPlayer);

  Future<void> _serial(Future<void> Function() operation) {
    final current = _tail.then((_) => operation());
    _tail = current.then<void>((_) {}, onError: (_, __) {});
    return current;
  }
}
```

`_serial` must append the operation after both successful and failed predecessors, and return a Future that completes with the current operation without permanently poisoning the queue.

- [ ] **Step 4: Route all Xiaozhi binary frames through the gate**

Construct the gate in `XiaozhiService` with the three `AudioUtil` callbacks. Replace direct/unawaited `_playAudioFrame` calls with `unawaited(_onlinePlayback.enqueueFrame(...))`. Implement `suspendOnlinePlayback`, `resumeOnlinePlayback`, and make `stopPlayback` use `gate.stop()`.

- [ ] **Step 5: Expose education audio boundaries from the controller**

```dart
Future<void> suspendOnlineAudioForEducation() async {
  await _service?.suspendOnlinePlayback();
}

Future<void> resumeOnlineAudioAfterEducation() async {
  await _service?.resumeOnlinePlayback();
}
```

Update the legacy emergency quick-answer path so every `completed`, `error`, exception, and explicit stop restores online playback after the offline player has released the native `AudioTrack`.

- [ ] **Step 6: Run focused and existing local-answer tests**

Run:

```bash
flutter test --no-pub test/services/online_playback_gate_test.dart test/widget_test.dart --plain-name '固定回答'
```

Expected: all selected tests pass.

- [ ] **Step 7: Commit the audio fix**

```bash
git add lib/services/online_playback_gate.dart lib/services/xiaozhi_service.dart lib/controllers/nurse_controller.dart test/services/online_playback_gate_test.dart test/widget_test.dart
git commit -m "fix: restore xiaozhi audio after offline education"
```

### Task 2: Show the Digital Nurse Through Playback and Comprehension

**Files:**
- Modify: `lib/features/education/screens/education_playback_screen.dart`
- Modify: `lib/features/education/screens/bedside_education_screen.dart`
- Modify: `lib/widgets/nurse_avatar.dart` only if a presentation-only parameter is required
- Test: `test/features/education/education_playback_screen_test.dart`
- Test: `test/features/education/bedside_education_screen_test.dart`

**Interfaces:**
- Consumes: existing `NurseAvatar`, `EducationSessionController`, `LocalSpeechService`, and Task 1 audio callbacks.
- Produces: `EducationPlaybackScreen(nurseAvatarPath:, autoStart:, onOfflinePlaybackStarting:, onOfflinePlaybackEnded:)`; `BedsideEducationScreen(nurseAvatarPath:, onOfflinePlaybackStarting:, onOfflinePlaybackEnded:)`.

- [ ] **Step 1: Write failing avatar, stage-transition, auto-start, and audio-boundary widget tests**

```dart
testWidgets('auto-start playback keeps avatar and replaces captions with question', (tester) async {
  final speech = FakeLocalSpeechService();
  final session = await readySession();
  var suspended = 0;
  var resumed = 0;
  await tester.pumpWidget(playbackApp(
    session,
    speech,
    autoStart: true,
    onOfflinePlaybackStarting: () async => suspended++,
    onOfflinePlaybackEnded: () async => resumed++,
  ));
  await tester.pump();
  expect(find.byType(NurseAvatar), findsOneWidget);
  expect(speech.spoken, isNotNull);
  expect(suspended, 1);

  speech.complete();
  await tester.pump();
  final question = reviewedItem
      .contentFor(OfflineSpeechLanguage.mandarin)
      .question;
  expect(find.text(question), findsOneWidget);
  expect(find.byType(NurseAvatar), findsOneWidget);
  expect(resumed, 1);
});
```

Add cases for speech error, back, background privacy clear, timeout, and replay. Each path must balance one suspend with one resume and never resume twice.

- [ ] **Step 2: Run playback tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_playback_screen_test.dart
```

Expected: FAIL because the playback screen has no avatar, auto-start, or audio boundary parameters.

- [ ] **Step 3: Implement the two-column nurse/stage layout**

Use the left 8/20 width for a card containing `NurseAvatar`; map ready to `NurseUiState.idle`, playing to `NurseUiState.speaking`, question/feedback to `NurseUiState.idle`. Use the right 12/20 width for `_EducationIntroduction` in ready/playing and `ComprehensionCard` / `EducationFeedbackCard` after completion. In compact mode keep a two-column layout with smaller padding so the question remains readable at 1024×600.

- [ ] **Step 4: Add guarded auto-start and balanced audio callbacks**

Schedule `_startPlayback` once after the first frame when `autoStart` is true. Before `speech.speak`, await `onOfflinePlaybackStarting`; after `completed`, `error`, exception, back, lifecycle clear, timeout, and dispose, await or unawait one idempotent `_restoreOnlineAudio()` Future. Replay must suspend again only after the previous restore finishes.

- [ ] **Step 5: Pass avatar and callbacks through the workbench**

Add the same required/optional parameters to `BedsideEducationScreen` and forward them when it constructs `EducationPlaybackScreen`. Existing callers may use empty avatar path and no-op callbacks in tests.

- [ ] **Step 6: Run playback/workbench size and lifecycle tests**

Run:

```bash
flutter test --no-pub test/features/education/education_playback_screen_test.dart test/features/education/bedside_education_screen_test.dart
```

Expected: all tests pass at 1024×600 and 1920×1200 with no overflow.

- [ ] **Step 7: Commit the playback experience**

```bash
git add lib/features/education/screens/education_playback_screen.dart lib/features/education/screens/bedside_education_screen.dart lib/widgets/nurse_avatar.dart test/features/education/education_playback_screen_test.dart test/features/education/bedside_education_screen_test.dart
git commit -m "feat: keep digital nurse visible during education"
```

### Task 3: Put Starred Education on the Home Screen

**Files:**
- Modify: `lib/controllers/nurse_controller.dart`
- Modify: `lib/screens/nurse_screen.dart`
- Test: `test/features/education/education_upgrade_integration_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 2 direct playback parameters and existing `EducationRepository.loadActive()`.
- Produces: `NurseController.activeEducationItems`, `favoriteEducationItems`; home `_FavoriteEducationStrip`; a shared screen helper for direct item playback and full workbench navigation.

- [ ] **Step 1: Write failing home favorite tests**

Create one starred and one unstarred fixture in `FakeEducationRepository`, initialize the controller, and assert:

```dart
expect(find.text(starredTitle), findsOneWidget);
expect(find.text(unstarredTitle), findsNothing);
expect(find.text('更多宣教'), findsOneWidget);
```

Tap the starred title and assert that the playback page opens, `LocalSpeechService.spoken` is set without tapping a second button, and the session selected the starred item. Rapid double-tap must open one route. Switch to a language whose starred content is unpublished and assert that its button is disabled with `该语言暂未提供`.

- [ ] **Step 2: Run home tests and verify RED**

Run:

```bash
flutter test --no-pub test/features/education/education_upgrade_integration_test.dart test/widget_test.dart --plain-name '星标'
```

Expected: FAIL because the home screen only has the workbench launch button.

- [ ] **Step 3: Cache active education in the controller**

Load active education after migration during `initializeLocalState`, expose an immutable list, and refresh it from `loadActiveEducation()`. Derive favorites with `where((item) => item.favorite)`. Refresh after closing settings so administrator star changes appear without restarting the app.

- [ ] **Step 4: Build the horizontally scrollable favorite strip**

Replace the ordinary `固定宣教` row with `常用宣教` plus `更多宣教`, followed by a 48–52 px horizontal list of favorite buttons. Preserve the existing emergency fallback strip when `educationFallbackActive` is true. Disable unavailable language entries and show the explicit unavailable label.

- [ ] **Step 5: Open a starred item directly and auto-start**

Factor route setup so both the home direct path and workbench path create a session consistently. The home path calls `startSession`, `selectItem`, and opens `EducationPlaybackScreen(autoStart: true, nurseAvatarPath: controller.config.nurseAvatarPath, onOfflinePlaybackStarting: controller.suspendOnlineAudioForEducation, onOfflinePlaybackEnded: controller.resumeOnlineAudioAfterEducation)`.

- [ ] **Step 6: Pass the same avatar/audio callbacks into the full workbench**

Update `_openBedsideEducation` to construct `BedsideEducationScreen` with the avatar path and Task 1 audio callbacks. Rename the button copy from `开始床旁宣教` to `更多宣教`; update prior tests and the golden baseline only after visually confirming the intentional layout.

- [ ] **Step 7: Run all home, upgrade, and layout tests**

Run:

```bash
flutter test --no-pub test/features/education/education_upgrade_integration_test.dart test/widget_test.dart test/avatar_preview_test.dart
```

Expected: all tests pass with no overflow and the upgraded custom content remains present.

- [ ] **Step 8: Commit home shortcuts**

```bash
git add lib/controllers/nurse_controller.dart lib/screens/nurse_screen.dart test/features/education/education_upgrade_integration_test.dart test/widget_test.dart test/goldens/new_brand_layout_preview.png
git commit -m "feat: launch favorite education from home"
```

### Task 4: Full Verification and v0.15.1 APK Delivery

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_CHECKLIST.md` only if a newly discovered blocker must be recorded
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.1-星标直达与音频恢复版.apk`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.1-更新说明.md`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.1-SHA256校验值.txt`

**Interfaces:**
- Consumes: Tasks 1–3 and existing release signing configuration.
- Produces: signed universal APK version `0.15.1+18`, checksums, and installation notes.

- [ ] **Step 1: Bump version and document the changes**

Set `version: 0.15.1+18`. Add release notes for home favorites, digital nurse playback layout, and online audio recovery. Preserve the voice-model, portrait, and logo copyright blockers.

- [ ] **Step 2: Run fresh formatting, analysis, and full tests**

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze lib test
flutter test --no-pub
```

Expected: zero formatting changes, `No issues found!`, and every test passes.

- [ ] **Step 3: Build and verify the signed universal APK**

```bash
flutter build apk --release --no-pub
```

Verify package `com.digitalnurse.app`, version code `18`, version name `0.15.1`, minimum SDK `24`, target SDK `36`, v2 signature certificate SHA-256 `4baff6b7d01271a1bbc8627696540616c2223ca3dc02690d7e00f37214517c47`, and all three native ABIs.

- [ ] **Step 4: Copy deliverables and calculate SHA-256**

Place the APK, update notes, checksum, and refreshed private source backup under `/Users/jialeisi/Desktop/数字人/outputs`. Installation notes must say to install over v0.15.0/v0.14.1 without uninstalling.

- [ ] **Step 5: Commit release metadata**

```bash
git add pubspec.yaml README.md RELEASE_CHECKLIST.md
git commit -m "release: prepare favorite education flow v0.15.1"
```
