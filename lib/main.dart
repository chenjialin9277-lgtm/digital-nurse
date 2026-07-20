import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:provider/provider.dart';

import 'controllers/nurse_controller.dart';
import 'models/app_usage_record.dart';
import 'repositories/app_usage_repository.dart';
import 'screens/nurse_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  initOpus(await opus_flutter.load());

  final controller = NurseController();
  // 必须在首页可交互前完成本地配置读取和旧版宣教迁移，
  // 否则用户快速点击会用默认值覆盖旧版科室自定义内容。
  await controller.initializeLocalState();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const DigitalNurseApp(),
    ),
  );
  unawaited(AppUsageRepository().record(AppUsageType.appLaunch));
  // 小智网络绑定和连接在首屏后继续，不延长本地首屏等待。
  unawaited(controller.initialize());
}

class DigitalNurseApp extends StatelessWidget {
  const DigitalNurseApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F8C),
      brightness: Brightness.light,
      surface: const Color(0xFFF4FAFA),
    );

    return MaterialApp(
      title: '数字护士',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4FAFA),
        fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
      ),
      home: home ?? const NurseScreen(),
    );
  }
}
