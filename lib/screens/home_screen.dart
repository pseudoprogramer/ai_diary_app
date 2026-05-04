import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/day_context.dart';
import '../viewmodels/home_viewmodel.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _scheduleController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  bool _compareMode = false;
  double _compare = 0.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().initialize();
    });
  }

  @override
  void dispose() {
    _scheduleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF3),
      appBar: AppBar(
        title: const Text('하루결'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFFAF3),
        actions: [
          IconButton(
            tooltip: '지난 기록',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
          ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<HomeViewModel>(
          builder: (context, vm, _) {
            if (vm.lastError != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(vm.lastError!)),
                );
                vm.consumeError();
              });
            }

            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              children: [
                Text(
                  '오늘의 흐름',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '캘린더와 사진첩의 시간 정보를 맞춰 하루의 장면을 먼저 정리합니다.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                const _TodayFlowSection(),
                const SizedBox(height: 12),
                _Section(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _LabelRow(
                          icon: Icons.mood_rounded, label: '오늘의 감정'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['평온', '설렘', '뿌듯함', '지침', '아쉬움', '행복', '복잡함']
                            .map(
                              (mood) => ChoiceChip(
                                label: Text(mood),
                                selected: vm.mood == mood,
                                onSelected: (_) => vm.setMood(mood),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      const _LabelRow(
                          icon: Icons.edit_note_rounded, label: '문체'),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '담백하게', label: Text('담백')),
                          ButtonSegment(value: '감성적으로', label: Text('감성')),
                          ButtonSegment(value: '귀엽게', label: Text('귀엽게')),
                        ],
                        selected: {vm.tone},
                        showSelectedIcon: false,
                        onSelectionChanged: (values) =>
                            vm.setTone(values.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _LabelRow(
                          icon: Icons.event_note_rounded,
                          label: '추가로 남길 일정/상황'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _scheduleController,
                        maxLines: 4,
                        minLines: 3,
                        textInputAction: TextInputAction.newline,
                        onChanged: vm.setScheduleText,
                        decoration: const InputDecoration(
                          hintText:
                              '사진이나 캘린더에 없는 일을 적어주세요.\n예: 친구와 잠깐 통화, 갑자기 들른 카페',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _LabelRow(
                          icon: Icons.short_text_rounded, label: '한 줄 메모'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _memoController,
                        textInputAction: TextInputAction.done,
                        onEditingComplete: () =>
                            FocusScope.of(context).unfocus(),
                        onChanged: vm.setMemo,
                        decoration: const InputDecoration(
                          hintText: '오늘 기억하고 싶은 말',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: _LabelRow(
                                  icon: Icons.photo_library_rounded,
                                  label: '대표 사진')),
                          IconButton(
                            tooltip: '사진 직접 선택',
                            onPressed: vm.isLoading ? null : vm.pickPhotos,
                            icon: const Icon(Icons.add_photo_alternate_rounded),
                          ),
                          IconButton(
                            tooltip: '직접 선택한 사진 비우기',
                            onPressed:
                                vm.selectedPhotoBytes.isEmpty || vm.isLoading
                                    ? null
                                    : vm.clearSelectedPhotos,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (vm.selectedPhotoBytes.isEmpty &&
                          vm.todayRepresentativeImageBytes == null)
                        Container(
                          height: 136,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEADFD3)),
                          ),
                          child: Text(
                            '오늘 사진을 찾으면 자동으로 대표 사진이 표시됩니다.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        )
                      else
                        SizedBox(
                          height: 132,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: vm.selectedPhotoBytes.isNotEmpty
                                ? vm.selectedPhotoBytes.length
                                : 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final bytes = vm.selectedPhotoBytes.isNotEmpty
                                  ? vm.selectedPhotoBytes[index]
                                  : vm.todayRepresentativeImageBytes!;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  bytes,
                                  width: 132,
                                  height: 132,
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DiaryPreview(compareMode: _compareMode, compare: _compare),
                if (_compareMode)
                  Slider(
                    value: _compare,
                    onChanged: (value) => setState(() => _compare = value),
                  ),
                const SizedBox(height: 12),
                _ActionRow(
                  compareMode: _compareMode,
                  onCompareChanged: (value) =>
                      setState(() => _compareMode = value),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Consumer<HomeViewModel>(
          builder: (context, vm, _) {
            return FilledButton.icon(
              onPressed: vm.isLoading
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      vm.createDailyDiary();
                    },
              icon: vm.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: const Text('오늘 페이지 만들기'),
            );
          },
        ),
      ),
    );
  }
}

class _TodayFlowSection extends StatelessWidget {
  const _TodayFlowSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                      child: _LabelRow(
                          icon: Icons.timeline_rounded, label: '자동 정리된 흐름')),
                  IconButton(
                    tooltip: '다시 불러오기',
                    onPressed:
                        vm.isContextLoading ? null : vm.refreshTodayContext,
                    icon: vm.isContextLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (vm.isContextLoading && vm.todaySegments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (vm.todaySegments.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '아직 오늘의 사진이나 캘린더 일정을 찾지 못했어요. 권한을 허용했는지 확인하거나 사진을 직접 골라주세요.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                )
              else
                Column(
                  children: [
                    for (final segment in vm.todaySegments.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SegmentTile(segment: segment),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentTile extends StatelessWidget {
  final DaySegment segment;

  const _SegmentTile({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isCalendar = segment.source == 'calendar';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCalendar ? const Color(0xFFF4F8F1) : const Color(0xFFF8F3EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEADFD3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCalendar
                ? Icons.event_available_rounded
                : Icons.photo_camera_rounded,
            color: const Color(0xFF6F8F6C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(segment.confidence * 100).round()}%',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[segment.timeRange];
    if (segment.calendarName != null &&
        segment.calendarName!.trim().isNotEmpty) {
      parts.add(segment.calendarName!.trim());
    }
    if (segment.photoCount > 0) {
      parts.add('사진 ${segment.photoCount}장');
    }
    if (segment.placeHint != null && segment.placeHint!.trim().isNotEmpty) {
      parts.add(segment.placeHint!.trim());
    }
    return parts.join(' · ');
  }
}

class _DiaryPreview extends StatelessWidget {
  final bool compareMode;
  final double compare;

  const _DiaryPreview({required this.compareMode, required this.compare});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        final orig = vm.originalImageBytes;
        final gen = vm.generatedImageBytes;
        final hasOrig = orig != null && orig.isNotEmpty;
        final hasGen = gen != null && gen.isNotEmpty;
        final text = vm.diaryText;

        if (!hasGen && (text == null || text.trim().isEmpty)) {
          return const SizedBox.shrink();
        }

        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LabelRow(icon: Icons.menu_book_rounded, label: '오늘의 페이지'),
              const SizedBox(height: 12),
              if (hasGen)
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: compareMode && hasOrig
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(orig, fit: BoxFit.cover),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: compare.clamp(0.0, 1.0),
                                  alignment: Alignment.centerLeft,
                                  child: Image.memory(gen, fit: BoxFit.cover),
                                ),
                              ),
                            ],
                          )
                        : Image.memory(vm.showOriginal && hasOrig ? orig : gen,
                            fit: BoxFit.cover),
                  ),
                ),
              if (text != null && text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool compareMode;
  final ValueChanged<bool> onCompareChanged;

  const _ActionRow({required this.compareMode, required this.onCompareChanged});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        final hasText = vm.diaryText != null && vm.diaryText!.trim().isNotEmpty;
        final hasImage = vm.generatedImageBytes != null &&
            vm.generatedImageBytes!.isNotEmpty;
        if (!hasText && !hasImage) return const SizedBox.shrink();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: vm.showOriginal ? '결과 보기' : '원본 보기',
              onPressed: vm.originalImageBytes == null
                  ? null
                  : () {
                      onCompareChanged(false);
                      vm.toggleShowOriginal();
                    },
              icon: Icon(vm.showOriginal
                  ? Icons.auto_awesome_rounded
                  : Icons.image_search_rounded),
            ),
            IconButton(
              tooltip: '비교 모드',
              onPressed: vm.originalImageBytes == null ||
                      vm.generatedImageBytes == null
                  ? null
                  : () => onCompareChanged(!compareMode),
              icon: Icon(compareMode
                  ? Icons.splitscreen_rounded
                  : Icons.compare_rounded),
            ),
            IconButton(
              tooltip: '다시 생성',
              onPressed: vm.isLoading ? null : vm.regenerateDiary,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: '일기 복사',
              onPressed: hasText
                  ? () async {
                      await Clipboard.setData(
                          ClipboardData(text: vm.diaryText ?? ''));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('일기를 복사했습니다.')),
                      );
                    }
                  : null,
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              tooltip: '공유',
              onPressed: (hasText || hasImage)
                  ? () async {
                      XFile? imageFile;
                      if (hasImage) {
                        final file = await vm.writeImageTempFile();
                        if (file != null) imageFile = XFile(file.path);
                      }
                      final content = vm.diaryText ?? '';
                      if (imageFile != null) {
                        await Share.shareXFiles([imageFile], text: content);
                      } else {
                        await Share.share(content);
                      }
                    }
                  : null,
              icon: const Icon(Icons.ios_share_rounded),
            ),
            IconButton(
              tooltip: '갤러리에 저장',
              onPressed: hasImage
                  ? () async {
                      final ok = await vm.saveImageToGallery();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(ok ? '갤러리에 저장했습니다.' : '저장하지 못했습니다.')),
                      );
                    }
                  : null,
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final Widget child;
  const _Section({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEADFD3)),
      ),
      child: child,
    );
  }
}

class _LabelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LabelRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF6F8F6C)),
        const SizedBox(width: 7),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
