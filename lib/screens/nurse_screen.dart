import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/nurse_controller.dart';
import '../features/education/controllers/education_session_controller.dart';
import '../features/education/models/education_item.dart';
import '../features/education/screens/bedside_education_screen.dart';
import '../features/education/screens/education_playback_screen.dart';
import '../features/education/widgets/daily_language_selector.dart';
import '../models/nurse_app_config.dart';
import '../models/offline_speech_language.dart';
import '../services/education_video_service.dart';
import '../theme/nurse_theme.dart';
import '../widgets/nurse_avatar.dart';
import '../widgets/nurse_config_dialog.dart';
import '../widgets/settings_password_dialog.dart';

class NurseScreen extends StatelessWidget {
  const NurseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NurseController>();
    final palette = NursePalette.forStyle(controller.config.visualStyle);
    return Theme(
      data: palette.createTheme(),
      child: Builder(
        builder:
            (themedContext) => Scaffold(
              body: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.backgroundStart, palette.backgroundEnd],
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (palette.isDark) const _TechBackdrop(),
                      Column(
                        children: [
                          _Header(
                            controller: controller,
                            onSettings:
                                () => _openSettings(themedContext, controller),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final landscape = constraints.maxWidth >= 800;
                                final avatar = _AvatarPanel(
                                  controller: controller,
                                );
                                final interaction = _InteractionPanel(
                                  controller: controller,
                                  onSettings:
                                      () => _openSettings(
                                        themedContext,
                                        controller,
                                      ),
                                  onCallNurse:
                                      () => _showCallNurse(
                                        themedContext,
                                        controller,
                                      ),
                                  onStartBedsideEducation:
                                      () => _openBedsideEducation(
                                        themedContext,
                                        controller,
                                      ),
                                  onStartFavoriteEducation:
                                      (item) => _openFavoriteEducation(
                                        themedContext,
                                        controller,
                                        item,
                                      ),
                                );
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    6,
                                    22,
                                    20,
                                  ),
                                  child:
                                      landscape
                                          ? Row(
                                            children: [
                                              Expanded(flex: 9, child: avatar),
                                              const SizedBox(width: 20),
                                              Expanded(
                                                flex: 11,
                                                child: interaction,
                                              ),
                                            ],
                                          )
                                          : Column(
                                            children: [
                                              Expanded(flex: 8, child: avatar),
                                              const SizedBox(height: 14),
                                              Expanded(
                                                flex: 12,
                                                child: interaction,
                                              ),
                                            ],
                                          ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Future<void> _openSettings(
    BuildContext context,
    NurseController controller,
  ) async {
    final unlocked =
        !controller.config.departmentConfigured
            ? true
            : await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder:
                  (_) => SettingsPasswordDialog(
                    verify: controller.verifySettingsPassword,
                  ),
            );
    if (unlocked != true || !context.mounted) return;
    final updated = await showDialog<NurseAppConfig>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => NurseConfigDialog(
            initial: controller.config,
            onResetBinding: controller.resetOfficialBinding,
            translateEducationFromMandarin:
                controller.translateEducationFromMandarin,
          ),
    );
    if (updated != null) await controller.saveConfig(updated);
    try {
      await controller.loadActiveEducation();
    } catch (_) {
      // The controller exposes the existing emergency education fallback.
    }
  }

  Future<void> _showCallNurse(
    BuildContext context,
    NurseController controller,
  ) async {
    controller.showEscalation();
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: const Icon(
              Icons.notifications_active_outlined,
              size: 44,
              color: Color(0xFFE27A26),
            ),
            title: const Text('请联系责任护士'),
            content: Text(
              controller.config.callNurseText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  child: Text('我知道了'),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _openBedsideEducation(
    BuildContext context,
    NurseController controller,
  ) => _openEducation(context, controller);

  Future<void> _openFavoriteEducation(
    BuildContext context,
    NurseController controller,
    EducationItem item,
  ) =>
      item.isVideo
          ? _openFavoriteVideo(context, controller, item)
          : _openEducation(context, controller, directItem: item);

  Future<void> _openFavoriteVideo(
    BuildContext context,
    NurseController controller,
    EducationItem item,
  ) async {
    final session = controller.createBedsideEducationSession();
    var suspended = false;
    try {
      await session.startSession(controller.config.offlineSpeechLanguage);
      await session.recordVideoSelected(item);
      await session.recordVideoPlaybackStarted(item);
      await controller.suspendOnlineAudioForEducation();
      suspended = true;
      final completed = await const EducationVideoService().playVideo(
        path: item.videoPath,
        title: item.videoTitle,
      );
      if (completed) await session.recordVideoPlaybackCompleted(item);
      await session.finishSession();
    } catch (error) {
      await session.clearTransientState();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('视频宣教暂时无法播放：$error')));
    } finally {
      if (suspended) await controller.resumeOnlineAudioAfterEducation();
    }
  }

  Future<void> _openEducation(
    BuildContext context,
    NurseController controller, {
    EducationItem? directItem,
  }) async {
    EducationSessionController? session;
    var routeTakenOwnership = false;
    try {
      final items =
          directItem == null
              ? await controller.loadActiveEducation()
              : controller.activeEducationItems;
      if (!context.mounted) return;
      if (directItem == null && items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前科室还没有可用的宣教内容')));
        return;
      }
      final createdSession = controller.createBedsideEducationSession();
      session = createdSession;
      await createdSession.startSession(
        controller.config.offlineSpeechLanguage,
      );
      if (directItem != null) await createdSession.selectItem(directItem);
      if (!context.mounted) {
        return;
      }
      final palette = NursePalette.forStyle(controller.config.visualStyle);
      final educationScreen =
          directItem == null
              ? BedsideEducationScreen(
                items: items,
                session: createdSession,
                departmentName: controller.config.wardName,
                nurseAvatarPath: controller.config.nurseAvatarPath,
                onOfflinePlaybackStarting:
                    controller.suspendOnlineAudioForEducation,
                onOfflinePlaybackEnded:
                    controller.resumeOnlineAudioAfterEducation,
                onLanguageChanged:
                    (language) => unawaited(
                      controller.selectOfflineSpeechLanguage(language),
                    ),
              )
              : EducationPlaybackScreen(
                session: createdSession,
                speech: controller.localSpeechService,
                departmentName: controller.config.wardName,
                nurseAvatarPath: controller.config.nurseAvatarPath,
                autoStart: true,
                onOfflinePlaybackStarting:
                    controller.suspendOnlineAudioForEducation,
                onOfflinePlaybackEnded:
                    controller.resumeOnlineAudioAfterEducation,
                onLanguageChanged:
                    (language) => unawaited(
                      controller.selectOfflineSpeechLanguage(language),
                    ),
              );
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder:
              (_) => Theme(data: palette.createTheme(), child: educationScreen),
        ),
      );
      routeTakenOwnership = true;
    } catch (error) {
      if (!context.mounted) return;
      final target = directItem == null ? '宣教工作台' : '宣教';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$target暂时无法打开：$error')));
    } finally {
      if (session != null && !routeTakenOwnership) {
        try {
          await session.clearTransientState();
        } catch (_) {
          // Cleanup is best-effort if the local event store is also failing.
        }
      }
    }
  }
}

class _TechBackdrop extends StatelessWidget {
  const _TechBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(child: CustomPaint(painter: _TechGridPainter())),
    );
  }
}

