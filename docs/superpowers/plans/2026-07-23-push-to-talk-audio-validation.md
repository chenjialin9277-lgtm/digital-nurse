# v0.15.3 Push-to-Talk Audio Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android push-to-talk capture the tablet microphone reliably and prevent silent, truncated, or failed recordings from being submitted to Xiaozhi ASR.

**Architecture:** Keep the existing 16 kHz mono PCM → 60 ms Opus pipeline, but add a pure in-memory capture tracker at the microphone boundary. `PushToTalkAudioSession` will use the final capture result to choose `listen/stop` for valid speech or `abort` for invalid input, and the controller will show a retry message without entering a fatal error state.

**Tech Stack:** Flutter/Dart, `record` 5.2.1, `opus_dart`, `audio_session`, `flutter_test`, Android APK/Gradle.

## Global Constraints

- Android recording remains PCM 16-bit, 16 kHz, mono, encoded into 60 ms Opus frames.
- Android input source is `AndroidAudioSource.voiceRecognition`; automatic Bluetooth routing is disabled.
- A valid capture requires at least 5 encoded frames and at least 2 PCM frames whose peak amplitude is at least 256.
- Microphone startup and permission failures must propagate to the UI.
- Invalid audio sends `abort` and must not send `listen/stop`.
- No PCM, Opus, transcript, or user utterance is written to disk or logs.
- Release version is `0.15.3+20` and must install over v0.15.2 without clearing app data.

---

## File Structure

- Create `lib/services/microphone_capture_result.dart`: immutable capture result and mutable in-memory PCM statistics tracker.
- Modify `lib/utils/audio_util.dart`: Android recorder configuration, error propagation, capture tracking, and result-returning stop.
- Modify `lib/services/push_to_talk_audio_session.dart`: valid/invalid stop decision and abort callback.
- Modify `lib/services/xiaozhi_service.dart`: wire abort and return the session stop result.
- Modify `lib/controllers/nurse_controller.dart`: show retry messages for invalid or interrupted capture.
- Create `test/services/microphone_capture_result_test.dart`: pure capture-threshold tests.
- Modify `test/services/push_to_talk_audio_session_test.dart`: server command ordering and abort behavior.
- Modify `test/utils/audio_util_test.dart`: Android input-route configuration regression test.
- Modify `test/widget_test.dart`: controller state and retry-copy regression tests.
- Modify `pubspec.yaml`, `README.md`, and release artifacts under `/Users/jialeisi/Desktop/数字人/outputs` for v0.15.3.

---

### Task 1: In-Memory Capture Result and Android Recorder Configuration

**Files:**
- Create: `lib/services/microphone_capture_result.dart`
- Modify: `lib/utils/audio_util.dart:13-320`
- Create: `test/services/microphone_capture_result_test.dart`
- Modify: `test/utils/audio_util_test.dart`

**Interfaces:**
- Produces: `MicrophoneCaptureResult`, `MicrophoneCaptureTracker`, `AudioUtil.recordConfig`, and `Future<MicrophoneCaptureResult> AudioUtil.stopRecording()`.
- Consumes: `RecordConfig`, `AndroidRecordConfig`, and `AndroidAudioSource` from `record`.

- [ ] **Step 1: Write failing capture-threshold tests**

```dart
import 'dart:typed_data';

import 'package:digital_nurse/services/microphone_capture_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('five encoded frames with two voiced PCM frames are valid', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      final frame = Int16List(960);
      if (index < 2) frame[0] = 512;
      tracker.addPcmFrame(Uint8List.view(frame.buffer));
      tracker.markEncodedFrame();
    }

    expect(tracker.finish().hasValidSpeech, isTrue);
  });

  test('silent PCM is rejected even when frame count is sufficient', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      tracker.addPcmFrame(Uint8List(1920));
      tracker.markEncodedFrame();
    }

    expect(tracker.finish().hasValidSpeech, isFalse);
  });

  test('stream errors invalidate otherwise valid speech', () {
    final tracker = MicrophoneCaptureTracker();
    for (var index = 0; index < 5; index++) {
      final frame = Int16List(960)..[0] = 512;
      tracker.addPcmFrame(Uint8List.view(frame.buffer));
      tracker.markEncodedFrame();
    }
    tracker.markStreamError(StateError('stream stopped'));

    final result = tracker.finish();
    expect(result.hasValidSpeech, isFalse);
    expect(result.streamFailed, isTrue);
  });
}
```

- [ ] **Step 2: Run the capture tests and verify RED**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub test/services/microphone_capture_result_test.dart
```

Expected: compilation fails because `microphone_capture_result.dart` and its types do not exist.

- [ ] **Step 3: Implement the pure capture tracker**

```dart
import 'dart:typed_data';

