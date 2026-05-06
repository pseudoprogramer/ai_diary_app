import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/day_context.dart';
import '../models/diary_entry.dart';
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
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
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
                _MonthlyDiaryCalendar(
                  visibleMonth: _visibleMonth,
                  selectedDay: _selectedDay,
                  onMonthChanged: (month) {
                    setState(() {
                      _visibleMonth = DateTime(month.year, month.month);
                    });
                  },
                  onDaySelected: (day) {
                    setState(() {
                      _selectedDay = DateTime(day.year, day.month, day.day);
                      _visibleMonth = DateTime(day.year, day.month);
                    });
                  },
                ),
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

class _MonthlyDiaryCalendar extends StatelessWidget {
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  const _MonthlyDiaryCalendar({
    required this.visibleMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        final entriesByDay = <DateTime, List<DiaryEntry>>{};
        for (final entry in vm.history) {
          final day = _dateOnly(entry.photoTakenAt ?? entry.createdAt);
          entriesByDay.putIfAbsent(day, () => <DiaryEntry>[]).add(entry);
        }
        final selectedEntries =
            entriesByDay[_dateOnly(selectedDay)] ?? const <DiaryEntry>[];

        return _Section(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _LabelRow(
                      icon: Icons.calendar_month_rounded,
                      label: '월별 기록',
                    ),
                  ),
                  IconButton(
                    tooltip: '이전 달',
                    onPressed: () => onMonthChanged(
                      DateTime(visibleMonth.year, visibleMonth.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    '${visibleMonth.year}.${_two(visibleMonth.month)}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: () => onMonthChanged(
                      DateTime(visibleMonth.year, visibleMonth.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: const ['일', '월', '화', '수', '목', '금', '토']
                    .map(
                      (day) => Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: const TextStyle(
                              color: Color(0xFF8D8378),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              _CalendarGrid(
                visibleMonth: visibleMonth,
                selectedDay: selectedDay,
                entriesByDay: entriesByDay,
                onDaySelected: onDaySelected,
              ),
              const SizedBox(height: 16),
              Text(
                '${selectedDay.month}월 ${selectedDay.day}일의 기록',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (selectedEntries.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '이 날에 저장된 일기가 아직 없어요.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                )
              else
                SizedBox(
                  height: 292,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: selectedEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return _PolaroidDiaryCard(entry: selectedEntries[index]);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final Map<DateTime, List<DiaryEntry>> entriesByDay;
  final ValueChanged<DateTime> onDaySelected;

  const _CalendarGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.entriesByDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final firstOffset = first.weekday % 7;
    final start = first.subtract(Duration(days: firstOffset));

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 42,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final day = _dateOnly(start.add(Duration(days: index)));
        final inMonth = day.month == visibleMonth.month;
        final selected = _sameDay(day, selectedDay);
        final today = _sameDay(day, DateTime.now());
        final hasEntry = entriesByDay.containsKey(day);

        return _CalendarDayButton(
          day: day,
          inMonth: inMonth,
          selected: selected,
          today: today,
          hasEntry: hasEntry,
          onTap: () => onDaySelected(day),
        );
      },
    );
  }
}

class _CalendarDayButton extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool today;
  final bool hasEntry;
  final VoidCallback onTap;

  const _CalendarDayButton({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.hasEntry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = selected
        ? const Color(0xFFBFDDB8)
        : today
            ? const Color(0xFFF1F6EC)
            : Colors.white;
    final borderColor = selected
        ? const Color(0xFF6F8F6C)
        : today
            ? const Color(0xFFBFDDB8)
            : const Color(0xFFEADFD3);
    final textColor = inMonth
        ? const Color(0xFF2F2A25)
        : colors.onSurfaceVariant.withValues(alpha: 0.38);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: textColor,
                fontWeight:
                    selected || today ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (hasEntry)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6F8F6C),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PolaroidDiaryCard extends StatelessWidget {
  final DiaryEntry entry;

  const _PolaroidDiaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(entry.imagePath);
    final exists = file.existsSync();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showEntryDialog(context, entry),
      child: Container(
        width: 188,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFEFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE6DACB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A6A5848),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: exists
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _firstDiaryLine(entry.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _entryTime(entry),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _firstDiaryLine(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '오늘의 작은 결';
  if (lines.length == 1) return lines.first;
  return lines[1].length < 8 ? lines.first : lines[1];
}

String _entryTime(DiaryEntry entry) {
  final dt = entry.photoTakenAt ?? entry.createdAt;
  return '${dt.year}.${_two(dt.month)}.${_two(dt.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

void _showEntryDialog(BuildContext context, DiaryEntry entry) {
  final theme = Theme.of(context);
  final file = File(entry.imagePath);
  final exists = file.existsSync();
  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (exists)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(file, fit: BoxFit.cover),
                    )
                  else
                    Container(
                      height: 220,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    _entryTime(entry),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    entry.text,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
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
