import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../models/offline_speech_language.dart';
import '../data/education_event_repository.dart';
import '../models/comprehension_result.dart';
import '../models/education_item.dart';
import '../models/education_session_event.dart';

enum EducationSessionStage {
  idle,
  selecting,
  ready,
  playing,
  question,
  feedback,
}

class EducationSessionState {
  const EducationSessionState({
    this.stage = EducationSessionStage.idle,
    this.sessionId,
    this.language = OfflineSpeechLanguage.mandarin,
    this.selectedItem,
    this.visibleCaption = '',
    this.result,
    this.feedbackTitle = '',
    this.nurseHelpRequested = false,
    this.attempt = 0,
  });

  final EducationSessionStage stage;
  final String? sessionId;
  final OfflineSpeechLanguage language;
  final EducationItem? selectedItem;
  final String visibleCaption;
  final ComprehensionResult? result;
  final String feedbackTitle;
  final bool nurseHelpRequested;
  final int attempt;
}

class EducationSessionController extends ChangeNotifier {
  EducationSessionController({
    required this.events,
    required this.departmentId,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? _secureId;

  final EducationEventRepository events;
  final String departmentId;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  EducationSessionState _state = const EducationSessionState();
  EducationSessionState get state => _state;
  Object? _lastPersistenceError;
  Object? get lastPersistenceError => _lastPersistenceError;

  Future<void> startSession(OfflineSpeechLanguage language) async {
    if (_state.sessionId != null) await clearTransientState();
    _lastPersistenceError = null;
    _state = EducationSessionState(
      stage: EducationSessionStage.selecting,
      sessionId: _idGenerator(),
      language: language,
    );
    notifyListeners();
    await _save(EducationEventType.sessionStarted);
  }

  Future<void> selectItem(EducationItem item) async {
    _requireSession();
    _requireStage(const {
      EducationSessionStage.selecting,
      EducationSessionStage.ready,
      EducationSessionStage.question,
      EducationSessionStage.feedback,
    }, '当前阶段不能更换宣教项目');
    if (!item.isAvailableIn(_state.language)) {
      throw StateError('所选宣教暂不支持当前语言');
    }
    _state = EducationSessionState(
      stage: EducationSessionStage.ready,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
    );
    notifyListeners();
    await _save(EducationEventType.itemSelected);
  }

  Future<void> beginPlayback() async {
    final item = _requireItem();
    _requireStage(const {EducationSessionStage.ready}, '当前阶段不能开始播报');
    final readyState = _state;
    await _save(EducationEventType.playbackStarted);
    if (!identical(_state, readyState)) return;
    _state = EducationSessionState(
      stage: EducationSessionStage.playing,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      visibleCaption: '',
      attempt: _state.attempt,
    );
    notifyListeners();
  }

  void updateVisibleCaption(String caption) {
    final item = _requireItem();
    _requireStage(const {EducationSessionStage.playing}, '只有播报期间可以更新字幕');
    _state = EducationSessionState(
      stage: _state.stage,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      visibleCaption: caption,
      attempt: _state.attempt,
    );
    notifyListeners();
  }

  Future<void> markSpeechComplete() async {
    final item = _requireItem();
    _requireStage(const {EducationSessionStage.playing}, '尚未开始播报，不能标记播报完成');
    _state = EducationSessionState(
      stage: EducationSessionStage.question,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      visibleCaption: _state.visibleCaption,
      attempt: _state.attempt,
    );
    notifyListeners();
    await _save(EducationEventType.playbackCompleted);
  }

  Future<void> submitAnswer(int selectedIndex) async {
    final item = _requireItem();
    if (_state.stage != EducationSessionStage.question) {
      throw StateError('请在宣教播报完成后再提交理解题');
    }
    final content = item.contentFor(_state.language);
    if (selectedIndex < 0 || selectedIndex >= content.options.length) {
      throw RangeError.index(selectedIndex, content.options, 'selectedIndex');
    }
    final attempt = _state.attempt + 1;
    final result = ComprehensionResult(
      itemId: item.id,
      itemVersion: item.version,
      language: _state.language,
      selectedIndex: selectedIndex,
      correctIndex: content.correctIndex,
      attempt: attempt,
    );
    _state = EducationSessionState(
      stage: EducationSessionStage.feedback,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      visibleCaption: _state.visibleCaption,
      result: result,
      feedbackTitle: result.isCorrect ? '本次理解确认完成' : '我们再看一下重点',
      attempt: attempt,
    );
    notifyListeners();
    await _save(
      EducationEventType.answer,
      attempt: attempt,
      value: result.isCorrect ? 1 : 0,
    );
  }

  Future<void> replay() async {
    final item = _requireItem();
    _requireStage(const {
      EducationSessionStage.question,
      EducationSessionStage.feedback,
    }, '当前阶段不能重新播放');
    _state = EducationSessionState(
      stage: EducationSessionStage.ready,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      attempt: _state.attempt,
    );
    notifyListeners();
    await _save(EducationEventType.replay, attempt: _state.attempt);
  }

  Future<void> requestNurseHelp() async {
    final item = _requireItem();
    _state = EducationSessionState(
      stage: EducationSessionStage.feedback,
      sessionId: _state.sessionId,
      language: _state.language,
      selectedItem: item,
      visibleCaption: _state.visibleCaption,
      result: _state.result,
      feedbackTitle: '请护士进一步解释',
      nurseHelpRequested: true,
      attempt: _state.attempt,
    );
    notifyListeners();
    await _save(EducationEventType.nurseHelp, attempt: _state.attempt);
  }

  Future<void> finishSession() async {
    if (_state.sessionId == null) return;
    final event = _buildEvent(EducationEventType.sessionCompleted);
    _state = const EducationSessionState();
    notifyListeners();
    await _saveAfterClear(event);
  }

  Future<void> clearTransientState() async {
    final event = _buildEvent(EducationEventType.sessionCleared);
    _state = const EducationSessionState();
    notifyListeners();
    await _saveAfterClear(event);
  }

  Future<void> _save(
    EducationEventType type, {
    int? attempt,
    int? value,
  }) async {
    final event = _buildEvent(type, attempt: attempt, value: value);
    if (event != null) await events.save(event);
  }

  EducationSessionEvent? _buildEvent(
    EducationEventType type, {
    int? attempt,
    int? value,
  }) {
    final sessionId = _state.sessionId;
    if (sessionId == null) return null;
    final item = _state.selectedItem;
    return EducationSessionEvent(
      id: _idGenerator(),
      sessionId: sessionId,
      departmentId: departmentId,
      itemId: item?.id,
      itemVersion: item?.version,
      language: _state.language,
      type: type,
      attempt: attempt,
      value: value,
      occurredAt: _clock().toUtc(),
    );
  }

  Future<void> _saveAfterClear(EducationSessionEvent? event) async {
    if (event == null) return;
    try {
      await events.save(event);
      _lastPersistenceError = null;
    } catch (error) {
      _lastPersistenceError = error;
    }
  }

  void _requireSession() {
    if (_state.sessionId == null) throw StateError('床旁宣教尚未开始');
  }

  EducationItem _requireItem() {
    _requireSession();
    final item = _state.selectedItem;
    if (item == null) throw StateError('尚未选择宣教项目');
    return item;
  }

  void _requireStage(Set<EducationSessionStage> allowed, String message) {
    if (!allowed.contains(_state.stage)) throw StateError(message);
  }

  static String _secureId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