class _TechGridPainter extends CustomPainter {
  const _TechGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid =
        Paint()
          ..color = const Color(0x1415C9D8)
          ..strokeWidth = 1;
    const step = 54.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final glow =
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x2615C9D8), Color(0x0015C9D8)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.82, size.height * 0.16),
              radius: size.shortestSide * 0.42,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.16),
      size.shortestSide * 0.42,
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _TechGridPainter oldDelegate) => false;
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onSettings});

  final NurseController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        final brandWidth = compact ? 365.0 : 470.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 16, 7),
          child: Row(
            children: [
              SizedBox(
                width: brandWidth,
                height: 72,
                child: Image.asset(
                  'assets/images/hospital_brand_full.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.high,
                  semanticLabel: controller.config.hospitalName,
                ),
              ),
              Container(
                width: 1,
                height: 46,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: palette.border,
              ),
              SizedBox(
                width: 58,
                height: 58,
                child: _DepartmentLogo(config: controller.config),
              ),
              const SizedBox(width: 12),
              if (!compact)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.config.wardName,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '数字护士',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              _StatusPill(controller: controller),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '设置',
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.controller});

  final NurseController controller;

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    final color = switch (controller.state) {
      NurseUiState.idle || NurseUiState.speaking => const Color(0xFF168A72),
      NurseUiState.listening ||
      NurseUiState.thinking => const Color(0xFF5F6ED6),
      NurseUiState.warning => const Color(0xFFE27A26),
      NurseUiState.reconnecting => palette.accent,
      NurseUiState.error || NurseUiState.offline => const Color(0xFFB44C4C),
      _ => const Color(0xFF738487),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            controller.statusLabel,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AvatarPanel extends StatelessWidget {
  const _AvatarPanel({required this.controller});

  final NurseController controller;

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: NurseAvatar(
                state: controller.state,
                emotion: controller.emotion,
                imagePath: controller.config.nurseAvatarPath,
                departmentName: controller.config.wardName,
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                _avatarPrompt(controller.state),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _avatarPrompt(NurseUiState state) => switch (state) {
    NurseUiState.listening => '请慢慢说，我正在听',
    NurseUiState.thinking => '正在从病区知识库中查找',
    NurseUiState.speaking => '正在为您讲解',
    NurseUiState.warning => '需要时请立即联系责任护士',
    NurseUiState.setupRequired => '首次使用请先完成科室配置',
    NurseUiState.activationRequired => '请在小智控制台输入屏幕激活码',
    NurseUiState.reconnecting => '连接波动，正在后台自动恢复',
    NurseUiState.offline => '正在等待网络恢复，字幕内容已保留',
    NurseUiState.error => '请检查设置或网络连接',
    _ => '点击常见问题，或按住话筒提问',
  };
}

class _InteractionPanel extends StatelessWidget {
  const _InteractionPanel({
    required this.controller,
    required this.onSettings,
    required this.onCallNurse,
    required this.onStartBedsideEducation,
    required this.onStartFavoriteEducation,
  });

  final NurseController controller;
  final VoidCallback onSettings;
  final VoidCallback onCallNurse;
  final Future<void> Function() onStartBedsideEducation;
  final Future<void> Function(EducationItem) onStartFavoriteEducation;

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.state == NurseUiState.setupRequired)
            _SetupBanner(onSettings: onSettings),
          if (controller.state == NurseUiState.activationRequired)
            _ActivationBanner(controller: controller),
          if (controller.userText.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '您问：${controller.userText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: _TranscriptView(
              text: controller.assistantText,
              errorMessage: controller.errorMessage,
              isFollowingVoice: controller.state == NurseUiState.speaking,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                controller.educationFallbackActive ? '宣教库异常，已启用旧版应急宣教' : '常用宣教',
                style: TextStyle(
                  color:
                      controller.educationFallbackActive
                          ? const Color(0xFFB65F22)
                          : palette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              if (!controller.educationFallbackActive)
                _BedsideLaunchButton(onPressed: onStartBedsideEducation),
              const Spacer(),
              DailyLanguageSelector(
                value: controller.config.offlineSpeechLanguage,
                compact: true,
                onChanged:
                    (language) => unawaited(
                      controller.selectOfflineSpeechLanguage(language),
                    ),
              ),
            ],
          ),
          if (controller.educationFallbackActive) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: controller.config.quickAnswers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = controller.config.quickAnswers[index];
                  return ActionChip(
                    avatar: const Icon(Icons.volume_up_outlined, size: 18),
                    label: Text(
                      item.titleFor(controller.config.offlineSpeechLanguage),
                    ),
                    onPressed:
                        () => unawaited(controller.playLocalQuickAnswer(item)),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            _FavoriteEducationStrip(
              items: controller.favoriteEducationItems,
              language: controller.config.offlineSpeechLanguage,
              onSelected: onStartFavoriteEducation,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _PushToTalkButton(controller: controller)),
              const SizedBox(width: 12),
              SizedBox(
                height: 64,
                child: OutlinedButton.icon(
                  onPressed: onCallNurse,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text(
                    '联系护士',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB65F22),
                    side: const BorderSide(color: Color(0xFFE8B28B)),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '数字护士仅提供通用宣教信息，不能替代医护人员进行诊断和个体化处置。',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TranscriptView extends StatefulWidget {
  const _TranscriptView({
    required this.text,
    required this.errorMessage,
    required this.isFollowingVoice,
  });

  final String text;
  final String? errorMessage;
  final bool isFollowingVoice;

  @override
  State<_TranscriptView> createState() => _TranscriptViewState();
}

class _FavoriteEducationStrip extends StatefulWidget {
  const _FavoriteEducationStrip({
    required this.items,
    required this.language,
    required this.onSelected,
  });

  final List<EducationItem> items;
  final OfflineSpeechLanguage language;
  final Future<void> Function(EducationItem) onSelected;

  @override
  State<_FavoriteEducationStrip> createState() =>
      _FavoriteEducationStripState();
}

class _FavoriteEducationStripState extends State<_FavoriteEducationStrip> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox(
        height: 50,
        child: Align(alignment: Alignment.centerLeft, child: Text('暂无常用宣教')),
      );
    }
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final available = item.isAvailableIn(widget.language);
          final currentTitle = item.titleFor(widget.language);
          final fallbackTitle =
              item.isVideo
                  ? '视频宣教'
                  : item.contents.values
                      .map((content) => content.title.trim())
                      .firstWhere(
                        (title) => title.isNotEmpty,
                        orElse: () => '宣教项目',
                      );
          final title = currentTitle.isEmpty ? fallbackTitle : currentTitle;
          return OutlinedButton.icon(
            key: ValueKey('favorite-education-${item.id}'),
            onPressed:
                !available || _opening ? null : () => _openFavorite(item),
            icon: Icon(
              available
                  ? item.isVideo
                      ? Icons.play_circle_outline
                      : Icons.volume_up_outlined
                  : Icons.block_outlined,
              size: 18,
            ),
            label:
                available
                    ? Text(title)
                    : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text('该语言暂未提供', style: TextStyle(fontSize: 11)),
                      ],
                    ),
          );
        },
      ),
    );
  }

  Future<void> _openFavorite(EducationItem item) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onSelected(item);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

