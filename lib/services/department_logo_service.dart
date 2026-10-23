import 'package:flutter/services.dart';

class DepartmentLogoService {
  const DepartmentLogoService();

  static const _channel = MethodChannel('digital_nurse/system');

  Future<String?> pickLogo() {
    return _channel.invokeMethod<String>('pickDepartmentLogo');
  }
}
