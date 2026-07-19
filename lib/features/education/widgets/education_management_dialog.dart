import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';
import '../data/education_repository.dart';
import '../models/education_item.dart';
import 'education_item_editor.dart';

class EducationManagementDialog extends StatefulWidget {
  const EducationManagementDialog({super.key, required this.repository});

  final EducationRepository repository;

  @override
  State<EducationManagementDialog> createState() =>
      _EducationManagementDialogState();
}

class _EducationManagementDialogState extends State<EducationManagementDialog> {
  List<EducationItem> _items = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.loadAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.local_library_outlined),
          SizedBox(width: 10),
          Text('本科室宣教内容'),
        ],
      ),
      content: SizedBox(
        width: 940,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: _buildBody(),
      ),
      actions: [
        FilledButton.tonalIcon(
          onPressed: _loading ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('新增宣教'),
        ),
        FilledButton(
          onPressed: () => Navigator.maybePop(context, _items),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 10),
            const Text('无法读取本科室宣教内容'),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('尚未配置宣教，请点击“新增宣教”'));
    }
    return ReorderableListView.builder(
      itemCount: _items.length,
      onReorderItem: _reorder,
      itemBuilder: (context, index) => _itemCard(_items[index], index),
    );
  }

  Widget _itemCard(EducationItem item, int index) {
    final mandarin = item.contentFor(OfflineSpeechLanguage.mandarin);
    return Card(
      key: ValueKey('education-card-${item.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_indicator),
          ),
        ),
        title: Text(
          mandarin.title.isEmpty ? '未命名草稿' : mandarin.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(item.category),
            ...OfflineSpeechLanguage.values.map((language) {
              final available = item.isAvailableIn(language);
              return Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${language.label}${available ? '已发布' : '未发布'}'),
              );
            }),
            if (mandarin.needsReview)
              const Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.warning_amber, size: 17),
                label: Text('理解题待复核'),
              ),
          ],
        ),
        trailing: SizedBox(
          width: 280,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: item.favorite ? '取消常用' : '设为常用',
                onPressed: () => _toggleFavorite(item),
                icon: Icon(item.favorite ? Icons.star : Icons.star_border),
              ),
              IconButton(
                tooltip: '编辑',
                onPressed: () => _edit(item),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '复制',
                onPressed: () => _copy(item),
                icon: const Icon(Icons.copy_outlined),
              ),
              Switch.adaptive(
                key: Key('education-enabled-${item.id}'),
                value: item.enabled,
                onChanged: (enabled) => _setEnabled(item, enabled),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: () => _delete(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final item = await showDialog<EducationItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EducationItemEditor(sortOrder: _nextSortOrder),
    );
    if (item == null || !mounted) return;
    await widget.repository.save(item);
    if (!mounted) return;
    setState(() => _items = [..._items, item]);
  }

  Future<void> _edit(EducationItem initial) async {
    final item = await showDialog<EducationItem>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => EducationItemEditor(
            initial: initial,
            sortOrder: initial.sortOrder,
          ),
    );
    if (item == null || !mounted) return;
    await widget.repository.save(item);
    if (!mounted) return;
    setState(() {
      _items =
          _items.map((value) => value.id == item.id ? item : value).toList();
    });
  }

  Future<void> _copy(EducationItem source) async {
    final now = DateTime.now().toUtc();
    final copy = source.copyWith(
      id: '${source.id}_copy_${now.microsecondsSinceEpoch}',
      sortOrder: _nextSortOrder,
      favorite: false,
      version: 1,
      createdAt: now,
      updatedAt: now,
      contents: {
        for (final entry in source.contents.entries)
          entry.key: entry.value.copyWith(
            title: '${entry.value.title}（副本）',
            published: false,
            needsReview: true,
          ),
      },
    );
    await widget.repository.save(copy);
    if (!mounted) return;
    setState(() => _items = [..._items, copy]);
  }

  Future<void> _toggleFavorite(EducationItem item) async {
    await _replace(item.copyWith(favorite: !item.favorite));
  }

  Future<void> _setEnabled(EducationItem item, bool enabled) async {
    await _replace(item.copyWith(enabled: enabled));
  }

  Future<void> _replace(EducationItem item) async {
    final updated = item.copyWith(
      version: item.version + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    await widget.repository.save(updated);
    if (!mounted) return;
    setState(() {
      _items =
          _items
              .map((value) => value.id == updated.id ? updated : value)
              .toList();
    });
  }

  Future<void> _delete(EducationItem item) async {
    await widget.repository.softDelete(item.id);
    if (!mounted) return;
    setState(
      () => _items = _items.where((value) => value.id != item.id).toList(),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final reordered = [..._items];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final normalized = List.generate(
      reordered.length,
      (index) => reordered[index].copyWith(sortOrder: index),
    );
    setState(() => _items = normalized);
    await widget.repository.reorder(normalized.map((item) => item.id).toList());
  }

  int get _nextSortOrder {
    var maximum = -1;
    for (final item in _items) {
      if (item.sortOrder > maximum) maximum = item.sortOrder;
    }
    return maximum + 1;
  }
}