class MicrophoneCaptureResult {
  const MicrophoneCaptureResult({
    required this.pcmByteCount,
    required this.encodedFrameCount,
    required this.voicedFrameCount,
    required this.peakAmplitude,
    required this.streamFailed,
  });

  static const int minimumEncodedFrames = 5;
  static const int minimumVoicedFrames = 2;
  static const int voicedPeakThreshold = 256;

  final int pcmByteCount;
  final int encodedFrameCount;
  final int voicedFrameCount;
  final int peakAmplitude;
  final bool streamFailed;

  bool get hasValidSpeech =>
      !streamFailed &&
      encodedFrameCount >= minimumEncodedFrames &&
      voicedFrameCount >= minimumVoicedFrames;
}

class MicrophoneCaptureTracker {
  int _pcmByteCount = 0;
  int _encodedFrameCount = 0;
  int _voicedFrameCount = 0;
  int _peakAmplitude = 0;
  bool _streamFailed = false;

  void addPcmFrame(Uint8List frame) {
    _pcmByteCount += frame.length;
    final samples = ByteData.sublistView(frame);
    var framePeak = 0;
    for (var offset = 0; offset + 1 < frame.length; offset += 2) {
      final sample = samples.getInt16(offset, Endian.little).abs();
      if (sample > framePeak) framePeak = sample;
    }
    if (framePeak > _peakAmplitude) _peakAmplitude = framePeak;
    if (framePeak >= MicrophoneCaptureResult.voicedPeakThreshold) {
      _voicedFrameCount++;
    }
  }

  void markEncodedFrame() => _encodedFrameCount++;
  void markStreamError(Object error) => _streamFailed = true;

  MicrophoneCaptureResult finish() => MicrophoneCaptureResult(
    pcmByteCount: _pcmByteCount,
    encodedFrameCount: _encodedFrameCount,
    voicedFrameCount: _voicedFrameCount,
    peakAmplitude: _peakAmplitude,
    streamFailed: _streamFailed,
  );
}
```

- [ ] **Step 4: Add a failing Android route regression test**

Add to `test/utils/audio_util_test.dart`:

```dart
test('push-to-talk uses the tablet voice-recognition microphone', () {
  expect(
    AudioUtil.recordConfig.androidConfig.audioSource,
    AndroidAudioSource.voiceRecognition,
  );
  expect(AudioUtil.recordConfig.androidConfig.manageBluetooth, isFalse);
  expect(AudioUtil.recordConfig.sampleRate, AudioUtil.SAMPLE_RATE);
  expect(AudioUtil.recordConfig.numChannels, AudioUtil.CHANNELS);
});
```

Expected RED: `AudioUtil.recordConfig` is not defined.

- [ ] **Step 5: Wire capture tracking and propagate recorder failures**

In `AudioUtil`, add the production configuration and tracker:

```dart
static const RecordConfig recordConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: SAMPLE_RATE,
  numChannels: CHANNELS,
  autoGain: true,
  echoCancel: false,
  noiseSuppress: false,
  androidConfig: AndroidRecordConfig(
    manageBluetooth: false,
    audioSource: AndroidAudioSource.voiceRecognition,
  ),
);

static MicrophoneCaptureTracker? _captureTracker;
```

Use `recordConfig` in `startStream`, create the tracker before starting, call `addPcmFrame(frame)` before Opus encoding, call `markEncodedFrame()` only after encoding succeeds, and call `markStreamError(error)` in `onError`. Permission denial and startup catch blocks must throw instead of returning or swallowing the exception.

Replace stop with this result-returning behavior:

```dart
static Future<MicrophoneCaptureResult> stopRecording() async {
  final tracker = _captureTracker ?? MicrophoneCaptureTracker();
  try {
    if (_isRecorderInitialized) await _audioRecorder.stop();
    await _recordingSubscription?.cancel();
    return tracker.finish();
  } catch (error) {
    tracker.markStreamError(error);
    return tracker.finish();
  } finally {
    _recordingSubscription = null;
    _pendingPcmBytes.clear();
    _captureTracker = null;
    _isRecording = false;
  }
}
```

- [ ] **Step 6: Run Task 1 tests and verify GREEN**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub test/services/microphone_capture_result_test.dart test/utils/audio_util_test.dart
```

