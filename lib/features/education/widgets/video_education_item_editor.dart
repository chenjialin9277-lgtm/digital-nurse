import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/education_video_service.dart';
import '../models/education_item.dart';

class VideoEducationItemEditor extends StatefulWidget {
  const VideoEducationItemEditor({
    super.key,
    this.initial,
    required this.sortOrder,
    this.videoService = const EducationVideoService(),
  });

  final EducationItem? initial;
  final int sortOrder;
  final EducationVideoService videoService;

  @override
  State<VideoEducationItemEditor> createState() =>
      _VideoEducationItemEditorState();
}

class _VideoEducationItemEditorState extends State<VideoEducationItemEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _minutes;
  late String _videoPath;
  bool _busy = false;
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.videoTitle ?? '');
    _category = TextEditingController(text: initial?.category ?? '视频宣教');
    _minutes = TextEditingController(
      text: (initial?.estimatedManualMinutes ?? 3).toString(),
    );
    _videoPath = initial?.videoPath ?? '';
  }

  @override
  void dispose() {
    final initialPath = widget.initial?.videoPath ?? '';
    if (!_committed && _videoPath.isNotEmpty && _videoPath != initialPath) {
      widget.videoService.deleteVideo(_videoPath).catchError((_) {});
    }
    _title.dispose();
    _category.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName =
        _videoPath.isEmpty
            ? '尚未导入视频'
            : _videoPath.replaceAll('\\', '/').split('/').last;
    return AlertDialog(
      title: Text(widget.initial == null ? '新增视频宣教' : '编辑视频宣教'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('video-education-title'),
                  controller: _title,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '视频宣教名称',
                    hintText: '例如：出院后换药操作示范',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return '请填写视频宣教名称';
                    return text.length > 60 ? '名称不能超过60个字符' : null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _category,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: '分类',
                          hintText: '例如：出院宣教',
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                (value?.trim().isEmpty ?? true)
                                    ? '请填写分类'
                                    : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '预计时长（分钟）',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final number = int.tryParse(value?.trim() ?? '');
                          return number == null || number < 1 || number > 60
                              ? '请填写1～60'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card.outlined(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.ondemand_video_outlined),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '本地视频文件',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (_busy)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                _videoPath.isEmpty
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '视频导入后会复制到APP本地存储，不需要网络。为保证各类安卓平板可播放，请使用MP4（H.264 + AAC）。',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              key: const Key('pick-video-education-file'),
                              onPressed: _busy ? null : _pickVideo,
                              icon: const Icon(Icons.video_file_outlined),
                              label: Text(_videoPath.isEmpty ? '选择视频' : '替换视频'),
                            ),
                            if (_videoPath.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _previewVideo,
                                icon: const Icon(Icons.play_circle_outline),
                                label: const Text('试播'),
                              ),
                            if (_videoPath.isNotEmpty)
                              TextButton.icon(
                                onPressed: _busy ? null : _removeVideo,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('移除'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存视频宣教'),
        ),
      ],
    );
  }

  Future<void> _pickVideo() async {
    setState(() => _busy = true);
    try {
      final path = await widget.videoService.pickVideo();
      if (mounted && path != null && path.trim().isNotEmpty) {
        final previous = _videoPath;
        setState(() => _videoPath = path);
        if (previous.isNotEmpty &&
            previous != (widget.initial?.videoPath ?? '')) {
          await widget.videoService.deleteVideo(previous).catchError((_) {});
        }
      }
    } on PlatformException catch (error) {
      _showError(error.message ?? '视频导入失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewVideo() async {
    setState(() => _busy = true);
    try {
      await widget.videoService.playVideo(
        path: _videoPath,
        title: _title.text.trim().isEmpty ? '视频宣教试播' : _title.text.trim(),
      );
    } on PlatformException catch (error) {
      _showError(error.message ?? '视频播放失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    if (_videoPath.isEmpty) {
      _showError('请先选择要播放的视频');
      return;
    }
    final initial = widget.initial;
    final now = DateTime.now().toUtc();
    _committed = true;
    Navigator.pop(
      context,
      EducationItem(
        id: initial?.id ?? 'video_education_${now.microsecondsSinceEpoch}',
        category: _category.text.trim(),
        contents: const {},
        estimatedManualMinutes: int.parse(_minutes.text.trim()),
        sortOrder: initial?.sortOrder ?? widget.sortOrder,
        favorite: initial?.favorite ?? false,
        enabled: initial?.enabled ?? true,
        version: (initial?.version ?? 0) + 1,
        createdAt: initial?.createdAt ?? now,
        updatedAt: now,
        kind: EducationItemKind.video,
        videoTitle: _title.text.trim(),
        videoPath: _videoPath,
      ),
    );
  }

  void _removeVideo() {
    final previous = _videoPath;
    setState(() => _videoPath = '');
    if (previous.isNotEmpty && previous != (widget.initial?.videoPath ?? '')) {
      widget.videoService.deleteVideo(previous).catchError((_) {});
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
