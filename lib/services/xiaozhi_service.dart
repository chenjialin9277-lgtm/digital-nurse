import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:permission_handler/permission_handler.dart';
import '../services/online_playback_gate.dart';
import '../services/push_to_talk_audio_session.dart';
import '../services/xiaozhi_websocket_manager.dart';
import '../utils/audio_util.dart';

import '../utils/diagnostic_log.dart';

/// 小智服务事件类型
enum XiaozhiServiceEventType {
  connected,
  disconnected,
  textMessage,
  audioData,
  error,
  voiceCallStart,
  voiceCallEnd,
  userMessage,
  sessionReady,
  assistantText,
  ttsStart,
  ttsSentenceEnd,
  ttsStop,
  emotion,
}

/// 小智服务事件
class XiaozhiServiceEvent {
  final XiaozhiServiceEventType type;
  final dynamic data;

  XiaozhiServiceEvent(this.type, this.data);
}

/// 小智服务监听器
typedef XiaozhiServiceListener = void Function(XiaozhiServiceEvent event);

/// 消息监听器
typedef MessageListener = void Function(dynamic message);

/// 小智服务
class XiaozhiService {
  static const String _logTag = "XiaozhiService";
  static const String defaultServer = "wss://ws.xiaozhi.ai";

  final String websocketUrl;
  final String macAddress;
  final String clientId;
  final String token;
  final int protocolVersion;
  String? _sessionId; // 会话ID将由服务器提供

  XiaozhiWebSocketManager? _webSocketManager;
  bool _isConnected = false;
  bool _isMuted = false;
  final List<XiaozhiServiceListener> _listeners = [];
  StreamSubscription? _audioStreamSubscription;
  PushToTalkAudioSession? _pushToTalkSession;
  bool _isVoiceCallActive = false;
  bool _hasStartedCall = false;
  MessageListener? _messageListener;
  final OnlinePlaybackGate _onlinePlayback;
  Completer<String>? _silentTextCompleter;
  StringBuffer? _silentTextBuffer;
  Timer? _silentTextTimeout;
  bool _silentTextReceivedStart = false;

  XiaozhiService({
    required this.websocketUrl,
    required this.macAddress,
    required this.clientId,
    required this.token,
    this.protocolVersion = 1,
    String? sessionId,
    @visibleForTesting OnlinePlaybackGate? onlinePlaybackGate,
  }) : _onlinePlayback =
           onlinePlaybackGate ??
           OnlinePlaybackGate(
             playFrame: AudioUtil.playOpusData,
             stopPlayer: AudioUtil.stopPlaying,
             startPlayer: AudioUtil.initPlayer,
           ) {
    _sessionId = sessionId;
  }

  /// 切换到语音通话模式
  Future<void> switchToVoiceCallMode() async {
    // 如果已经在语音通话模式，直接返回
    if (_isVoiceCallActive) return;

    try {
      logDiagnostic('$_logTag: 正在切换到语音通话模式');

      // 简化初始化流程，确保干净状态
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      _isVoiceCallActive = true;
      logDiagnostic('$_logTag: 已切换到语音通话模式');
    } catch (e) {
      logDiagnostic('$_logTag: 切换到语音通话模式失败: $e');
      rethrow;
    }
  }

  /// 切换到普通聊天模式
  Future<void> switchToChatMode() async {
    // 如果已经在普通聊天模式，直接返回
    if (!_isVoiceCallActive) return;

    try {
      logDiagnostic('$_logTag: 正在切换到普通聊天模式');

      // 停止语音通话相关的活动
      await stopListeningCall();

      // 确保播放器停止
      await AudioUtil.stopPlaying();

      _isVoiceCallActive = false;
      logDiagnostic('$_logTag: 已切换到普通聊天模式');
    } catch (e) {
      logDiagnostic('$_logTag: 切换到普通聊天模式失败: $e');
      _isVoiceCallActive = false;
    }
  }

  /// 设置消息监听器
  void setMessageListener(MessageListener listener) {
    _messageListener = listener;
  }