class _BedsideLaunchButton extends StatefulWidget {
  const _BedsideLaunchButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_BedsideLaunchButton> createState() => _BedsideLaunchButtonState();
}

class _BedsideLaunchButtonState extends State<_BedsideLaunchButton> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _opening ? null : _open,
      icon:
          _opening
              ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
              : const Icon(Icons.medical_information_outlined, size: 18),
      label: Text(_opening ? '正在打开' : '更多宣教'),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

class _TranscriptViewState extends State<_TranscriptView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    }
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    final displayText =
        widget.errorMessage ??
        (widget.text.isEmpty ? '正在组织回答，请稍候…' : widget.text);
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.72)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 9),
            decoration: BoxDecoration(
              color: palette.primary.withValues(
                alpha: palette.isDark ? 0.10 : 0.06,
              ),
              border: Border(
                bottom: BorderSide(
                  color: palette.border.withValues(alpha: 0.65),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.closed_caption_outlined,
                  size: 19,
                  color: palette.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '实时字幕',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (widget.isFollowingVoice) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: palette.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  widget.isFollowingVoice ? '跟随语音逐字显示' : '可上下滑动查看',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 16, 24, 34),
                child: SelectableText(
                  displayText,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.65,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color:
                        widget.errorMessage == null
                            ? palette.textPrimary
                            : const Color(0xFFE06A6A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB65F22)),
          const SizedBox(width: 10),
          const Expanded(child: Text('首次使用请先设置科室名称和科室Logo，再绑定本科室的小智AI账号。')),
          FilledButton.tonal(onPressed: onSettings, child: const Text('立即配置')),
        ],
      ),
    );
  }
}

