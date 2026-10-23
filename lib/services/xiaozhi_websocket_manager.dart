import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
// 尝试导入io.dart，但在web平台会抛出异常
import 'package:web_socket_channel/io.dart'
    if (dart.library.html) 'package:web_socket_channel/html.dart';

import '../utils/diagnostic_log.dart';

/// 小智WebSocket事件类型
enum XiaozhiEventType { connected, disconnected, message, error, binaryMessage }

/// 小智WebSocket事件
class XiaozhiEvent {
  final XiaozhiEventType type;
  final dynamic data;

  XiaozhiEvent({required this.type, this.data});
}

/// 小智WebSocket监听器接口
typedef XiaozhiWebSocketListener = void Function(XiaozhiEvent event);

/// 小智WebSocket管理器
class XiaozhiWebSocketManager {
  static const String _logTag = "XiaozhiWebSocket";

  WebSocketChannel? _channel;
  String? _serverUrl;
  final String? _deviceId;
  final String _clientId;
  final int _protocolVersion;
  String? _token;
  final bool _enableToken;

  final List<XiaozhiWebSocketListener> _listeners = [];
  bool _shouldReconnect = false;
  bool _isConnecting = false;
  bool _socketReady = false;
  bool _lossHandled = false;
  int _reconnectAttempts = 0;
  int _connectionGeneration = 0;
  Timer? _reconnectTimer;
  StreamSubscription? _streamSubscription;

  /// 构造函数
  XiaozhiWebSocketManager({
    required String deviceId,
    required String clientId,
    int protocolVersion = 1,
    bool enableToken = false,
  }) : _deviceId = deviceId,
       _clientId = clientId,
       _protocolVersion = protocolVersion,
       _enableToken = enableToken;

  /// 添加事件监听器
  void addListener(XiaozhiWebSocketListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiWebSocketListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiEvent event) {
    for (final listener in List<XiaozhiWebSocketListener>.of(_listeners)) {
      listener(event);
    }
  }

