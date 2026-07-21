import 'dart:async';

import 'package:flutter/material.dart';

import '../../../controllers/nurse_controller.dart';
import '../../../models/offline_speech_language.dart';
import '../../../services/local_speech_service.dart';
import '../../../theme/nurse_theme.dart';
import '../../../widgets/nurse_avatar.dart';
import '../controllers/education_session_controller.dart';
import '../models/education_language_content.dart';
import '../widgets/comprehension_card.dart';
import '../widgets/daily_language_selector.dart';
import '../widgets/education_feedback_card.dart';

class EducationPlaybackScreen extends StatefulWidget {
  const EducationPlaybackScreen({
    super.key,
    required this.session,
    required this.speech,
    required this.departmentName,
    this.nurseAvatarPath = '',
    this.autoStart = false,
    this.onOfflinePlaybackStarting,
    this.onOfflinePlaybackEnded,
    this.onLanguageChanged,
    this.inactivityDuration = const Duration(minutes: 5),
    this.warningDuration = const Duration(seconds: 30),
  });

  final EducationSessionController session;
  final LocalSpeechService speech;
  final String departmentName;
  final String nurseAvatarPath;
  final bool autoStart;
  final Future<void> Function()? onOfflinePlaybackStarting;
  final Future<void> Function()? onOfflinePlaybackEnded;
  final ValueChanged<OfflineSpeechLanguage>? onLanguageChanged;
  final Duration inactivityDuration;
  final Duration warningDuration;

  @override
  State<EducationPlaybackScreen> createState() =>
      _EducationPlaybackScreenState();
}

