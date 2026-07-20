import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../features/education/controllers/education_session_controller.dart';
import '../features/education/data/education_event_repository.dart';
import '../features/education/data/education_repository.dart';
import '../features/education/data/legacy_education_migrator.dart';
import '../features/education/data/native_education_event_repository.dart';
import '../features/education/data/native_education_repository.dart';
import '../features/education/models/education_item.dart';
import '../models/nurse_app_config.dart';
import '../models/offline_speech_language.dart';
import '../models/app_usage_record.dart';
import '../repositories/app_usage_repository.dart';
import '../repositories/nurse_config_repository.dart';
import '../services/local_speech_service.dart';
import '../services/xiaozhi_service.dart';
import '../services/xiaozhi_provisioning_service.dart';
import '../services/network_monitor.dart';

enum NurseUiState {
  setupRequired,
  activationRequired,
  connecting,
  idle,
  listening,
  thinking,
  speaking,
  reconnecting,
  warning,
  offline,
  error,
}

class NurseController extends ChangeNotifier with WidgetsBindingObserver {
  NurseController({
    NurseConfigRepository? repository,
    AppUsageRepository? usageRepository,
    XiaozhiProvisioningService? provisioningService,
    LocalSpeechService? localSpeechService,
    XiaozhiService? xiaozhiService,
    EducationRepository? educationRepository,
    EducationEventRepository? educationEventRepository,
  }) : _repository = repository ?? NurseConfigRepository(),
       _usageRepository = usageRepository ?? AppUsageRepository(),
       _provisioningService =
           provisioningService ?? const XiaozhiProvisioningService(),
       _localSpeech = localSpeechService ?? const LocalSpeechService(),
       _service = xiaozhiService,
       _educationRepository =
           educationRepository ?? NativeEducationRepository(),
       _educationEventRepository =
           educationEventRepository ?? NativeEducationEventRepository();

  final NurseConfigRepository _repository;
  final AppUsageRepository _usageRepository;
  final XiaozhiProvisioningService _provisioningService;
  final LocalSpeechService _localSpeech;
  final EducationRepository _educationRepository;
  final EducationEventRepository _educationEventRepository;
  Future<void>? _educationInitialization;
  Future<void>? _localStateInitialization;
  Future<void>? _remoteInitialization;
  bool _lifecycleInstalled = false;
  XiaozhiService? _service;
  Timer? _activationTimer;
  Timer? _captionTimer;
  Timer? _localCaptionFallbackTimer;
  StreamSubscription<bool>? _networkSubscription;
  StreamSubscription<LocalSpeechEvent>? _localSpeechSubscription;
  bool _checkingActivation = false;
  bool _hasReadySession = false;
  bool _networkAvailable = true;
  bool _playingLocalAnswer = false;
  NurseUiState _stateBeforeLocalAnswer = NurseUiState.idle;
  int _networkErrorCount = 0;
  final List<int> _captionTarget = [];
  int _captionVisibleCount = 0;
  int _currentSentenceEnd = 0;
  NurseAppConfig config = NurseAppConfig.defaults('', '');

  NurseUiState state = NurseUiState.connecting;
  String userText = '';
  String assistantText = '您好，我是广州中医药大学第三附属医院急诊病房数字护士。您可以向我询问入院、检查和出院注意事项。';
  String emotion = 'neutral';
  String? errorMessage;
  String? activationCode;
  String? activationMessage;
  String? educationInitializationError;
  bool isPressingToTalk = false;

  bool get educationFallbackActive => educationInitializationError != null;

  Future<void> initializeLocalState() {
    final existing = _localStateInitialization;
    if (existing != null) return existing;
    final initialization = _initializeLocalState();
    _localStateInitialization = initialization;
    return initialization;
  }

