import 'package:digital_nurse/features/education/widgets/education_management_dialog.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_language_content.dart';
import 'package:digital_nurse/features/education/services/education_translation_service.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:digital_nurse/models/nurse_app_config.dart';
import 'package:digital_nurse/services/education_video_service.dart';
import 'package:digital_nurse/widgets/nurse_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'education_test_fixtures.dart';
import 'education_widget_harness.dart';
import 'fake_education_repository.dart';

void main() {
  testWidgets('宣教库读取失败后重试成功会清除错误页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _RetryEducationRepository();
    await repository.replaceAll([reviewedItem]);
    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取本科室宣教内容'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('无法读取本科室宣教内容'), findsNothing);
    expect(find.text('入院注意事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('管理员可新增宣教并仅发布普通话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    await tester.pumpWidget(
      educationTestApp(EducationManagementDialog(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增文字宣教'));
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

  testWidgets('管理员可单独新增本地视频宣教', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    final videos = _FakeEducationVideoService();
    await tester.pumpWidget(
      educationTestApp(
        EducationManagementDialog(repository: repository, videoService: videos),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增视频宣教'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('video-education-title')),
      '出院后换药操作示范',
    );
    await tester.tap(find.byKey(const Key('pick-video-education-file')));
    await tester.pump();
    await tester.tap(find.text('保存视频宣教'));
    await tester.pumpAndSettle();

    final saved = (await repository.loadAll()).single;
    expect(saved.isVideo, isTrue);
    expect(saved.videoTitle, '出院后换药操作示范');
    expect(saved.videoPath, '/app/education_videos/discharge.mp4');
    expect(saved.contents, isEmpty);
    expect(find.text('视频宣教'), findsWidgets);
  });

  testWidgets('管理员可从普通话同步生成粤语和英语待复核草稿', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeEducationRepository();
    var translateCount = 0;
    const translatedCantonese = EducationLanguageContent(
      title: '出院食药',
      body: '请跟医嘱食药。',
      summary: '',
      question: '应该点食药？',
      options: ['跟医嘱', '自己加量'],
      correctIndex: 0,
      explanation: '跟医嘱比较安全。',
      published: false,
      needsReview: true,
    );
    const translatedEnglish = EducationLanguageContent(
      title: 'Discharge medication',
      body: 'Take your medicine as prescribed.',
      summary: '',
      question: 'How should you take it?',
      options: ['As prescribed', 'Increase it yourself'],
      correctIndex: 0,
      explanation: 'Following the prescription is safer.',
      published: false,
      needsReview: true,
    );
    await tester.pumpWidget(
      educationTestApp(
        EducationManagementDialog(
          repository: repository,
          translateFromMandarin: (source) async {
            translateCount++;
            expect(source.body, '请按医嘱服药。');
            return const EducationTranslationBundle(
              cantonese: translatedCantonese,
              english: translatedEnglish,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增文字宣教'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('education-title-mandarin')),
      '出院用药',
    );
    await tester.enterText(
      find.byKey(const Key('education-body-mandarin')),
      '请按医嘱服药。',
    );
    await fillKnowledgeQuestion(tester);
    await tester.tap(
      find.byKey(const Key('translate-education-from-mandarin')),
    );
    await tester.pumpAndSettle();

    expect(translateCount, 1);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('education-title-cantonese')),
          )
          .controller!
          .text,
      '出院食药',
    );
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();

    final saved = (await repository.loadAll()).single;
    expect(
      saved.contentFor(OfflineSpeechLanguage.english).title,
      'Discharge medication',
    );
    expect(saved.isAvailableIn(OfflineSpeechLanguage.cantonese), isFalse);
    expect(saved.isAvailableIn(OfflineSpeechLanguage.english), isFalse);
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

class _FakeEducationVideoService extends EducationVideoService {
  @override
  Future<String?> pickVideo() async => '/app/education_videos/discharge.mp4';

  @override
  Future<bool> playVideo({required String path, required String title}) async =>
      true;

  @override
  Future<void> deleteVideo(String path) async {}
}

class _RetryEducationRepository extends FakeEducationRepository {
  bool _failed = false;

  @override
  Future<List<EducationItem>> loadAll() async {
    if (!_failed) {
      _failed = true;
      throw StateError('temporary database failure');
    }
    return super.loadAll();
  }
}