  /// 连接到WebSocket服务器
  Future<void> connect(String url, String token) async {
    if (url.isEmpty) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: "WebSocket地址不能为空"),
      );
      return;
    }

    _serverUrl = url;
    _token = token;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    if (isConnected) return;
    await _openConnection();
  }

  /// Called after Wi-Fi/mobile-network recovery or when the app resumes.
  Future<void> ensureConnected() async {
    if (!_shouldReconnect) _shouldReconnect = true;
    if (isConnected || _isConnecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _openConnection();
  }

  Future<void> _openConnection() async {
    if (_isConnecting || !_shouldReconnect) return;
    final url = _serverUrl;
    final token = _token;
    if (url == null || token == null) return;

    _isConnecting = true;
    // Invalidate callbacks from the old socket before closing it. Without this,
    // its onDone callback can schedule a second reconnect while the new socket
    // is already handshaking.
    final generation = ++_connectionGeneration;
    await _closeCurrentConnection();
    _socketReady = false;
    _lossHandled = false;

    try {
      final uri = Uri.parse(url);

      logDiagnostic('$_logTag: 正在连接服务器');
      logDiagnostic('$_logTag: 设备身份已配置');
      logDiagnostic('$_logTag: Token启用: $_enableToken');

      if (_enableToken) logDiagnostic('$_logTag: 已启用Token认证');

      WebSocketChannel channel;
      var usedHandshakeHeaders = false;
      try {
        final headers = <String, dynamic>{
          'Device-Id': _deviceId ?? '',
          'Client-Id': _clientId,
          'Protocol-Version': '$_protocolVersion',
        };

        if (_enableToken && token.isNotEmpty) {
          headers['Authorization'] =
              token.contains(' ') ? token : 'Bearer $token';
        } else {
          headers['Authorization'] = 'Bearer test-token';
        }
        channel = IOWebSocketChannel.connect(
          uri,
          headers: headers,
          // WebSocket pings detect the common tablet case where Wi-Fi remains
          // connected but the route/NAT entry is already dead.
          pingInterval: const Duration(seconds: 20),
          connectTimeout: const Duration(seconds: 12),
        );
        usedHandshakeHeaders = true;
      } catch (e) {
        logDiagnostic('$_logTag: 不支持使用headers方式，回退到基本连接: $e');
        channel = WebSocketChannel.connect(uri);
      }

      _channel = channel;
      _streamSubscription = channel.stream.listen(
        (message) {
          if (generation == _connectionGeneration) _onMessage(message);
        },
        onDone: () {
          if (generation == _connectionGeneration) _onDisconnected();
        },
        onError: (Object error) {
          if (generation == _connectionGeneration) _onError(error);
        },
        cancelOnError: false,
      );

      await channel.ready.timeout(const Duration(seconds: 15));
      if (generation != _connectionGeneration || !_shouldReconnect) return;

      if (!usedHandshakeHeaders) {
        final credential =
            _enableToken && token.isNotEmpty
                ? (token.contains(' ') ? token : 'Bearer $token')
                : 'Bearer test-token';
        channel.sink.add('Authorization: $credential');
        channel.sink.add('Device-ID: $_deviceId');
        channel.sink.add('Client-ID: $_clientId');
      }

      _isConnecting = false;
      _socketReady = true;
      _lossHandled = false;
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.connected, data: null),
      );
      _sendHelloMessage();
      logDiagnostic('$_logTag: 服务器连接完成');
    } catch (e) {
      logDiagnostic('$_logTag: 连接失败: $e');
      if (generation == _connectionGeneration) {
        _handleConnectionLoss(generation, e);
      }
    } finally {
      if (generation == _connectionGeneration) _isConnecting = false;
    }
  }

  /// 断开WebSocket连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connectionGeneration++;
    _isConnecting = false;
    _socketReady = false;
    await _closeCurrentConnection();
    _reconnectAttempts = 0;
  }

  Future<void> _closeCurrentConnection() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    final channel = _channel;
    _channel = null;
    _socketReady = false;
    if (channel != null) {
      await channel.sink.close(status.normalClosure);
      logDiagnostic('$_logTag: 连接已断开');
    }
  }

  /// 发送Hello消息
  void _sendHelloMessage() {
    final hello = {
      "type": "hello",
      "version": _protocolVersion,
      "transport": "websocket",
      "audio_params": {
        "format": "opus",
        "sample_rate": 16000,
        "channels": 1,
        "frame_duration": 60,
      },
    };

    sendMessage(jsonEncode(hello));
  }

  /// 发送文本消息
  void sendMessage(String message) {
    if (_channel != null && isConnected) {
      try {
        _channel!.sink.add(message);
      } catch (error) {
        logDiagnostic('$_logTag: 发送文本失败: $error');
        _handleConnectionLoss(_connectionGeneration, error);
      }
    } else {
      logDiagnostic('$_logTag: 发送失败，连接未建立');
    }
  }

  /// 发送二进制数据
  void sendBinaryMessage(List<int> data) {
    if (_channel != null && isConnected) {
      try {
        _channel!.sink.add(_encodeAudioPacket(data));
      } catch (e) {
        logDiagnostic('$_logTag: 二进制数据发送失败: $e');
        _handleConnectionLoss(_connectionGeneration, e);
      }
    } else {
      logDiagnostic('$_logTag: 发送失败，连接未建立');
    }
  }

  /// 发送文本请求
  void sendTextRequest(String text) {
    if (!isConnected) {
      logDiagnostic('$_logTag: 发送失败，连接未建立');
      return;
    }

    try {
      // 构造消息格式，与Java实现保持一致
      final jsonMessage = {
        "type": "listen",
        "state": "detect",
        "text": text,
        "source": "text",
      };

      logDiagnostic('$_logTag: 发送文本请求');
      sendMessage(jsonEncode(jsonMessage));
    } catch (e) {
      logDiagnostic('$_logTag: 发送文本请求失败: $e');
    }
  }

  /// 处理收到的消息
  void _onMessage(dynamic message) {
    _reconnectAttempts = 0;
    if (message is String) {
      // 文本消息
      logDiagnostic('$_logTag: 收到文本消息');
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.message, data: message),
      );
    } else if (message is List<int>) {
      // 二进制消息
      final audio = _decodeAudioPacket(message);
      if (audio == null) return;
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.binaryMessage, data: audio),
      );
    }
  }

  List<int> _encodeAudioPacket(List<int> opus) {
    if (_protocolVersion == 2) {
      final packet = Uint8List(16 + opus.length);
      final header = ByteData.sublistView(packet, 0, 16);
      header
        ..setUint16(0, 2, Endian.big)
        ..setUint16(2, 0, Endian.big)
        ..setUint32(4, 0, Endian.big)
        ..setUint32(
          8,
          DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF,
          Endian.big,
        )
        ..setUint32(12, opus.length, Endian.big);
      packet.setRange(16, packet.length, opus);
      return packet;
    }
    if (_protocolVersion == 3) {
      final packet = Uint8List(4 + opus.length);
      final header = ByteData.sublistView(packet, 0, 4);
      header
        ..setUint8(0, 0)
        ..setUint8(1, 0)
        ..setUint16(2, opus.length, Endian.big);
      packet.setRange(4, packet.length, opus);
      return packet;
    }
    return opus;
  }

  List<int>? _decodeAudioPacket(List<int> packet) {
    if (_protocolVersion == 2) {
      if (packet.length < 16) return null;
      final header = ByteData.sublistView(Uint8List.fromList(packet), 0, 16);
      final size = header.getUint32(12, Endian.big);
      if (size > packet.length - 16) return null;
      return packet.sublist(16, 16 + size);
    }
    if (_protocolVersion == 3) {
      if (packet.length < 4) return null;
      final header = ByteData.sublistView(Uint8List.fromList(packet), 0, 4);
      final size = header.getUint16(2, Endian.big);
      if (size > packet.length - 4) return null;
      return packet.sublist(4, 4 + size);
    }
    return packet;
  }

  /// 处理断开连接事件
  void _onDisconnected() {
    _handleConnectionLoss(_connectionGeneration, null);
  }

  /// 处理错误事件
  void _onError(error) {
    logDiagnostic('$_logTag: 错误: $error');
    _handleConnectionLoss(_connectionGeneration, error);
  }

  void _handleConnectionLoss(int generation, Object? error) {
    if (generation != _connectionGeneration || _lossHandled) return;
    _lossHandled = true;
    _socketReady = false;
    _isConnecting = false;
    logDiagnostic('$_logTag: 连接已断开${error == null ? '' : ': $error'}');
    // A transient transport error and the following onDone represent one loss,
    // so the UI receives one disconnected event instead of repeated warnings.
    _dispatchEvent(
      XiaozhiEvent(
        type: XiaozhiEventType.disconnected,
        data: error?.toString(),
      ),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect ||
        _serverUrl == null ||
        _token == null ||
        (_reconnectTimer?.isActive ?? false)) {
      return;
    }
    const delays = [2, 4, 8, 15, 30];
    final index = _reconnectAttempts.clamp(0, delays.length - 1).toInt();
    final delay = Duration(seconds: delays[index]);
    _reconnectAttempts++;
    logDiagnostic('$_logTag: ${delay.inSeconds} 秒后尝试恢复连接');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _openConnection();
    });
  }

  /// 判断是否已连接
  bool get isConnected {
    return _socketReady &&
        _channel != null &&
        _streamSubscription != null &&
        !_isConnecting;
  }
}
