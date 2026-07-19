import 'package:digital_nurse/features/education/widgets/education_management_dialog.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/widgets/nurse_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'education_widget_harness.dart';
import 'fake_education_repository.dart';

void main() {
  testWidgets('管理员可新增宣教并仅发布普通话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增宣教'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('education-title-mandarin')),
      '骨科术后活动',
    );
    await tester.enterText(
      find.byKey(const Key('education-body-mandarin')),
      '请在护士指导下活动。',
    );
    await fillKnowledgeQuestion(tester);
    await tester.tap(find.text('保存并发布普通话'));
    await tester.pumpAndSettle();

    final saved = (await repository.loadAll()).single;
    expect(saved.isAvailableIn(OfflineSpeechLanguage.mandarin), isTrue);
    expect(saved.isAvailableIn(OfflineSpeechLanguage.cantonese), isFalse);
    expect(saved.isAvailableIn(OfflineSpeechLanguage.english), isFalse);
    expect(find.text('骨科术后活动'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停用的宣教仍在管理端可见并可重新启用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    await repository.replaceAll([reviewedItem.copyWith(enabled: false)]);

    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('入院注意事项'), findsOneWidget);
    await tester.tap(find.byKey(const Key('education-enabled-admission')));
    await tester.pumpAndSettle();

    expect((await repository.loadActive()).single.enabled, isTrue);
  });

  testWidgets('设置页通过独立管理入口打开科室宣教', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    final config = NurseAppConfig.defaults(
      'device',
      'client',
    ).copyWith(departmentConfigured: true);

    await tester.pumpWidget(
      educationTestApp(
        NurseConfigDialog(initial: config, educationRepository: repository),
      ),
    );
    final entry = find.text('管理本科室宣教内容');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('本科室宣教内容'), findsOneWidget);
    expect(find.text('入院注意事项'), findsOneWidget);
  });

  testWidgets('删除中间项后复制的宣教仍保持唯一且稳定的末尾排序', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    await repository.replaceAll([
      educationFixture(id: 'a', sortOrder: 0),
      educationFixture(id: 'middle', sortOrder: 1),
      educationFixture(id: 'c', sortOrder: 2),
    ]);
    await repository.softDelete('middle');

    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();
    final firstCard = find.byKey(const ValueKey('education-card-a'));
    await tester.tap(
      find.descendant(of: firstCard, matching: find.byTooltip('复制')),
    );
    await tester.pumpAndSettle();

    final items = await repository.loadAll();
    final sortOrders = items.map((item) => item.sortOrder).toList();
    expect(sortOrders.toSet(), hasLength(items.length));
    expect(sortOrders.reduce((left, right) => left > right ? left : right), 3);
  });

  testWidgets('软删除的宣教重开管理页不会复活', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    await repository.replaceAll([educationFixture(id: 'delete-me')]);

    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('education-card-delete-me'));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('删除')));
    await tester.pumpAndSettle();

    expect(await repository.loadAll(), isEmpty);
  });
}
