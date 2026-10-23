import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nurse_app_config.dart';

class NurseConfigRepository {
  static const _configKey = 'digital_nurse_config_v1';
  static const _tokenKey = 'digital_nurse_xiaozhi_token';
  static const _passwordKey = 'digital_nurse_settings_password';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<NurseAppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final hadStartupSubtitle =
          (decoded['startupSubtitle'] as String?)?.trim().isNotEmpty == true;
      final saved = NurseAppConfig.fromJson(decoded);
      final secureToken = await _secureStorage.read(key: _tokenKey);
      final securePassword = await _secureStorage.read(key: _passwordKey);
      var migrated = saved.copyWith(
        token: secureToken ?? saved.token,
        settingsPassword:
            securePassword ?? NurseAppConfig.defaultSettingsPassword,
      );
      if (migrated.hospitalName == 'XX医院') {
        migrated = migrated.copyWith(
          hospitalName: NurseAppConfig.defaultHospitalName,
        );
      }
      if (migrated.wardName == 'XX病区') {
        migrated = migrated.copyWith(wardName: NurseAppConfig.defaultWardName);
      }
      if (!hadStartupSubtitle) {
        migrated = migrated.copyWith(
          startupSubtitle: NurseAppConfig.defaultStartupSubtitle(
            migrated.hospitalName,
            migrated.wardName,
          ),
        );
      }
      if (migrated.deviceId.isEmpty) {
        migrated = migrated.copyWith(deviceId: _generateDeviceId());
      }
      if (migrated.clientId.isEmpty) {
        migrated = migrated.copyWith(clientId: _generateClientId());
      }
      await save(migrated);
      return migrated;
    }

    final config = NurseAppConfig.defaults(
      _generateDeviceId(),
      _generateClientId(),
    );
    await save(config);
    return config;
  }

  Future<void> save(NurseAppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _tokenKey, value: config.token);
    await _secureStorage.write(
      key: _passwordKey,
      value: config.settingsPassword,
    );
    final withoutToken = config.copyWith(
      token: '',
      settingsPassword: NurseAppConfig.defaultSettingsPassword,
    );
    await prefs.setString(_configKey, jsonEncode(withoutToken.toJson()));
  }

  NurseAppConfig withFreshDeviceIdentity(NurseAppConfig config) {
    return config.copyWith(
      officialPlatform: true,
      websocketUrl: '',
      deviceId: _generateDeviceId(),
      clientId: _generateClientId(),
      token: '',
      protocolVersion: 1,
      departmentConfigured: true,
    );
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(6, (_) => random.nextInt(256));
    // 本地管理、单播 MAC，避免与平板或 ESP32 的真实硬件地址冲突。
    bytes[0] = (bytes[0] & 0xFC) | 0x02;
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  String _generateClientId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