Expected: all Task 1 tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add lib/services/microphone_capture_result.dart lib/utils/audio_util.dart test/services/microphone_capture_result_test.dart test/utils/audio_util_test.dart
git commit -m "fix: validate captured microphone audio"
```

---

### Task 2: Abort Invalid Push-to-Talk Sessions

**Files:**
- Modify: `lib/services/push_to_talk_audio_session.dart`
- Modify: `test/services/push_to_talk_audio_session_test.dart`

**Interfaces:**
- Consumes: `Future<MicrophoneCaptureResult> Function() stopMicrophone`.
- Produces: `PushToTalkStopResult`, `Future<PushToTalkStopResult> stop()`, and `void Function() sendAbort`.

- [ ] **Step 1: Replace the session test with valid, silent, and failed cases**

The valid case returns a result with `encodedFrameCount: 5`, `voicedFrameCount: 2`, and `streamFailed: false`, then expects `listen-stop` and no abort. Add an invalid case returning zero voiced frames and expect `listen-abort` with no `listen-stop`. Add a stream-failed case and expect `PushToTalkStopResult.recordingFailed`.

```dart
const validCapture = MicrophoneCaptureResult(
  pcmByteCount: 9600,
  encodedFrameCount: 5,
  voicedFrameCount: 2,
  peakAmplitude: 512,
  streamFailed: false,
);

const silentCapture = MicrophoneCaptureResult(
  pcmByteCount: 9600,
  encodedFrameCount: 5,
  voicedFrameCount: 0,
  peakAmplitude: 0,
  streamFailed: false,
);
```

Expected RED: constructor types, `sendAbort`, and `PushToTalkStopResult` do not exist.

- [ ] **Step 2: Run the session tests and verify RED**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub test/services/push_to_talk_audio_session_test.dart
```

Expected: compilation fails on the new stop result and callback signatures.

- [ ] **Step 3: Implement result-based stop behavior**

Add:

```dart
enum PushToTalkStopResult { submitted, noSpeech, recordingFailed }
```

Change the constructor fields to:

```dart
final Future<MicrophoneCaptureResult> Function() stopMicrophone;
final void Function() sendAbort;
```

Implement stop as:

```dart
Future<PushToTalkStopResult> stop() async {
  if (!_started && _microphoneSubscription == null) {
    return PushToTalkStopResult.noSpeech;
  }

  MicrophoneCaptureResult capture;
  try {
    capture =
        _started
            ? await stopMicrophone()
            : const MicrophoneCaptureResult(
              pcmByteCount: 0,
              encodedFrameCount: 0,
              voicedFrameCount: 0,
              peakAmplitude: 0,
              streamFailed: true,
            );
  } finally {
    _started = false;
    await _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
    await playback.resume();
  }

  if (capture.hasValidSpeech) {
    sendStop();
    return PushToTalkStopResult.submitted;
  }
  sendAbort();
  return capture.streamFailed
      ? PushToTalkStopResult.recordingFailed
      : PushToTalkStopResult.noSpeech;
}
```

The `start()` failure path must call `sendAbort()` instead of `sendStop()`.

- [ ] **Step 4: Run the session tests and verify GREEN**

Run the command from Step 2. Expected: all session tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/services/push_to_talk_audio_session.dart test/services/push_to_talk_audio_session_test.dart
git commit -m "fix: abort invalid push-to-talk sessions"
```

---

### Task 3: Surface Retry States Through Service and Controller

**Files:**
- Modify: `lib/services/xiaozhi_service.dart:735-815`
- Modify: `lib/controllers/nurse_controller.dart:408-478`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `PushToTalkStopResult` from Task 2 and `AudioUtil.stopRecording()` from Task 1.
- Produces: `Future<PushToTalkStopResult> XiaozhiService.stopListening()` and user-facing retry messages.

- [ ] **Step 1: Write controller failing tests**

Make `_BlockingPushToTalkService` return a configurable result:

```dart
PushToTalkStopResult stopResult = PushToTalkStopResult.submitted;

@override
Future<PushToTalkStopResult> stopListening() async {
  events.add('stop');
  return stopResult;
}
```

Add tests asserting:

```dart
online.stopResult = PushToTalkStopResult.noSpeech;
await controller.startPushToTalk();
await controller.stopPushToTalk();
expect(controller.state, NurseUiState.idle);
expect(controller.errorMessage, '未检测到语音，请重试');
expect(controller.userText, isEmpty);
```

and:

```dart
online.stopResult = PushToTalkStopResult.recordingFailed;
await controller.startPushToTalk();
await controller.stopPushToTalk();
expect(controller.state, NurseUiState.idle);
expect(controller.errorMessage, '录音中断，请重试');
```

Expected RED: service and controller still use `Future<void>` and always enter `thinking`.

- [ ] **Step 2: Run focused widget tests and verify RED**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub test/widget_test.dart --plain-name "语音"
```

