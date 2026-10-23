import 'package:flutter/services.dart';

class EducationVideoService {
  const EducationVideoService();

  static const _channel = MethodChannel('digital_nurse/system');

  Future<String?> pickVideo() {
    return _channel.invokeMethod<String>('pickEducationVideo');
  }

  Future<bool> playVideo({required String path, required String title}) async {
    return await _channel.invokeMethod<bool>('playEducationVideo', {
          'path': path,
          'title': title,
        }) ??
        false;
  }

  Future<void> deleteVideo(String path) {
    return _channel.invokeMethod<void>('deleteEducationVideo', {'path': path});
  }
}
