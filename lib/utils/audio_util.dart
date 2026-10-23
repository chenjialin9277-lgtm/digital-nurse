import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_pcm_player/flutter_pcm_player.dart';

import '../services/microphone_capture_result.dart';
import '../services/online_audio_prebuffer.dart';

import 'diagnostic_log.dart';

/// 音频工具类，用于处理Opus音频编解码和录制播放
class AudioUtil {
  static const String _logTag = "AudioUtil";
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int frameDuration = 60; // 毫秒

  static const RecordConfig recordConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: channels,
    autoGain: true,
    echoCancel: false,
    noiseSuppress: false,
    androidConfig: AndroidRecordConfig(
      manageBluetooth: false,
      audioSource: AndroidAudioSource.voiceRecognition,
    ),
  );

  static final AudioRecorder _audioRecorder = AudioRecorder();
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isStoppingRecording = false;
  static bool _isPlaying = false;
  static final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  static StreamSubscription<Uint8List>? _recordingSubscription;
  static final List<int> _pendingPcmBytes = [];
  static MicrophoneCaptureTracker? _captureTracker;
  static final OnlineAudioPrebuffer _onlinePrebuffer = OnlineAudioPrebuffer();

  // Opus相关
  static final _encoder = SimpleOpusEncoder(
    sampleRate: sampleRate,
    channels: channels,
    application: Application.voip,
  );
  static final _decoder = SimpleOpusDecoder(
    sampleRate: sampleRate,
    channels: channels,
  );

  // FlutterPcmPlayer实例
  static FlutterPcmPlayer? _pcmPlayer;

  /// 获取音频流
  static Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 初始化音频录制器
  static Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;

    logDiagnostic('$_logTag: 开始初始化录音器');

    // 更积极地请求所有可能需要的权限
    if (Platform.isAndroid) {
      logDiagnostic('$_logTag: 请求Android所需的所有权限');
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        logDiagnostic('$_logTag: 麦克风权限被拒绝');
        throw Exception('需要麦克风权限');
      }
    } else {
      // iOS/其他平台只请求麦克风权限
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        logDiagnostic('$_logTag: 麦克风权限被拒绝');
        throw Exception('需要麦克风权限');
      }
    }

    // 检查是否可用
    logDiagnostic('$_logTag: 检查PCM16编码是否支持');
    final isAvailable = await _audioRecorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    logDiagnostic('$_logTag: PCM16编码支持状态: $isAvailable');

    // 设置音频模式 - 参考Android原生实现
    logDiagnostic('$_logTag: 配置音频会话');
    final session = await AudioSession.instance;

    // 使用与原生Android实现更接近的配置
    if (Platform.isAndroid) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientExclusive,
          androidWillPauseWhenDucked: false,
        ),
      );
    } else {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
        ),
      );
      await session.setActive(true);
    }

    _isRecorderInitialized = true;
    logDiagnostic('$_logTag: 录音器初始化成功');
  }

  /// 初始化音频播放器
  static Future<void> initPlayer() async {
    // 确保任何旧播放器被释放
    await stopPlaying();

    try {
      logDiagnostic('$_logTag: 使用简单方式初始化PCM播放器');

      // 创建新的播放器实例 - 完全按照官方示例的简单方式
      _pcmPlayer = FlutterPcmPlayer();
      await _pcmPlayer!.initialize();
      await _pcmPlayer!.play();

      _isPlayerInitialized = true;
      logDiagnostic('$_logTag: PCM播放器初始化成功');
    } catch (e) {
      logDiagnostic('$_logTag: PCM播放器初始化失败: $e');
      _isPlayerInitialized = false;
      _pcmPlayer = null;
      rethrow;
    }
  }

  /// 播放Opus音频数据
  static Future<void> playOpusData(Uint8List opusData) async {
    try {
      // 解码Opus数据
      final Int16List pcmData = _decoder.decode(input: opusData);

      // 准备PCM数据（按照示例直接方式）
      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      ByteData bytes = ByteData.view(pcmBytes.buffer);

      // 使用小端字节序
      for (int i = 0; i < pcmData.length; i++) {
        bytes.setInt16(i * 2, pcmData[i], Endian.little);
      }

      final readyFrames = _onlinePrebuffer.add(pcmBytes);
      if (readyFrames.isEmpty) return;

      // Wait for several real-time packets before playback. Feeding the whole
      // initial batch gives AudioTrack enough headroom for normal Wi-Fi jitter.
      if (!_isPlayerInitialized || _pcmPlayer == null) {
        await initPlayer();
        _onlinePrebuffer.markStarted();
      }
      final player = _pcmPlayer;
      if (player == null) return;
      for (final frame in readyFrames) {
        await player.feed(frame);
      }
      _isPlaying = true;
    } catch (e) {
      logDiagnostic('$_logTag: 播放失败: $e');
      // Rebuffer after a player failure instead of restarting from one frame,
      // which would immediately expose the user to another underrun.
      await stopPlaying();
    }
  }

  /// 停止播放
  static Future<void> stopPlaying() async {
    _onlinePrebuffer.reset();
    if (_pcmPlayer != null) {
      try {
        await _pcmPlayer!.stop();
        logDiagnostic('$_logTag: 播放器已停止');
      } catch (e) {
        logDiagnostic('$_logTag: 停止播放失败: $e');
      }
      _pcmPlayer = null;
      _isPlayerInitialized = false;
      _isPlaying = false;
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await stopRecording();
    await stopPlaying();
    logDiagnostic('$_logTag: 资源已释放');
  }

  /// 开始录音
  static Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    if (_isRecording) return;

    try {
      logDiagnostic('$_logTag: 尝试启动录音');

      // 确保麦克风权限已获取 - 使用不同方式检查权限
      final status = await Permission.microphone.status;
      logDiagnostic('$_logTag: 麦克风权限状态: $status');

      if (status != PermissionStatus.granted) {
        final result = await Permission.microphone.request();
        logDiagnostic('$_logTag: 请求麦克风权限结果: $result');
        if (result != PermissionStatus.granted) {
          logDiagnostic('$_logTag: 麦克风权限被拒绝');
          throw Exception('需要麦克风权限');
        }
      }

      // 尝试直接使用音频流
      try {
        logDiagnostic('$_logTag: 尝试启动流式录音');
        _captureTracker = MicrophoneCaptureTracker();
        final stream = await _audioRecorder.startStream(recordConfig);

        _isRecording = true;
        _isStoppingRecording = false;
        logDiagnostic('$_logTag: 流式录音启动成功');

        _pendingPcmBytes.clear();
        _recordingSubscription = stream.listen(
          (data) {
            if (data.isEmpty) return;
            _pendingPcmBytes.addAll(data);
            const frameBytes = sampleRate * frameDuration ~/ 1000 * 2;
            while (_pendingPcmBytes.length >= frameBytes) {
              final frame = Uint8List.fromList(
                _pendingPcmBytes.sublist(0, frameBytes),
              );
              _pendingPcmBytes.removeRange(0, frameBytes);
              _captureTracker?.addPcmFrame(frame);
              final opusData = encodeToOpus(frame);
              if (opusData != null) {
                _captureTracker?.markEncodedFrame();
                _audioStreamController.add(opusData);
              }
            }
          },
          onError: (error) {
            logDiagnostic('$_logTag: 音频流错误: $error');
            _captureTracker?.markStreamError(error);
            _isRecording = false;
          },
          onDone: () {
            logDiagnostic('$_logTag: 音频流结束');
            if (!_isStoppingRecording) {
              _captureTracker?.markStreamError(StateError('音频流在停止请求前结束'));
            }
            _isRecording = false;
          },
        );
      } catch (e) {
        logDiagnostic('$_logTag: 流式录音失败: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      logDiagnostic('$_logTag: 启动录音失败: $e');
      logDiagnostic(stackTrace);
      _isRecording = false;
      _isStoppingRecording = false;
      _captureTracker = null;
      rethrow;
    }
  }

  /// 停止录音
  static Future<MicrophoneCaptureResult> stopRecording() async {
    final tracker = _captureTracker ?? MicrophoneCaptureTracker();
    _isStoppingRecording = true;
    try {
      if (_isRecorderInitialized) await _audioRecorder.stop();
      await _recordingSubscription?.cancel();
      final result = tracker.finish();
      logDiagnostic(
        '$_logTag: 停止录音，PCM字节=${result.pcmByteCount}，'
        '编码帧=${result.encodedFrameCount}，有效帧=${result.voicedFrameCount}，'
        '峰值=${result.peakAmplitude}，流错误=${result.streamFailed}',
      );
      return result;
    } catch (error) {
      logDiagnostic('$_logTag: 停止录音失败: $error');
      tracker.markStreamError(error);
      return tracker.finish();
    } finally {
      _recordingSubscription = null;
      _pendingPcmBytes.clear();
      _captureTracker = null;
      _isRecording = false;
      _isStoppingRecording = false;
    }
  }

  /// 将PCM数据编码为Opus格式
  static Uint8List? encodeToOpus(Uint8List pcmData) {
    try {
      // 删除频繁日志
      // 转换PCM数据为Int16List (小端字节序，与Android一致)
      final Int16List pcmInt16 = Int16List.fromList(
        List.generate(
          pcmData.length ~/ 2,
          (i) => (pcmData[i * 2]) | (pcmData[i * 2 + 1] << 8),
        ),
      );

      // 确保数据长度符合Opus要求（必须是2.5ms、5ms、10ms、20ms、40ms或60ms的采样数）
      final int samplesPerFrame = (sampleRate * frameDuration) ~/ 1000;

      Uint8List encoded;

      // 处理过短的数据
      if (pcmInt16.length < samplesPerFrame) {
        // 对于过短的数据，可以通过添加静音来填充到所需长度
        final Int16List paddedData = Int16List(samplesPerFrame);
        for (int i = 0; i < pcmInt16.length; i++) {
          paddedData[i] = pcmInt16[i];
        }

        // 编码填充后的数据
        encoded = Uint8List.fromList(_encoder.encode(input: paddedData));
      } else {
        // 对于足够长的数据，裁剪到精确的帧长度
        encoded = Uint8List.fromList(
          _encoder.encode(input: pcmInt16.sublist(0, samplesPerFrame)),
        );
      }

      return encoded;
    } catch (e, stackTrace) {
      logDiagnostic('$_logTag: Opus编码失败: $e');
      logDiagnostic(stackTrace);
      return null;
    }
  }

  /// 检查是否正在录音
  static bool get isRecording => _isRecording;

  /// 检查是否正在播放
  static bool get isPlaying => _isPlaying;
}
