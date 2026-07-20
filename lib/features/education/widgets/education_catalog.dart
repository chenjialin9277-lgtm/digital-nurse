import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';
import '../models/education_item.dart';

enum EducationCatalogView { all, favorites, recent }

class EducationCatalog extends StatefulWidget {
  const EducationCatalog({
    super.key,
    required this.items,
    required this.language,
    required this.onSelected,
    this.recentItemIds = const [],
  });

  final List<EducationItem> items;
  final OfflineSpeechLanguage language;
  final Future<void> Function(EducationItem item) onSelected;
  final List<String> recentItemIds;

  @override
  State<EducationCatalog> createState() => _EducationCatalogState();
}

class _EducationCatalogState extends State<EducationCatalog> {
  final _searchController = TextEditingController();
  EducationCatalogView _view = EducationCatalogView.all;
  String? _category;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        widget.items.map((item) => item.category).toSet().toList()..sort();
    final visibleItems = _filteredItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: '搜索宣教名称或分类',
            prefixIcon: const Icon(Icons.search),
            suffixIcon:
                _query.isEmpty
                    ? null
                    : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ViewChip(
                label: '全部',
                icon: Icons.apps_outlined,
                selected: _view == EducationCatalogView.all,
                onSelected:
                    () => setState(() => _view = EducationCatalogView.all),
              ),
              _ViewChip(
                label: '常用',
                icon: Icons.star_outline,
                selected: _view == EducationCatalogView.favorites,
                onSelected:
                    () =>
                        setState(() => _view = EducationCatalogView.favorites),
              ),
              _ViewChip(
                label: '最近',
                icon: Icons.history,
                selected: _view == EducationCatalogView.recent,
                onSelected:
                    () => setState(() => _view = EducationCatalogView.recent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: FilterChip(
                  label: const Text('全部'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: FilterChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected:
                        (_) => setState(
                          () =>
                              _category =
                                  _category == category ? null : category,
                        ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              visibleItems.isEmpty
                  ? const Center(child: Text('没有找到匹配的宣教内容'))
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 2, 4, 12),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return _EducationTile(
                        item: item,
                        language: widget.language,
                        onTap: () => widget.onSelected(item),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  List<EducationItem> _filteredItems() {
    final recentOrder = <String, int>{
      for (var index = 0; index < widget.recentItemIds.length; index++)
        widget.recentItemIds[index]: index,
    };
    final filtered =
        widget.items.where((item) {
          if (_view == EducationCatalogView.favorites && !item.favorite) {
            return false;
          }
          if (_view == EducationCatalogView.recent &&
              !recentOrder.containsKey(item.id)) {
            return false;
          }
          if (_category != null && item.category != _category) return false;
          if (_query.isEmpty) return true;
          final content = item.contentFor(widget.language);
          final available = item.isAvailableIn(widget.language);
          final haystack =
              '${available ? content.title : ''}\n'
                      '${available ? content.summary : ''}\n${item.category}'
                  .toLowerCase();
          return haystack.contains(_query.toLowerCase());
        }).toList();
    if (_view == EducationCatalogView.recent) {
      filtered.sort(
        (left, right) => (recentOrder[left.id] ?? 9999).compareTo(
          recentOrder[right.id] ?? 9999,
        ),
      );
    } else {
      filtered.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    }
    return filtered;
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _EducationTile extends StatelessWidget {
  const _EducationTile({
    required this.item,
    required this.language,
    required this.onTap,
  });

  final EducationItem item;
  final OfflineSpeechLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = item.contentFor(language);
    final available = item.isAvailableIn(language);
    final title =
        available ? content.title : '${item.category}·${language.label}';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.favorite ? Icons.star : Icons.menu_book_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      available
                          ? '${item.category} · 约 ${item.estimatedManualMinutes} 分钟'
                          : '该语言暂未提供',
                      style: TextStyle(
                        color:
                            available
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.error,
                        fontWeight:
                            available ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(available ? Icons.chevron_right : Icons.lock_outline),
            ],
          ),
        ),
      ),
    );
  }
}