Expected: the new retry-state assertions fail.

- [ ] **Step 3: Wire abort and stop results in XiaozhiService**

Pass `AudioUtil.stopRecording` directly to the session. Add `sendAbort` that sends:

```dart
final message = {
  'session_id': _sessionId,
  'type': 'abort',
  'reason': 'no_speech',
};
_webSocketManager?.sendMessage(jsonEncode(message));
```

Return the session result without swallowing it:

```dart
Future<PushToTalkStopResult> stopListening() async {
  final session = _pushToTalkSession;
  _pushToTalkSession = null;
  if (session == null) return PushToTalkStopResult.noSpeech;
  return session.stop();
}
```

- [ ] **Step 4: Map stop results to UI states**

Replace the active-session branch in `stopPushToTalk()` with:

```dart
final result = await _service!.stopListening();
switch (result) {
  case PushToTalkStopResult.submitted:
    state = NurseUiState.thinking;
  case PushToTalkStopResult.noSpeech:
    state = NurseUiState.idle;
    errorMessage = '未检测到语音，请重试';
  case PushToTalkStopResult.recordingFailed:
    state = NurseUiState.idle;
    errorMessage = '录音中断，请重试';
}
```

Import `push_to_talk_audio_session.dart` in the controller and keep `userText` empty for invalid sessions.

- [ ] **Step 5: Run focused service/controller tests and verify GREEN**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub test/services/push_to_talk_audio_session_test.dart test/widget_test.dart
```

Expected: all targeted tests pass, including the existing start/stop race regression.

- [ ] **Step 6: Commit Task 3**

```bash
git add lib/services/xiaozhi_service.dart lib/controllers/nurse_controller.dart test/widget_test.dart
git commit -m "fix: show retry state for invalid speech"
```

---

### Task 4: Full Verification and v0.15.3 Test Release

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-按住说话有效音频修复版-更新说明.md`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-SHA256校验值.txt`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-按住说话有效音频修复版.apk`
- Create: `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-私有源码与发布材料备份.tar.gz`

**Interfaces:**
- Consumes: all passing behavior from Tasks 1-3.
- Produces: signed, installable v0.15.3 test APK and reproducible release checksums.

- [ ] **Step 1: Update version and release notes**

Set `pubspec.yaml` to:

```yaml
version: 0.15.3+20
```

Add a README v0.15.3 section documenting Android internal-microphone routing, explicit capture errors, silence rejection, and direct upgrade from v0.15.2.

- [ ] **Step 2: Run formatter, static analysis, and full tests**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/dart format lib/services/microphone_capture_result.dart lib/services/push_to_talk_audio_session.dart lib/services/xiaozhi_service.dart lib/controllers/nurse_controller.dart lib/utils/audio_util.dart test/services/microphone_capture_result_test.dart test/services/push_to_talk_audio_session_test.dart test/utils/audio_util_test.dart test/widget_test.dart
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/dart analyze lib test
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter test --no-pub
```

Expected: formatter completes, analysis reports `No issues found!`, and all tests pass.

- [ ] **Step 3: Build the release APK**

Run:

```bash
/Users/jialeisi/Desktop/数字人/work/toolchains/flutter/bin/flutter build apk --release --no-pub
```

Copy `build/app/outputs/flutter-apk/app-release.apk` to `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-按住说话有效音频修复版.apk`.

- [ ] **Step 4: Verify package metadata, signing, ABI, and checksum**

Use Android `aapt`, `apksigner`, `unzip`, and `shasum -a 256` to verify:

- package name `com.digitalnurse.app`;
- version code `20` and version name `0.15.3`;
- minimum SDK 24 and target SDK 36;
- v2 signature verifies and certificate matches v0.15.2;
- ABIs include `arm64-v8a`, `armeabi-v7a`, and `x86_64`;
- SHA-256 values are written to the checksum file.

- [ ] **Step 5: Build the private backup without publishing secrets**

Create `/Users/jialeisi/Desktop/数字人/outputs/数字护士-v0.15.3-私有源码与发布材料备份.tar.gz` from the project source and required private release material, excluding `build`, `.dart_tool`, transient logs, and previously generated archives. Record its SHA-256 in the checksum file. Do not upload or expose signing credentials.

- [ ] **Step 6: Commit release metadata**

```bash
git add pubspec.yaml README.md
git commit -m "release: prepare push-to-talk audio validation v0.15.3"
```

- [ ] **Step 7: Hand off the test build**

Report the APK path, SHA-256, signing verification, supported ABIs, and three acceptance checks: different spoken sentences no longer all become “我”, silence shows the retry message, and direct upgrade preserves existing data.
