import 'package:digital_nurse/main.dart';
import 'package:digital_nurse/controllers/nurse_controller.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/screens/nurse_screen.dart';
import 'package:digital_nurse/theme/nurse_theme.dart';
import 'package:digital_nurse/widgets/nurse_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('生成新数字护士静态形象预览', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NurseAvatar(
            state: NurseUiState.speaking,
            emotion: 'neutral',
            imagePath: '',
            departmentName: '急诊病房',
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/digital_nurse_v2.png'),
        tester.element(find.byType(NurseAvatar)),
      );
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(NurseAvatar),
      matchesGoldenFile('goldens/avatar_v2_static_preview.png'),
    );
  });

  testWidgets('生成新医院品牌与科室Logo横屏排版预览', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller =
        NurseController()
          ..config = NurseAppConfig.defaults(
            '02:11:22:33:44:55',
            '11111111-2222-4333-8444-555555555555',
          ).copyWith(
            websocketUrl: 'wss://example.invalid/xiaozhi/v1/',
            token: 'test-token',
            visualStyle: NurseVisualStyle.clinicalLight,
          )
          ..state = NurseUiState.idle;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const DigitalNurseApp(home: NurseScreen()),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(NurseScreen));
      await Future.wait([
        precacheImage(
          const AssetImage('assets/images/digital_nurse_v2.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/hospital_brand_full.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/images/emergency_ward_logo_v2.png'),
          context,
        ),
      ]);
    });
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(NurseScreen),
      matchesGoldenFile('goldens/new_brand_layout_preview.png'),
    );
  });
}