  /// 添加事件监听器
  void addListener(XiaozhiServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiServiceListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiServiceEvent event) {
    for (final listener in List<XiaozhiServiceListener>.of(_listeners)) {
      listener(event);
    }
  }

  /// 连接到小智服务
  Future<void> connect() async {
    if (_isConnected) return;

    if (_webSocketManager != null) {
      await _webSocketManager!.ensureConnected();
      return;
    }

    try {
      logDiagnostic('$_logTag: 开始连接服务器...');

      // 创建WebSocket管理器
      _webSocketManager = XiaozhiWebSocketManager(
        deviceId: macAddress,
        clientId: clientId,
        protocolVersion: protocolVersion,
        enableToken: true,
      );

      // 添加WebSocket事件监听
      _webSocketManager!.addListener(_onWebSocketEvent);

      // 连接WebSocket
      await _webSocketManager!.connect(websocketUrl, token);
    } catch (e) {
      logDiagnostic('$_logTag: 连接失败: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.error, '连接小智服务失败: $e'),
      );
    }
  }

  /// 断开小智服务连接
  Future<void> disconnect() async {
    try {
      final pushToTalk = _pushToTalkSession;
      _pushToTalkSession = null;
      await pushToTalk?.stop();

      if (_webSocketManager == null) return;

      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 断开WebSocket连接
      await _webSocketManager!.disconnect();
      _webSocketManager = null;
      _isConnected = false;
    } catch (e) {
      logDiagnostic('$_logTag: 断开连接失败: $e');
    }
  }