class _DepartmentLogo extends StatelessWidget {
  const _DepartmentLogo({required this.config});

  final NurseAppConfig config;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'assets/images/emergency_ward_logo_v2.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '${config.wardName}科室标志',
    );
    final path = config.departmentLogoPath.trim();
    if (path.isEmpty) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '${config.wardName}科室标志',
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _ActivationBanner extends StatelessWidget {
  const _ActivationBanner({required this.controller});

  final NurseController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB9D9F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phonelink_lock_outlined, color: Color(0xFF266C9B)),
          const SizedBox(width: 10),
          const Text('设备激活码', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          SelectableText(
            controller.activationCode ?? '正在获取',
            style: const TextStyle(
              color: Color(0xFF155A89),
              fontSize: 24,
              letterSpacing: 3,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: controller.openOfficialConsole,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('打开小智控制台'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: controller.provisionOfficialPlatform,
            icon: const Icon(Icons.refresh),
            label: const Text('重新获取'),
          ),
        ],
      ),
    );
  }
}

class _PushToTalkButton extends StatelessWidget {
  const _PushToTalkButton({required this.controller});

  final NurseController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.isPressingToTalk;
    final palette = NursePalette.of(context);
    final buttonColor = active ? palette.accent : palette.primary;
    return Semantics(
      button: true,
      label: active ? '松开发送' : '按住说话',
      child: GestureDetector(
        onTapDown:
            controller.canInteract
                ? (_) => unawaited(controller.startPushToTalk())
                : null,
        onTapUp:
            controller.canInteract
                ? (_) => unawaited(controller.stopPushToTalk())
                : null,
        onTapCancel:
            controller.canInteract
                ? () => unawaited(controller.stopPushToTalk())
                : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 64,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: buttonColor.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.graphic_eq : Icons.mic_none_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                active ? '正在聆听，松开发送' : '按住说话',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
