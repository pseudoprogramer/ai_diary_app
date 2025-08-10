import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/home_viewmodel.dart';
import '../models/diary_entry.dart';

class HistoryScreen extends StatefulWidget {
  final bool autoOpenLatest;
  const HistoryScreen({super.key, this.autoOpenLatest = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_opened && widget.autoOpenLatest) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final vm = context.read<HomeViewModel>();
        if (vm.history.isNotEmpty) {
          final latest = vm.history.first;
          showDialog(
            context: context,
            builder: (_) => Dialog(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (File(latest.imagePath).existsSync())
                    Image.file(File(latest.imagePath), fit: BoxFit.cover),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(latest.text, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('히스토리'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '모두 삭제',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              final vm = context.read<HomeViewModel>();
              final messenger = ScaffoldMessenger.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('모두 삭제'),
                  content: const Text('모든 히스토리를 삭제할까요? 이 작업은 되돌릴 수 없습니다.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
                  ],
                ),
              );
              if (ok == true) {
                final done = await vm.clearHistory();
                messenger.showSnackBar(
                  SnackBar(content: Text(done ? '모두 삭제했습니다.' : '삭제하지 못했습니다.')),
                );
              }
            },
          )
        ],
      ),
      body: Consumer<HomeViewModel>(
        builder: (context, vm, _) {
          final List<DiaryEntry> items = vm.history;
          if (items.isEmpty) {
            return const Center(child: Text('아직 생성된 일기가 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final e = items[index];
              return Dismissible(
                key: ValueKey(e.id),
                background: Container(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Icon(Icons.delete_outline),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('삭제'),
                      content: const Text('이 항목을 삭제할까요?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
                      ],
                    ),
                  );
                },
                onDismissed: (_) async {
                  final vm = context.read<HomeViewModel>();
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await vm.deleteEntryById(e.id);
                  messenger.showSnackBar(
                    SnackBar(content: Text(ok ? '삭제했습니다.' : '삭제하지 못했습니다.')),
                  );
                },
                child: _DiaryTile(entry: e),
              );
            },
          );
        },
      ),
    );
  }
}

class _DiaryTile extends StatelessWidget {
  final DiaryEntry entry;
  const _DiaryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (File(entry.imagePath).existsSync())
                  Image.file(File(entry.imagePath), fit: BoxFit.cover),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(entry.text, style: theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: File(entry.imagePath).existsSync()
                ? Image.file(
                    File(entry.imagePath),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 72,
                    height: 72,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  _buildSubtitle(entry),
                  style: theme.textTheme.labelMedium,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(DiaryEntry e) {
    final parts = <String>[];
    parts.add(_fmt(e.createdAt));
    if ((e.placeLabel ?? '').trim().isNotEmpty) parts.add(e.placeLabel!.trim());
    return parts.join(' · ');
  }

  String _fmt(DateTime dt) {
    return '${dt.year}.${_two(dt.month)}.${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}