  /// 发送文本消息
  Future<String> sendTextMessage(String message) async {
    if (!isConnected) {
      await connect();
    }

    try {
      // 创建一个Completer来等待响应
      final completer = Completer<String>();
      logDiagnostic('$_logTag: 开始发送文本消息');

      // 添加消息监听器，监听所有可能的回复
      void onceListener(XiaozhiServiceEvent event) {
        if (event.type == XiaozhiServiceEventType.textMessage) {
          // 忽略echo消息（即我们发送的消息）
          if (event.data == message) {
            logDiagnostic('$_logTag: 忽略echo消息');
            return;
          }

          logDiagnostic('$_logTag: 收到服务器响应');
          if (!completer.isCompleted) {
            completer.complete(event.data as String);
            removeListener(onceListener);
          }
        } else if (event.type == XiaozhiServiceEventType.error &&
            !completer.isCompleted) {
          logDiagnostic('$_logTag: 收到错误响应');
          completer.completeError(event.data.toString());
          removeListener(onceListener);
        }
      }

      // 先添加监听器，确保不会错过任何消息
      addListener(onceListener);

      // 发送文本请求
      logDiagnostic('$_logTag: 发送文本请求');
      _webSocketManager!.sendTextRequest(message);

      // 设置超时，15秒比10秒更宽松一些
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          logDiagnostic('$_logTag: 请求超时，15秒内没有收到响应');
          completer.completeError('请求超时');
          removeListener(onceListener);
        }
      });

      // 等待响应
      try {
        final result = await completer.future;
        // 取消超时定时器
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        // 取消超时定时器
        timeoutTimer.cancel();
        rethrow;
      }
    } catch (e) {
      logDiagnostic('$_logTag: 发送消息失败: $e');
      rethrow;
    }
  }

  /// Requests a text-only answer through the already-bound Xiaozhi account.
  /// Incoming TTS audio and UI events are suppressed until the response is
  /// complete, which lets settings features such as translation reuse the
  /// existing account without speaking the prompt or JSON result aloud.
  Future<String> requestSilentTextMessage(String message) async {
    if (_silentTextCompleter != null) {
      throw StateError('已有一项智能生成任务正在进行');
    }
    if (!isConnected) await ensureConnected();
    if (!isConnected) throw StateError('小智尚未连接，请联网后重试');

    await sendAbortMessage();
    await stopPlayback();
    final completer = Completer<String>();
    _silentTextCompleter = completer;
    _silentTextBuffer = StringBuffer();
    _silentTextReceivedStart = false;
    _silentTextTimeout = Timer(const Duration(seconds: 90), () {
      _finishSilentTextRequest(error: StateError('智能生成超时，请检查网络后重试'));
    });
    try {
      _webSocketManager!.sendTextRequest(message);
      final result = (await completer.future).trim();
      if (result.isEmpty) throw StateError('小智没有返回可用的翻译内容');
      return result;
    } finally {
      if (identical(_silentTextCompleter, completer)) {
        _silentTextTimeout?.cancel();
        _silentTextTimeout = null;
        _silentTextCompleter = null;
        _silentTextBuffer = null;
        _silentTextReceivedStart = false;
      }
    }
  }

  void _finishSilentTextRequest({Object? error}) {
    final completer = _silentTextCompleter;
    if (completer == null || completer.isCompleted) return;
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(_silentTextBuffer?.toString() ?? '');
    }
  }

  /// 连接语音通话
  Future<void> connectVoiceCall() async {
    try {
      if (_webSocketManager != null) {
        await _webSocketManager!.ensureConnected();
        return;
      }
      // 简化流程，确保权限和音频准备就绪
      if (Platform.isIOS || Platform.isAndroid) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          logDiagnostic('$_logTag: 麦克风权限被拒绝');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.error, '麦克风权限被拒绝'),
          );
          return;
        }
      }

      // 初始化音频系统
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      logDiagnostic('$_logTag: 正在连接服务器');
      logDiagnostic('$_logTag: 设备身份已配置');
      logDiagnostic('$_logTag: Token启用: true');
      logDiagnostic('$_logTag: 已启用Token认证');

      // 使用 WebSocketManager 连接
      _webSocketManager = XiaozhiWebSocketManager(
        deviceId: macAddress,
        clientId: clientId,
        protocolVersion: protocolVersion,
        enableToken: true,
      );
      _webSocketManager!.addListener(_onWebSocketEvent);
      await _webSocketManager!.connect(websocketUrl, token);
    } catch (e) {
      logDiagnostic('$_logTag: 连接失败: $e');
      rethrow;
    }
  }

  /// 结束语音通话
  Future<void> disconnectVoiceCall() async {
    if (_webSocketManager == null) return;

    try {
      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 停止音频播放
      await AudioUtil.stopPlaying();

      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 直接断开连接
      await disconnect();
    } catch (e) {
      // 忽略断开连接时的错误
      logDiagnostic('$_logTag: 结束语音通话时发生错误: $e');
    }
  }

  /// 开始说话
  Future<void> startSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'start', 'mode': 'auto'};
      _webSocketManager?.sendMessage(jsonEncode(message));
      logDiagnostic('$_logTag: 已发送开始说话消息');
    } catch (e) {
      logDiagnostic('$_logTag: 开始说话失败: $e');
    }
  }

  /// 停止说话
  Future<void> stopSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'stop', 'mode': 'auto'};
      _webSocketManager?.sendMessage(jsonEncode(message));
      logDiagnostic('$_logTag: 已发送停止说话消息');
    } catch (e) {
      logDiagnostic('$_logTag: 停止说话失败: $e');
    }
  }

  /// 发送listen消息
  void _sendListenMessage() async {
    try {
      final listenMessage = {
        'type': 'listen',
        'session_id': _sessionId,
        'state': 'start',
        'mode': 'auto',
      };
      _webSocketManager?.sendMessage(jsonEncode(listenMessage));
      logDiagnostic('$_logTag: 已发送listen消息');

      // 开始录音
      _isVoiceCallActive = true;
      await AudioUtil.startRecording();
    } catch (e) {
      logDiagnostic('$_logTag: 发送listen消息失败: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.error, '发送listen消息失败: $e'),
      );
    }
  }

  /// 开始听说（语音通话模式）
  Future<void> startListeningCall() async {
    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        logDiagnostic('$_logTag: 没有会话ID，无法开始监听，等待会话ID初始化...');
        // 等待短暂时间，然后重新检查会话ID
        await Future.delayed(const Duration(milliseconds: 500));
        if (_sessionId == null) {
          logDiagnostic('$_logTag: 会话ID仍然为空，放弃开始监听');
          throw Exception('会话ID为空，无法开始录音');
        }
      }

      logDiagnostic('$_logTag: 使用当前会话开始录音');

      // 请求麦克风权限
      if (Platform.isIOS) {
        final micStatus = await Permission.microphone.status;
        if (micStatus != PermissionStatus.granted) {
          final result = await Permission.microphone.request();
          if (result != PermissionStatus.granted) {
            logDiagnostic('$_logTag: 麦克风权限被拒绝');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.error, '麦克风权限被拒绝'),
            );
            return;
          }
        }

        // 确保音频会话已初始化
        await AudioUtil.initRecorder();
      } else {
        // Android权限请求
        final status = await Permission.microphone.request();
        if (status.isDenied) {
          logDiagnostic('$_logTag: 麦克风权限被拒绝');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.error, '麦克风权限被拒绝'),
          );
          return;
        }
      }

      // 开始录音
      await AudioUtil.startRecording();

      // 设置音频流订阅
      _audioStreamSubscription = AudioUtil.audioStream.listen((opusData) {
        // 发送音频数据
        _webSocketManager?.sendBinaryMessage(opusData);
      });

      // 发送开始监听命令
      final message = {
        'session_id': _sessionId,
        'type': 'listen',
        'state': 'start',
        'mode': 'auto',
      };
      _webSocketManager?.sendMessage(jsonEncode(message));
      logDiagnostic('$_logTag: 已发送开始监听消息 (语音通话模式)');
    } catch (e) {
      logDiagnostic('$_logTag: 开始监听失败: $e');
      throw Exception('开始语音输入失败: $e');
    }
  }

  /// 停止听说（语音通话模式）
  Future<void> stopListeningCall() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _webSocketManager != null) {
        final message = {
          'session_id': _sessionId,
          'type': 'listen',
          'state': 'stop',
          'mode': 'auto',
        };
        _webSocketManager?.sendMessage(jsonEncode(message));
        logDiagnostic('$_logTag: 已发送停止监听消息 (语音通话模式)');
      }
    } catch (e) {
      logDiagnostic('$_logTag: 停止监听失败: $e');
    }
  }

  /// 取消发送（上滑取消）
  Future<void> abortListening() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送中止命令
      if (_sessionId != null && _webSocketManager != null) {
        final message = {'session_id': _sessionId, 'type': 'abort'};
        _webSocketManager?.sendMessage(jsonEncode(message));
        logDiagnostic('$_logTag: 已发送中止消息');
      }
    } catch (e) {
      logDiagnostic('$_logTag: 中止监听失败: $e');
    }
  }

  /// 切换静音状态
  void toggleMute() {
    _isMuted = !_isMuted;

    if (_webSocketManager == null || !_webSocketManager!.isConnected) return;

    try {
      final request = {'type': _isMuted ? 'voice_mute' : 'voice_unmute'};

      _webSocketManager!.sendMessage(jsonEncode(request));
    } catch (e) {
      logDiagnostic('$_logTag: 切换静音状态失败: $e');
    }
  }

  /// 处理WebSocket事件
  @visibleForTesting
  void debugHandleWebSocketEvent(XiaozhiEvent event) {
    _onWebSocketEvent(event);
  }

  void _onWebSocketEvent(XiaozhiEvent event) {
    switch (event.type) {
      case XiaozhiEventType.connected:
        _isConnected = true;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.connected, null),
        );
        break;

      case XiaozhiEventType.disconnected:
        _isConnected = false;
        _sessionId = null;
        _hasStartedCall = false;
        _finishSilentTextRequest(error: StateError('小智连接已断开'));
        unawaited(_stopStreamingAfterConnectionLoss());
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.disconnected, event.data),
        );
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        final audioData = event.data as List<int>;
        if (_silentTextCompleter != null) break;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.audioData, audioData),
        );
        unawaited(
          _onlinePlayback
              .enqueueFrame(Uint8List.fromList(audioData))
              .catchError((Object error, StackTrace stackTrace) {
                _dispatchEvent(
                  XiaozhiServiceEvent(
                    XiaozhiServiceEventType.error,
                    '在线音频播放失败：$error',
                  ),
                );
              }),
        );
        break;

      case XiaozhiEventType.error:
        _finishSilentTextRequest(error: StateError(event.data.toString()));
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.error, event.data),
        );
        break;
    }
  }

  Future<void> _stopStreamingAfterConnectionLoss() async {
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    if (AudioUtil.isRecording) await AudioUtil.stopRecording();
  }

  /// Forces an immediate reconnect after Android reports that a network is
  /// available or when the app returns to the foreground.
  Future<void> ensureConnected() async {
    if (_webSocketManager == null) {
      await connectVoiceCall();
    } else {
      await _webSocketManager!.ensureConnected();
    }
  }

  /// 处理文本消息
  void _handleTextMessage(String message) {
    logDiagnostic('$_logTag: 收到文本消息');
    try {
      final Map<String, dynamic> jsonData = json.decode(message);
      final String type = jsonData['type'] ?? '';

      // 确保首先调用消息监听器
      if (_messageListener != null) {
        _messageListener!(jsonData);
      }

      // 更新会话ID（服务器在hello消息中会提供新的会话ID）
      if (jsonData['session_id'] != null) {
        _sessionId = jsonData['session_id'];
        logDiagnostic('$_logTag: 更新会话状态');
      }

      // 根据消息类型分发事件
      switch (type) {
        case 'hello':
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.sessionReady, jsonData),
          );
          // 处理服务器的hello响应
          if (_isVoiceCallActive && !_hasStartedCall) {
            _hasStartedCall = true;
            // 发送自动说话模式消息
            startSpeaking();
          }
          break;

        case 'start':
          // 收到start响应后，如果是语音通话模式，开始录音
          if (_isVoiceCallActive) {
            _sendListenMessage();
          }
          break;

        case 'tts':
          // TTS消息处理
          final String state = jsonData['state'] ?? '';
          final String text = jsonData['text'] ?? '';

          if (_silentTextCompleter != null) {
            if (state == 'start') {
              _silentTextReceivedStart = true;
            } else if (state == 'sentence_start' && text.isNotEmpty) {
              _silentTextReceivedStart = true;
              _silentTextBuffer?.write(text);
            } else if (state == 'stop' && _silentTextReceivedStart) {
              _finishSilentTextRequest();
            }
            break;
          }

          if (state == 'start') {
            unawaited(
              _onlinePlayback.beginUtterance().catchError((
                Object error,
                StackTrace stackTrace,
              ) {
                _dispatchEvent(
                  XiaozhiServiceEvent(
                    XiaozhiServiceEventType.error,
                    '在线音频缓冲初始化失败：$error',
                  ),
                );
              }),
            );
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.ttsStart, null),
            );
          } else if (state == 'stop') {
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.ttsStop, null),
            );
          } else if (state == 'sentence_start' && text.isNotEmpty) {
            logDiagnostic('$_logTag: 收到TTS句子');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.assistantText, text),
            );
          } else if (state == 'sentence_end') {
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.ttsSentenceEnd, null),
            );
          }
          break;

        case 'stt':
          // 处理语音识别结果
          final String text = jsonData['text'] ?? '';
          if (text.isNotEmpty) {
            logDiagnostic('$_logTag: 收到语音识别结果');
            // 先分发用户消息事件
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.userMessage, text),
            );
          }
          break;

        case 'llm':
        case 'emotion':
          final String emotion = jsonData['emotion'] ?? '';
          if (emotion.isNotEmpty) {
            logDiagnostic('$_logTag: 收到表情消息: $emotion');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.emotion, emotion),
            );
          }
          break;

        default:
          // 对于其他类型的消息，直接忽略
          logDiagnostic('$_logTag: 收到未知类型消息');
      }
    } catch (e) {
      logDiagnostic('$_logTag: 解析消息失败');
    }
  }

  /// 中断音频播放
  Future<void> stopPlayback() async {
    try {
      logDiagnostic('$_logTag: 正在停止音频播放');

      await _onlinePlayback.stop();

      logDiagnostic('$_logTag: 音频播放已停止');
    } catch (e) {
      logDiagnostic('$_logTag: 停止音频播放失败: $e');
    }
  }

  Future<void> suspendOnlinePlayback() => _onlinePlayback.suspend();

  Future<void> resumeOnlinePlayback() => _onlinePlayback.resume();

  /// 判断是否已连接
  bool get isConnected =>
      _isConnected &&
      _webSocketManager != null &&
      _webSocketManager!.isConnected;

  /// 判断是否静音
  bool get isMuted => _isMuted;

  /// 判断语音通话是否活跃
  bool get isVoiceCallActive => _isVoiceCallActive;

  /// 释放资源
  Future<void> dispose() async {
    await disconnect();
    await AudioUtil.dispose();
    _listeners.clear();
    logDiagnostic('$_logTag: 资源已释放');
  }

  /// 开始监听（按住说话模式）
  Future<void> startListening({String mode = 'manual'}) async {
    if (!_isConnected || _webSocketManager == null) {
      await connect();
    }

    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        logDiagnostic('$_logTag: 没有会话ID，无法开始监听');
        throw Exception('服务器会话尚未准备完成');
      }

      final session = PushToTalkAudioSession(
        playback: _onlinePlayback,
        microphoneFrames: AudioUtil.audioStream,
        startMicrophone: AudioUtil.startRecording,
        stopMicrophone: () async {
          await AudioUtil.stopRecording();
        },
        sendStart: () {
          final message = {
            'session_id': _sessionId,
            'type': 'listen',
            'state': 'start',
            'mode': mode,
          };
          _webSocketManager?.sendMessage(jsonEncode(message));
          logDiagnostic('$_logTag: 已发送开始监听消息 (按住说话)');
        },
        sendAudio: (opusData) {
          _webSocketManager?.sendBinaryMessage(opusData);
        },
        sendStop: () {
          if (_sessionId == null || _webSocketManager == null) return;
          final message = {
            'session_id': _sessionId,
            'type': 'listen',
            'state': 'stop',
          };
          _webSocketManager?.sendMessage(jsonEncode(message));
          logDiagnostic('$_logTag: 已发送停止监听消息');
        },
      );
      _pushToTalkSession = session;
      try {
        await session.start();
      } catch (_) {
        if (identical(_pushToTalkSession, session)) {
          _pushToTalkSession = null;
        }
        rethrow;
      }
    } catch (e) {
      logDiagnostic('$_logTag: 开始监听失败: $e');
      throw Exception('开始语音输入失败: $e');
    }
  }

  /// 停止监听（按住说话模式）
  Future<void> stopListening() async {
    try {
      final session = _pushToTalkSession;
      _pushToTalkSession = null;
      await session?.stop();
    } catch (e) {
      logDiagnostic('$_logTag: 停止监听失败: $e');
    }
  }

  /// 发送中断消息
  Future<void> sendAbortMessage() async {
    try {
      if (_webSocketManager != null && _isConnected && _sessionId != null) {
        final abortMessage = {
          'session_id': _sessionId,
          'type': 'abort',
          'reason': 'wake_word_detected',
        };
        _webSocketManager?.sendMessage(jsonEncode(abortMessage));
        logDiagnostic('$_logTag: 发送中断消息');

        // 如果当前正在录音，短暂停顿后继续
        if (_isSpeaking) {
          await stopListeningCall();
          await Future.delayed(const Duration(milliseconds: 500));
          await startListeningCall();
        }
      }
    } catch (e) {
      logDiagnostic('$_logTag: 发送中断消息失败: $e');
    }
  }

  /// 判断是否正在说话
  bool get _isSpeaking =>
      _audioStreamSubscription != null || _pushToTalkSession != null;
}
