import 'package:flutter/services.dart';

class NurseAvatarImageService {
  const NurseAvatarImageService();

  static const _channel = MethodChannel('digital_nurse/system');

  Future<String?> pickStandardAvatar() {
    return _channel.invokeMethod<String>('pickNurseAvatar');
  }
}