class _EducationPlaybackScreenState extends State<EducationPlaybackScreen>
    with WidgetsBindingObserver {
  StreamSubscription<LocalSpeechEvent>? _speechSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  Timer? _captionTimer;
  Timer? _warningTimer;
  Timer? _inactivityTimer;
  List<int> _captionRunes = const [];
  int _visibleRuneCount = 0;
  Duration _captionInterval = const Duration(milliseconds: 120);
  bool _finished = false;
  bool _changingLanguage = false;
  bool _showInactivityWarning = false;
  int _operationGeneration = 0;
  bool _replaying = false;
  bool _startingPlayback = false;
  String? _playbackStartError;
  bool _offlinePlaybackActive = false;
  Future<void>? _suspendFuture;
  Future<void>? _restoreFuture;
  Future<void>? _stopAndRestoreFuture;
  final ScrollController _captionScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    _speechSubscription = widget.speech.events.listen(_handleSpeechEvent);
    _durationSubscription = widget.speech.playbackDurations.listen(
      _handlePlaybackDuration,
    );
    _resetInactivityTimer();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startPlayback());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_clearForPrivacy());
    }
  }

  @override
  void dispose() {
    _operationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    _speechSubscription?.cancel();
    _durationSubscription?.cancel();
    _captionScrollController.dispose();
    _cancelTimers();
    if (!_finished) {
      unawaited(widget.session.clearTransientState());
      unawaited(_stopOfflinePlaybackAndRestore());
    } else if (_stopAndRestoreFuture == null) {
      unawaited(_restoreOnlineAudio());
    }
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.session.state;
    final item = state.selectedItem;
    final palette = NursePalette.of(context);
    if (_finished || item == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined, size: 54),
              const SizedBox(height: 14),
              const Text(
                '本次宣教已结束',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回宣教列表'),
              ),
            ],
          ),
        ),
      );
    }

    final content = item.contentFor(state.language);
    final playing = state.stage == EducationSessionStage.playing;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_clearForPrivacy());
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _resetInactivityTimer(),
          child: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.backgroundStart, palette.backgroundEnd],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlaybackHeader(
                      departmentName: widget.departmentName,
                      language: state.language,
                      languageEnabled: !playing && !_changingLanguage,
                      changingLanguage: _changingLanguage,
                      onBack: _finishAndClose,
                      onLanguageChanged: _changeLanguage,
                    ),
                    if (_showInactivityWarning) ...[
                      const SizedBox(height: 8),
                      MaterialBanner(
                        content: const Text('长时间无操作，本次宣教即将自动结束并清屏。'),
                        leading: const Icon(Icons.timer_outlined),
                        actions: [
                          TextButton(
                            onPressed: _resetInactivityTimer,
                            child: const Text('继续使用'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              constraints.maxWidth < 1200 ||
                              constraints.maxHeight < 720;
                          final introduction = _EducationIntroduction(
                            title: content.title,
                            summary: content.summary,
                            category: item.category,
                            minutes: item.estimatedManualMinutes,
                            visibleCaption: state.visibleCaption,
                            playing: playing,
                            scrollController: _captionScrollController,
                            onStart: _startPlayback,
                            compact: compact,
                            startError: _playbackStartError,
                          );
                          final stage = switch (state.stage) {
                            EducationSessionStage.ready ||
                            EducationSessionStage.playing => introduction,
                            _ => _buildStage(state, content),
                          };
                          return Row(
                            children: [
                              Expanded(
                                flex: 8,
                                child: _NurseStageCard(
                                  state:
                                      playing
                                          ? NurseUiState.speaking
                                          : NurseUiState.idle,
                                  imagePath: widget.nurseAvatarPath,
                                  departmentName: widget.departmentName,
                                  compact: compact,
                                ),
                              ),
                              SizedBox(width: compact ? 10 : 16),
                              Expanded(flex: 12, child: stage),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(
    EducationSessionState state,
    EducationLanguageContent content,
  ) {
    return switch (state.stage) {
      EducationSessionStage.ready ||
      EducationSessionStage.playing => const SizedBox.shrink(),
      EducationSessionStage.question => ComprehensionCard(
        content: content,
        onAnswer: (index) {
          _resetInactivityTimer();
          unawaited(widget.session.submitAnswer(index));
        },
        onReplay: () => unawaited(_replay()),
        onNurseHelp: () => unawaited(_requestNurseHelp()),
      ),
      EducationSessionStage.feedback => EducationFeedbackCard(
        title: state.feedbackTitle,
        content: content,
        isCorrect: state.result?.isCorrect ?? false,
        nurseHelpRequested: state.nurseHelpRequested,
        onReplay: () => unawaited(_replay()),
        onNurseHelp: () => unawaited(_requestNurseHelp()),
        onFinish: () => unawaited(_finishAndClose()),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Future<void> _startPlayback() async {
    if (_startingPlayback ||
        _finished ||
        widget.session.state.stage != EducationSessionStage.ready) {
      return;
    }
    _startingPlayback = true;
    if (_playbackStartError != null && mounted) {
      setState(() => _playbackStartError = null);
    }
    _resetInactivityTimer();
    final state = widget.session.state;
    final body = state.selectedItem!.contentFor(state.language).body;
    _captionRunes = body.runes.toList(growable: false);
    _visibleRuneCount = 0;
    try {
      await widget.session.beginPlayback();
    } catch (_) {
      if (!_finished && mounted) {
        setState(() {
          _playbackStartError = '使用记录保存失败，宣教未开始，请重试';
        });
      }
      return;
    } finally {
      _startingPlayback = false;
    }
    if (_finished ||
        !mounted ||
        widget.session.state.stage != EducationSessionStage.playing) {
      return;
    }
    var speechStarted = false;
    try {
      await _suspendOnlineAudio();
      if (_finished ||
          !mounted ||
          widget.session.state.stage != EducationSessionStage.playing) {
        return;
      }
      await widget.speech.speak(body, language: state.language);
      speechStarted = true;
    } catch (_) {
      if (widget.session.state.stage == EducationSessionStage.playing) {
        widget.session.updateVisibleCaption(body);
        await widget.session.markSpeechComplete();
      }
    } finally {
      if (!speechStarted) await _restoreOnlineAudio();
    }
  }

  void _handleSpeechEvent(LocalSpeechEvent event) {
    if (_finished ||
        widget.session.state.stage != EducationSessionStage.playing) {
      return;
    }
    if (event == LocalSpeechEvent.started) {
      _captionTimer?.cancel();
      _captionTimer = Timer.periodic(
        _captionInterval,
        (_) => _revealNextRune(),
      );
      return;
    }
    if (event == LocalSpeechEvent.completed ||
        event == LocalSpeechEvent.error) {
      unawaited(_completePlayback());
    }
  }

  void _handlePlaybackDuration(Duration duration) {
    if (_captionRunes.isEmpty) return;
    final milliseconds = (duration.inMilliseconds / _captionRunes.length)
        .round()
        .clamp(25, 1200);
    _captionInterval = Duration(milliseconds: milliseconds);
  }

  void _revealNextRune() {
    if (widget.session.state.stage != EducationSessionStage.playing) {
      _captionTimer?.cancel();
      return;
    }
    if (_visibleRuneCount >= _captionRunes.length) {
      _captionTimer?.cancel();
      return;
    }
    _visibleRuneCount++;
    widget.session.updateVisibleCaption(
      String.fromCharCodes(_captionRunes.take(_visibleRuneCount)),
    );
    _followCaption();
  }

  Future<void> _completePlayback() async {
    _captionTimer?.cancel();
    try {
      if (widget.session.state.stage != EducationSessionStage.playing) return;
      final state = widget.session.state;
      final body = state.selectedItem!.contentFor(state.language).body;
      widget.session.updateVisibleCaption(body);
      _followCaption();
      await widget.session.markSpeechComplete();
      _resetInactivityTimer();
    } finally {
      await _restoreOnlineAudio();
    }
  }

  Future<void> _replay() async {
    if (_replaying || _finished) return;
    _replaying = true;
    _resetInactivityTimer();
    try {
      await widget.speech.stop();
      await widget.session.replay();
      await _startPlayback();
    } finally {
      _replaying = false;
    }
  }

  Future<void> _requestNurseHelp() async {
    _resetInactivityTimer();
    await widget.speech.stop();
    await widget.session.requestNurseHelp();
  }

  Future<void> _changeLanguage(OfflineSpeechLanguage language) async {
    if (_changingLanguage ||
        widget.session.state.stage == EducationSessionStage.playing ||
        language == widget.session.state.language) {
      return;
    }
    final item = widget.session.state.selectedItem;
    if (item == null || !item.isAvailableIn(language)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该语言暂未提供')));
      return;
    }
    final generation = ++_operationGeneration;
    setState(() => _changingLanguage = true);
    _resetInactivityTimer();
    await widget.speech.stop();
    if (_finished || !mounted || generation != _operationGeneration) return;
    await widget.session.clearTransientState();
    if (_finished || !mounted || generation != _operationGeneration) return;
    await widget.session.startSession(language);
    if (_finished || !mounted || generation != _operationGeneration) {
      await widget.session.clearTransientState();
      return;
    }
    await widget.session.selectItem(item);
    if (_finished || !mounted || generation != _operationGeneration) {
      await widget.session.clearTransientState();
      return;
    }
    widget.onLanguageChanged?.call(language);
    if (mounted) setState(() => _changingLanguage = false);
  }

  void _resetInactivityTimer() {
    _warningTimer?.cancel();
    _inactivityTimer?.cancel();
    if (mounted && _showInactivityWarning) {
      setState(() => _showInactivityWarning = false);
    }
    final warningDelay = widget.inactivityDuration - widget.warningDuration;
    _warningTimer = Timer(
      warningDelay.isNegative ? Duration.zero : warningDelay,
      () {
        if (mounted && !_finished) {
          setState(() => _showInactivityWarning = true);
        }
      },
    );
    _inactivityTimer = Timer(widget.inactivityDuration, () {
      unawaited(_finish(clearOnly: true));
    });
  }

  Future<void> _finishAndClose() async {
    await _finish(clearOnly: false);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _finish({required bool clearOnly}) async {
    if (_finished) return;
    _finished = true;
    _operationGeneration++;
    _cancelTimers();
    final clearFuture =
        clearOnly
            ? widget.session.clearTransientState()
            : widget.session.finishSession();
    await Future.wait([clearFuture, _stopOfflinePlaybackAndRestore()]);
    if (mounted) setState(() {});
  }

  Future<void> _clearForPrivacy() async {
    if (_finished) return;
    _finished = true;
    _operationGeneration++;
    _cancelTimers();
    final clearFuture = widget.session.clearTransientState();
    await Future.wait([clearFuture, _stopOfflinePlaybackAndRestore()]);
    if (mounted) setState(() {});
  }

  void _cancelTimers() {
    _captionTimer?.cancel();
    _warningTimer?.cancel();
    _inactivityTimer?.cancel();
  }

  void _followCaption() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_captionScrollController.hasClients) return;
      _captionScrollController.jumpTo(
        _captionScrollController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _suspendOnlineAudio() async {
    await _restoreFuture;
    if (_offlinePlaybackActive) return;
    final existing = _suspendFuture;
    if (existing != null) return existing;
    _offlinePlaybackActive = true;
    final future = () async {
      try {
        await widget.onOfflinePlaybackStarting?.call();
      } catch (_) {
        _offlinePlaybackActive = false;
        rethrow;
      }
    }();
    _suspendFuture = future;
    try {
      await future;
    } finally {
      if (identical(_suspendFuture, future)) _suspendFuture = null;
    }
  }

  Future<void> _stopOfflinePlaybackAndRestore() {
    final existing = _stopAndRestoreFuture;
    if (existing != null) return existing;
    final future = () async {
      try {
        await widget.speech.stop();
      } catch (_) {
        // A failed stop must not prevent the online player restore attempt.
      } finally {
        await _performOnlineAudioRestore();
      }
    }();
    _stopAndRestoreFuture = future;
    future.whenComplete(() {
      if (identical(_stopAndRestoreFuture, future)) {
        _stopAndRestoreFuture = null;
      }
    });
    return future;
  }

  Future<void> _restoreOnlineAudio() async {
    final stopping = _stopAndRestoreFuture;
    if (stopping != null) {
      await stopping;
      return;
    }
    await _performOnlineAudioRestore();
  }

  Future<void> _performOnlineAudioRestore() {
    final existing = _restoreFuture;
    if (existing != null) return existing;
    final future = () async {
      final suspending = _suspendFuture;
      if (suspending != null) {
        try {
          await suspending;
        } catch (_) {
          return;
        }
      }
      if (!_offlinePlaybackActive) return;
      try {
        await widget.onOfflinePlaybackEnded?.call();
        _offlinePlaybackActive = false;
      } catch (_) {
        // Restoring online playback must never prevent privacy clearing.
      }
    }();
    _restoreFuture = future;
    future.whenComplete(() {
      if (identical(_restoreFuture, future)) _restoreFuture = null;
    });
    return future;
  }
}

class _NurseStageCard extends StatelessWidget {
  const _NurseStageCard({
    required this.state,
    required this.imagePath,
    required this.departmentName,
    required this.compact,
  });

  final NurseUiState state;
  final String imagePath;
  final String departmentName;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: EdgeInsets.all(compact ? 6 : 10),
      child: NurseAvatar(
        state: state,
        emotion: 'neutral',
        imagePath: imagePath,
        departmentName: departmentName,
        motionEnabled: false,
      ),
    ),
  );
}

class _PlaybackHeader extends StatelessWidget {
  const _PlaybackHeader({
    required this.departmentName,
    required this.language,
    required this.languageEnabled,
    required this.changingLanguage,
    required this.onBack,
    required this.onLanguageChanged,
  });

  final String departmentName;
  final OfflineSpeechLanguage language;
  final bool languageEnabled;
  final bool changingLanguage;
  final VoidCallback onBack;
  final ValueChanged<OfflineSpeechLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: '结束并返回',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$departmentName·床旁宣教',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text('AI 辅助宣教 · 请以医护人员指导为准'),
            ],
          ),
        ),
        if (changingLanguage)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        DailyLanguageSelector(
          value: language,
          enabled: languageEnabled,
          compact: true,
          onChanged: onLanguageChanged,
        ),
      ],
    );
  }
}

class _EducationIntroduction extends StatelessWidget {
  const _EducationIntroduction({
    required this.title,
    required this.summary,
    required this.category,
    required this.minutes,
    required this.visibleCaption,
    required this.playing,
    required this.scrollController,
    required this.onStart,
    required this.compact,
    required this.startError,
  });

  final String title;
  final String summary;
  final String category;
  final int minutes;
  final String visibleCaption;
  final bool playing;
  final ScrollController scrollController;
  final VoidCallback onStart;
  final bool compact;
  final String? startError;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 21 : 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text('$category · 护士人工宣教约 $minutes 分钟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '要点：$summary',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (startError != null) ...[
              SizedBox(height: compact ? 8 : 12),
              Text(
                startError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: SingleChildScrollView(
                  key: const Key('education-caption-scroll'),
                  controller: scrollController,
                  child: Text(
                    visibleCaption.isEmpty
                        ? playing
                            ? '语音即将开始，字幕会跟随语音出现…'
                            : '点击“开始播放”后，语音和字幕将同步进行。'
                        : visibleCaption,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (!playing) ...[
              SizedBox(height: compact ? 8 : 12),
              const Text(
                '开始宣教',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始播放'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
