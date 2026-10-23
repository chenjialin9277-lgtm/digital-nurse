import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/offline_speech_language.dart';
import '../../../services/local_speech_service.dart';
import '../../../services/education_video_service.dart';
import '../../../theme/nurse_theme.dart';
import '../controllers/education_session_controller.dart';
import '../models/education_item.dart';
import 'education_playback_screen.dart';
import '../widgets/daily_language_selector.dart';
import '../widgets/education_catalog.dart';

class BedsideEducationScreen extends StatefulWidget {
  const BedsideEducationScreen({
    super.key,
    required this.items,
    required this.session,
    required this.departmentName,
    this.nurseAvatarPath = '',
    this.onOfflinePlaybackStarting,
    this.onOfflinePlaybackEnded,
    this.onLanguageChanged,
    this.videoService = const EducationVideoService(),
  });

  final List<EducationItem> items;
  final EducationSessionController session;
  final String departmentName;
  final String nurseAvatarPath;
  final Future<void> Function()? onOfflinePlaybackStarting;
  final Future<void> Function()? onOfflinePlaybackEnded;
  final ValueChanged<OfflineSpeechLanguage>? onLanguageChanged;
  final EducationVideoService videoService;

  @override
  State<BedsideEducationScreen> createState() => _BedsideEducationScreenState();
}

class _BedsideEducationScreenState extends State<BedsideEducationScreen> {
  late OfflineSpeechLanguage _language;
  final List<String> _recentItemIds = [];
  bool _switchingLanguage = false;
  bool _selectingItem = false;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _language = widget.session.state.language;
  }

  @override
  void dispose() {
    _operationGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NursePalette.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.session.clearTransientState();
      },
      child: Scaffold(
        body: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.backgroundStart, palette.backgroundEnd],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkbenchHeader(
                    departmentName: widget.departmentName,
                    language: _language,
                    switchingLanguage: _switchingLanguage,
                    onBack: () async {
                      _operationGeneration++;
                      await widget.session.clearTransientState();
                      if (mounted) {
                        setState(() {
                          _switchingLanguage = false;
                          _selectingItem = false;
                        });
                      }
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                    onLanguageChanged: _changeLanguage,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 0),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: palette.border),
                        boxShadow: [
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: EducationCatalog(
                        items: widget.items,
                        language: _language,
                        recentItemIds: _recentItemIds,
                        onSelected: _selectItem,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeLanguage(OfflineSpeechLanguage language) async {
    if (_switchingLanguage || language == _language) return;
    final generation = ++_operationGeneration;
    setState(() => _switchingLanguage = true);
    await widget.session.clearTransientState();
    if (!mounted || generation != _operationGeneration) {
      if (mounted) setState(() => _switchingLanguage = false);
      return;
    }
    await widget.session.startSession(language);
    if (!mounted || generation != _operationGeneration) {
      await widget.session.clearTransientState();
      return;
    }
    widget.onLanguageChanged?.call(language);
    setState(() {
      _language = language;
      _switchingLanguage = false;
    });
  }

  Future<void> _selectItem(EducationItem item) async {
    if (_selectingItem || _switchingLanguage) return;
    if (!item.isAvailableIn(_language)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              item.isVideo
                  ? '${item.category}：视频文件不可用，请联系管理员'
                  : '${item.category}：该语言暂未提供',
            ),
          ),
        );
      return;
    }
    setState(() => _selectingItem = true);
    try {
      _recentItemIds
        ..remove(item.id)
        ..insert(0, item.id);
      if (item.isVideo) {
        await _playVideoItem(item);
        return;
      }
      if (widget.session.state.stage == EducationSessionStage.idle) {
        await widget.session.startSession(_language);
      }
      await widget.session.selectItem(item);
      if (!mounted) {
        await widget.session.clearTransientState();
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder:
              (_) => Theme(
                data: Theme.of(context),
                child: EducationPlaybackScreen(
                  session: widget.session,
                  speech: const LocalSpeechService(),
                  departmentName: widget.departmentName,
                  nurseAvatarPath: widget.nurseAvatarPath,
                  onOfflinePlaybackStarting: widget.onOfflinePlaybackStarting,
                  onOfflinePlaybackEnded: widget.onOfflinePlaybackEnded,
                  onLanguageChanged: (language) {
                    if (mounted) setState(() => _language = language);
                    widget.onLanguageChanged?.call(language);
                  },
                ),
              ),
        ),
      );
    } finally {
      if (mounted) setState(() => _selectingItem = false);
    }
  }

  Future<void> _playVideoItem(EducationItem item) async {
    var suspended = false;
    try {
      if (widget.session.state.stage == EducationSessionStage.idle) {
        await widget.session.startSession(_language);
      }
      await widget.session.recordVideoSelected(item);
      await widget.session.recordVideoPlaybackStarted(item);
      await widget.onOfflinePlaybackStarting?.call();
      suspended = true;
      final completed = await widget.videoService.playVideo(
        path: item.videoPath,
        title: item.videoTitle,
      );
      if (completed) {
        await widget.session.recordVideoPlaybackCompleted(item);
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message ?? '视频播放失败')));
    } finally {
      if (suspended) await widget.onOfflinePlaybackEnded?.call();
    }
  }
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.departmentName,
    required this.language,
    required this.switchingLanguage,
    required this.onBack,
    required this.onLanguageChanged,
  });

  final String departmentName;
  final OfflineSpeechLanguage language;
  final bool switchingLanguage;
  final VoidCallback onBack;
  final ValueChanged<OfflineSpeechLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1120;
        return Row(
          children: [
            IconButton.filledTonal(
              tooltip: '返回数字护士首页',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '床旁宣教工作台',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NursePalette.of(context).textPrimary,
                      fontSize: compact ? 22 : 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$departmentName · 不记录患者身份信息',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NursePalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            if (switchingLanguage)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            DailyLanguageSelector(
              value: language,
              enabled: !switchingLanguage,
              compact: compact,
              onChanged: onLanguageChanged,
            ),
          ],
        );
      },
    );
  }
}