  Future<void> _initializeLocalState() async {
    if (!_lifecycleInstalled) {
      WidgetsBinding.instance.addObserver(this);
      _networkSubscription = const NetworkMonitor().changes.listen(
        _handleNetworkAvailability,
        onError: (_) {
          // The platform signal is an optimization. WebSocket ping/reconnect
          // remains the source of truth if the signal is unavailable.
        },
      );
      _localSpeechSubscription = _localSpeech.events.listen(
        _handleLocalSpeechEvent,
        onError: (_) {},
      );
      _lifecycleInstalled = true;
    }
    try {
      config = await _repository.load();
    } catch (error) {
      educationInitializationError = '本地配置读取失败：$error';
      state = NurseUiState.setupRequired;
      assistantText = '本地配置暂时无法读取，已启用应急宣教。请联系管理员检查。';
      notifyListeners();
      return;
    }
    try {
      await _ensureEducationInitialized();
      educationInitializationError = null;
    } catch (error) {
      // 宣教库异常不阻断小智问答，首页保留旧版固定宣教作为应急入口。
      educationInitializationError = '宣教库初始化失败：$error';
    }
    if (!config.departmentConfigured) {
      state = NurseUiState.setupRequired;
      assistantText = '首次使用请先设置科室名称和科室Logo，再绑定本科室的小智AI账号。';
      notifyListeners();
      return;
    }
    // Copy and initialize the last selected offline model in the background so
    // the first fixed-education tap can begin speaking with minimal delay.
    unawaited(
      _localSpeech.prepare(config.offlineSpeechLanguage).catchError((_) {}),
    );
    state = NurseUiState.connecting;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    await initializeLocalState();
    final existing = _remoteInitialization;
    if (existing != null) return existing;
    final initialization = _initializeRemoteState();
    _remoteInitialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _remoteInitialization = null;
      rethrow;
    }
  }

  Future<void> _initializeRemoteState() async {
    if (!config.departmentConfigured) return;
    if (config.officialPlatform) {
      await provisionOfficialPlatform();
    } else if (config.canConnect) {
      await connect();
    } else {
      state = NurseUiState.setupRequired;
      notifyListeners();
    }
  }

  Future<List<EducationItem>> loadActiveEducation() async {
    try {
      await _ensureEducationInitialized();
      educationInitializationError = null;
    } catch (error) {
      educationInitializationError = '宣教库加载失败：$error';
      notifyListeners();
      rethrow;
    }
    return _educationRepository.loadActive();
  }

  EducationSessionController createBedsideEducationSession() =>
      EducationSessionController(
        events: _educationEventRepository,
        departmentId: config.wardName,
      );

  Future<void> _ensureEducationInitialized() {
    final existing = _educationInitialization;
    if (existing != null) return existing;
    final initialization = LegacyEducationMigrator(
      repository: _educationRepository,
    ).migrateIfNeeded(config);
    _educationInitialization = initialization;
    return initialization.catchError((Object error) {
      _educationInitialization = null;
      throw error;
    });
  }

  void _handleNetworkAvailability(bool available) {
    final wasAvailable = _networkAvailable;
    _networkAvailable = available;
    if (_playingLocalAnswer) {
      if (available && !wasAvailable && _service != null) {
        unawaited(_service!.ensureConnected());
      }
      return;
    }
    if (!available) {
      if (_hasReadySession) state = NurseUiState.reconnecting;
      errorMessage = null;
      isPressingToTalk = false;
      notifyListeners();
      return;
    }
    if (!wasAvailable ||
        state == NurseUiState.reconnecting ||
        state == NurseUiState.offline) {
      state = NurseUiState.connecting;
      errorMessage = null;
      notifyListeners();
      final service = _service;
      if (service != null) unawaited(service.ensureConnected());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final service = _service;
    if (service != null) unawaited(service.ensureConnected());
  }

  Future<void> provisionOfficialPlatform() async {
    _activationTimer?.cancel();
    activationCode = null;
    activationMessage = null;
    state = NurseUiState.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _provisioningService.check(config);
      if (result.hasWebsocketConfig) {
        config = config.copyWith(
          websocketUrl: result.websocketUrl,
          token: result.token,
          protocolVersion: result.protocolVersion,
        );
        await _repository.save(config);
        await connect();
        return;
      }

      if (result.requiresActivation) {
        activationCode = result.activationCode;
        activationMessage = result.activationMessage;
        state = NurseUiState.activationRequired;
        assistantText = '请登录小智控制台，在“添加设备”中输入屏幕上的激活码。绑定完成后，数字护士会自动连接。';
        notifyListeners();
        _startActivationPolling(result.activationTimeout);
        return;
      }

      throw const XiaozhiProvisioningException('官方平台没有返回设备配置或激活码');
    } catch (error) {
      state = NurseUiState.error;
      errorMessage = '自动配置失败：$error';
      notifyListeners();
    }
  }

  void _startActivationPolling(Duration timeout) {
    final startedAt = DateTime.now();
    _activationTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      if (DateTime.now().difference(startedAt) >= timeout) {
        timer.cancel();
        activationMessage = '激活码已超时，请点击“重新获取”生成新的激活码。';
        notifyListeners();
        return;
      }
      if (_checkingActivation) return;
      _checkingActivation = true;
      try {
        final status = await _provisioningService.activate(config);
        if (status == XiaozhiActivationStatus.activated) {
          timer.cancel();
          await provisionOfficialPlatform();
        }
      } catch (error) {
        activationMessage = '正在等待绑定；暂时无法检查激活状态：$error';
        notifyListeners();
      } finally {
        _checkingActivation = false;
      }
    });
  }

  Future<void> openOfficialConsole() async {
    try {
      await const MethodChannel(
        'digital_nurse/system',
      ).invokeMethod<void>('openUrl', {'url': 'https://xiaozhi.me'});
    } catch (_) {
      activationMessage = '请在浏览器打开 xiaozhi.me，并登录您的小智账号。';
      notifyListeners();
    }
  }

  Future<void> connect() async {
    if (_service != null) {
      _service!.removeListener(_handleServiceEvent);
      await _service!.dispose();
    }
    state = NurseUiState.connecting;
    errorMessage = null;
    notifyListeners();

    final service = XiaozhiService(
      websocketUrl: config.websocketUrl,
      macAddress: config.deviceId,
      clientId: config.clientId,
      token: config.token,
      protocolVersion: config.protocolVersion,
    );
    _service = service;
    service.addListener(_handleServiceEvent);

    try {
      await service.connectVoiceCall();
    } catch (error) {
      state = NurseUiState.error;
      errorMessage = '连接失败：$error';
      notifyListeners();
    }
  }

  Future<void> saveConfig(NurseAppConfig updated) async {
    _activationTimer?.cancel();
    final previous = config;
    final connectionChanged =
        previous.officialPlatform != updated.officialPlatform ||
        previous.otaUrl != updated.otaUrl ||
        previous.websocketUrl != updated.websocketUrl ||
        previous.deviceId != updated.deviceId ||
        previous.clientId != updated.clientId ||
        previous.token != updated.token ||
        previous.protocolVersion != updated.protocolVersion;
    config = updated;
    await _repository.save(updated);
    notifyListeners();
    if (!connectionChanged && _service != null) return;
    if (updated.officialPlatform) {
      await provisionOfficialPlatform();
    } else if (updated.canConnect) {
      await connect();
    } else {
      state = NurseUiState.setupRequired;
      notifyListeners();
    }
  }

  Future<void> resetOfficialBinding() async {
    _activationTimer?.cancel();
    activationCode = null;
    activationMessage = null;
    final service = _service;
    if (service != null) {
      service.removeListener(_handleServiceEvent);
      await service.dispose();
      _service = null;
    }
    _hasReadySession = false;
    final fresh = _repository.withFreshDeviceIdentity(config);
    config = fresh;
    await _repository.save(fresh);
    state = NurseUiState.connecting;
    errorMessage = null;
    notifyListeners();
    await provisionOfficialPlatform();
  }

  Future<void> startPushToTalk() async {
    if (_service == null || !config.canConnect || isPressingToTalk) return;
    if (_playingLocalAnswer) {
      try {
        await _localSpeech.stop();
      } finally {
        _playingLocalAnswer = false;
        await resumeOnlineAudioAfterEducation();
      }
    }
    if (state == NurseUiState.speaking) {
      await _service!.sendAbortMessage();
      await _service!.stopPlayback();
    }
    isPressingToTalk = true;
    state = NurseUiState.listening;
    userText = '';
    errorMessage = null;
    notifyListeners();
    try {
      await _service!.startListening(mode: 'manual');
    } catch (error) {
      isPressingToTalk = false;
      state = NurseUiState.error;
      errorMessage = '无法开始录音：$error';
      notifyListeners();
    }
  }

  Future<void> stopPushToTalk() async {
    if (!isPressingToTalk || _service == null) return;
    isPressingToTalk = false;
    await _service!.stopListening();
    state = NurseUiState.thinking;
    notifyListeners();
  }

  Future<void> playLocalQuickAnswer(LocalQuickAnswer item) async {
    unawaited(_usageRepository.record(AppUsageType.fixedEducation));
    _localSpeechSubscription ??= _localSpeech.events.listen(
      _handleLocalSpeechEvent,
      onError: (_) {},
    );
    _captionTimer?.cancel();
    _localCaptionFallbackTimer?.cancel();
    if (_service != null) {
      if (state == NurseUiState.speaking && !_playingLocalAnswer) {
        await _service!.sendAbortMessage();
      }
      // The Xiaozhi PCM player holds exclusive Android audio focus even while
      // idle. Releasing it lets the system TTS engine produce audible speech.
      await suspendOnlineAudioForEducation();
    }
    try {
      await _localSpeech.stop();
    } catch (_) {
      await resumeOnlineAudioAfterEducation();
      rethrow;
    }
    _stateBeforeLocalAnswer = state;
    _resetCaptionForAnswer();
    final language = config.offlineSpeechLanguage;
    final title = item.titleFor(language);
    final answer = item.answerFor(language);
    _captionTarget.addAll(answer.runes);
    _currentSentenceEnd = _captionTarget.length;
    _playingLocalAnswer = true;
    isPressingToTalk = false;
    userText = title;
    errorMessage = null;
    state = NurseUiState.speaking;
    notifyListeners();
    try {
      await _localSpeech.speak(answer, language: language);
      _localCaptionFallbackTimer = Timer(const Duration(milliseconds: 650), () {
        if (_playingLocalAnswer && _captionVisibleCount == 0) {
          _scheduleCaptionTick(const Duration(milliseconds: 60));
        }
      });
    } catch (_) {
      // The standard text remains available even if Android has no Chinese
      // speech engine installed.
      try {
        await _localSpeech.stop();
      } finally {
        await resumeOnlineAudioAfterEducation();
      }
      _revealThrough(_captionTarget.length);
      _playingLocalAnswer = false;
      state = _hasReadySession ? NurseUiState.idle : _stateBeforeLocalAnswer;
      notifyListeners();
    }
  }

  Future<void> selectOfflineSpeechLanguage(
    OfflineSpeechLanguage language,
  ) async {
    if (language == config.offlineSpeechLanguage) return;
    _captionTimer?.cancel();
    _localCaptionFallbackTimer?.cancel();
    final wasPlayingLocalAnswer = _playingLocalAnswer;
    try {
      await _localSpeech.stop();
    } finally {
      if (wasPlayingLocalAnswer) {
        await resumeOnlineAudioAfterEducation();
      }
    }
    if (_playingLocalAnswer) {
      _playingLocalAnswer = false;
      state = _hasReadySession ? NurseUiState.idle : _stateBeforeLocalAnswer;
    }
    config = config.copyWith(offlineSpeechLanguage: language);
    await _repository.save(config);
    notifyListeners();
    // Model extraction/loading may take a few seconds on the first switch. It
    // happens immediately after selection so playback itself starts faster.
    unawaited(_localSpeech.prepare(language).catchError((_) {}));
  }

  Future<void> suspendOnlineAudioForEducation() async {
    await _service?.suspendOnlinePlayback();
  }

  Future<void> resumeOnlineAudioAfterEducation() async {
    await _service?.resumeOnlinePlayback();
  }

  bool verifySettingsPassword(String input) => input == config.settingsPassword;

  void _handleLocalSpeechEvent(LocalSpeechEvent event) {
    if (!_playingLocalAnswer) return;
    if (event == LocalSpeechEvent.started) {
      _localCaptionFallbackTimer?.cancel();
      _scheduleCaptionTick(const Duration(milliseconds: 60));
      return;
    }
    if (event == LocalSpeechEvent.completed ||
        event == LocalSpeechEvent.error) {
      _revealThrough(_captionTarget.length);
      _localCaptionFallbackTimer?.cancel();
      _playingLocalAnswer = false;
      state = _hasReadySession ? NurseUiState.idle : _stateBeforeLocalAnswer;
      notifyListeners();
      unawaited(resumeOnlineAudioAfterEducation());
    }
  }

  void showEscalation() {
    unawaited(_usageRepository.record(AppUsageType.contactNurse));
    _captionTimer?.cancel();
    _localCaptionFallbackTimer?.cancel();
    final wasPlayingLocalAnswer = _playingLocalAnswer;
    unawaited(
      _localSpeech.stop().whenComplete(() async {
        if (wasPlayingLocalAnswer) {
          await resumeOnlineAudioAfterEducation();
        }
      }),
    );
    _playingLocalAnswer = false;
    state = NurseUiState.warning;
    assistantText = config.callNurseText;
    notifyListeners();
  }

  void _handleServiceEvent(XiaozhiServiceEvent event) {
    if (_playingLocalAnswer) {
      if (event.type == XiaozhiServiceEventType.sessionReady) {
        _hasReadySession = true;
      }
      return;
    }
    switch (event.type) {
      case XiaozhiServiceEventType.connected:
        state = NurseUiState.connecting;
        errorMessage = null;
        break;
      case XiaozhiServiceEventType.sessionReady:
        _hasReadySession = true;
        _networkErrorCount = 0;
        errorMessage = null;
        state = NurseUiState.idle;
        break;
      case XiaozhiServiceEventType.disconnected:
        isPressingToTalk = false;
        state =
            _hasReadySession
                ? NurseUiState.reconnecting
                : NurseUiState.connecting;
        errorMessage = null;
        break;
      case XiaozhiServiceEventType.userMessage:
        unawaited(_usageRepository.record(AppUsageType.voiceQuestion));
        userText = event.data?.toString() ?? '';
        state = NurseUiState.thinking;
        break;
      case XiaozhiServiceEventType.textMessage:
      case XiaozhiServiceEventType.assistantText:
        final text = event.data?.toString() ?? '';
        if (text.isNotEmpty) _appendCaptionSentence(text);
        break;
      case XiaozhiServiceEventType.ttsStart:
        _resetCaptionForAnswer();
        state = NurseUiState.speaking;
        break;
      case XiaozhiServiceEventType.ttsSentenceEnd:
        _revealThrough(_currentSentenceEnd);
        break;
      case XiaozhiServiceEventType.ttsStop:
        _revealThrough(_captionTarget.length);
        state = NurseUiState.idle;
        break;
      case XiaozhiServiceEventType.emotion:
        emotion = event.data?.toString() ?? 'neutral';
        break;
      case XiaozhiServiceEventType.error:
        _networkErrorCount++;
        errorMessage = null;
        state =
            _networkErrorCount >= 4
                ? NurseUiState.offline
                : (_hasReadySession
                    ? NurseUiState.reconnecting
                    : NurseUiState.connecting);
        break;
      case XiaozhiServiceEventType.audioData:
        break;
      case XiaozhiServiceEventType.voiceCallStart:
      case XiaozhiServiceEventType.voiceCallEnd:
        break;
    }
    notifyListeners();
  }

  void _resetCaptionForAnswer() {
    _captionTimer?.cancel();
    _localCaptionFallbackTimer?.cancel();
    _captionTimer = null;
    _captionTarget.clear();
    _captionVisibleCount = 0;
    _currentSentenceEnd = 0;
    assistantText = '';
  }

  void _appendCaptionSentence(String text) {
    if (_captionTarget.isNotEmpty) _captionTarget.add('\n'.runes.single);
    _captionTarget.addAll(text.runes);
    _currentSentenceEnd = _captionTarget.length;
    _scheduleCaptionTick();
  }

  void _scheduleCaptionTick([
    Duration delay = const Duration(milliseconds: 90),
  ]) {
    if (_captionVisibleCount >= _captionTarget.length ||
        (_captionTimer?.isActive ?? false)) {
      return;
    }
    _captionTimer = Timer(delay, _revealNextCaptionCharacter);
  }

  void _revealNextCaptionCharacter() {
    _captionTimer = null;
    if (_captionVisibleCount >= _captionTarget.length) return;
    _captionVisibleCount++;
    assistantText = String.fromCharCodes(
      _captionTarget.take(_captionVisibleCount),
    );
    notifyListeners();

    final last = _captionTarget[_captionVisibleCount - 1];
    final punctuation = '，。！？；：、,.!?;:'.runes.contains(last);
    _scheduleCaptionTick(Duration(milliseconds: punctuation ? 220 : 115));
  }

  void _revealThrough(int target) {
    if (target <= _captionVisibleCount || _captionTarget.isEmpty) return;
    _captionVisibleCount = target.clamp(0, _captionTarget.length).toInt();
    assistantText = String.fromCharCodes(
      _captionTarget.take(_captionVisibleCount),
    );
    notifyListeners();
    _scheduleCaptionTick();
  }

  String get statusLabel => switch (state) {
    NurseUiState.setupRequired => '等待配置',
    NurseUiState.activationRequired => '等待激活',
    NurseUiState.connecting => '正在连接',
    NurseUiState.idle => '可以开始提问',
    NurseUiState.listening => '正在聆听',
    NurseUiState.thinking => '正在查询',
    NurseUiState.speaking => '正在回答',
    NurseUiState.reconnecting => '正在恢复连接',
    NurseUiState.warning => '请联系护士',
    NurseUiState.offline => '等待网络恢复',
    NurseUiState.error => '出现问题',
  };

  bool get canInteract =>
      config.canConnect &&
      state != NurseUiState.setupRequired &&
      state != NurseUiState.activationRequired &&
      state != NurseUiState.connecting &&
      state != NurseUiState.reconnecting &&
      state != NurseUiState.offline &&
      state != NurseUiState.error;

  @override
  void dispose() {
    if (_lifecycleInstalled) WidgetsBinding.instance.removeObserver(this);
    _activationTimer?.cancel();
    _captionTimer?.cancel();
    _localCaptionFallbackTimer?.cancel();
    _networkSubscription?.cancel();
    _localSpeechSubscription?.cancel();
    unawaited(_localSpeech.stop());
    _service?.removeListener(_handleServiceEvent);
    final service = _service;
    if (service != null) unawaited(service.dispose());
    super.dispose();
  }
}
