import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/nurse_app_config.dart';

class XiaozhiProvisioningResult {
  const XiaozhiProvisioningResult({
    this.websocketUrl,
    this.token,
    this.protocolVersion = 1,
    this.activationCode,
    this.activationMessage,
    this.activationTimeout = const Duration(minutes: 10),
  });

  final String? websocketUrl;
  final String? token;
  final int protocolVersion;
  final String? activationCode;
  final String? activationMessage;
  final Duration activationTimeout;

  bool get hasWebsocketConfig =>
      (websocketUrl?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);
  bool get requiresActivation => activationCode?.isNotEmpty ?? false;
}

enum XiaozhiActivationStatus { waiting, activated }

/// Implements the activation flow used by the official xiaozhi-esp32 firmware.
class XiaozhiProvisioningService {
  const XiaozhiProvisioningService();

  Future<XiaozhiProvisioningResult> check(NurseAppConfig config) async {
    final response = await _post(
      config,
      Uri.parse(config.otaUrl),
      _systemInfo(config),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw XiaozhiProvisioningException('官方配置服务返回 ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const XiaozhiProvisioningException('官方配置数据格式不正确');
    }

    final websocket = body['websocket'];
    final activation = body['activation'];
    final ws = websocket is Map ? Map<String, dynamic>.from(websocket) : null;
    final act =
        activation is Map ? Map<String, dynamic>.from(activation) : null;

    return XiaozhiProvisioningResult(
      websocketUrl: ws?['url']?.toString(),
      token: ws?['token']?.toString(),
      protocolVersion: _asInt(ws?['version']) ?? 1,
      activationCode: act?['code']?.toString(),
      activationMessage: act?['message']?.toString(),
      activationTimeout: Duration(
        milliseconds: _asInt(act?['timeout_ms']) ?? 600000,
      ),
    );
  }

  Future<XiaozhiActivationStatus> activate(NurseAppConfig config) async {
    final base =
        config.otaUrl.endsWith('/') ? config.otaUrl : '${config.otaUrl}/';
    final response = await _post(
      config,
      Uri.parse('${base}activate'),
      const {},
    );
    if (response.statusCode == HttpStatus.accepted) {
      return XiaozhiActivationStatus.waiting;
    }
    if (response.statusCode == HttpStatus.ok) {
      return XiaozhiActivationStatus.activated;
    }
    throw XiaozhiProvisioningException('设备激活检查返回 ${response.statusCode}');
  }

  Future<_HttpResult> _post(
    NurseAppConfig config,
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set('Activation-Version', '1')
        ..set('Device-Id', config.deviceId)
        ..set('Client-Id', config.clientId)
        ..set(HttpHeaders.userAgentHeader, 'digital-nurse-android/0.2.0')
        ..set(HttpHeaders.acceptLanguageHeader, 'zh-CN')
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await utf8.decoder.bind(response).join();
      return _HttpResult(response.statusCode, responseBody);
    } on SocketException {
      throw const XiaozhiProvisioningException('无法连接小智官方平台，请检查网络');
    } on TimeoutException {
      throw const XiaozhiProvisioningException('连接小智官方平台超时，请稍后重试');
    } on HandshakeException {
      throw const XiaozhiProvisioningException('与小智官方平台的安全连接失败');
    } on FormatException {
      throw const XiaozhiProvisioningException('小智官方平台返回了无法识别的数据');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _systemInfo(NurseAppConfig config) => {
    'version': 2,
    'language': 'zh-CN',
    'mac_address': config.deviceId,
    'uuid': config.clientId,
    'chip_model_name': 'android',
    'application': {'name': 'digital-nurse-android', 'version': '0.2.0'},
    'board': {
      'type': 'android-tablet',
      'name': 'Xiaomi Pad 6 Max 14',
      'screen_width': 2880,
      'screen_height': 1800,
    },
  };

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class XiaozhiProvisioningException implements Exception {
  const XiaozhiProvisioningException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
