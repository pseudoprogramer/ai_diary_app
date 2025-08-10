import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../viewmodels/home_viewmodel.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _compareMode = false;
  double _compare = 0.5;
  @override
  void initState() {
    super.initState();
    // 앱 진입 시 위치 요청 및 현재 위치 조회
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().requestLocationAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color placeholderBackground = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.06),
      colorScheme.surface,
    );
    final Color iconColor = colorScheme.outline;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 그림일기'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '히스토리',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: '더보기',
            onSelected: (value) async {
              if (value == 'run_auto') {
                await context.read<HomeViewModel>().runAutoPipelineNow();
              } else if (value == 'toggle_auto') {
                final vm = context.read<HomeViewModel>();
                await vm.setAutoEnabled(!vm.autoEnabled);
              }
            },
            itemBuilder: (context) {
              final vm = context.read<HomeViewModel>();
              return [
                const PopupMenuItem(
                  value: 'run_auto',
                  child: Text('자정 파이프라인 테스트 실행'),
                ),
                PopupMenuItem(
                  value: 'toggle_auto',
                  child: Text(vm.autoEnabled ? '자동 생성 끄기' : '자동 생성 켜기'),
                ),
              ];
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Consumer<HomeViewModel>(builder: (context, vm, _) {
                if (vm.lastError != null) {
                  // 스낵바로 사용자에게 오류 전달 후 상태 초기화
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(vm.lastError!)),
                    );
                    vm.consumeError();
                  });
                }
                return const SizedBox.shrink();
              }),
              Consumer<HomeViewModel>(
                builder: (context, vm, _) {
                  final pos = vm.lastPosition;
                  final hasPos = pos != null;
                  final String label = !hasPos
                      ? '위치 권한이 필요합니다.'
                      : (
                          vm.placeLabel != null && vm.placeLabel!.trim().isNotEmpty
                              ? '현재 위치: ${vm.placeLabel} (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'
                              : '현재 위치: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
                        );
                  return AnimatedOpacity(
                    opacity: hasPos ? 1 : 0.6,
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: placeholderBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Consumer<HomeViewModel>(
                    builder: (context, vm, _) {
                      final orig = vm.originalImageBytes;
                      final gen = vm.generatedImageBytes;
                      final bool hasOrig = orig != null && orig.isNotEmpty;
                      final bool hasGen = gen != null && gen.isNotEmpty;

                      if (_compareMode && hasOrig && hasGen) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(orig, fit: BoxFit.cover),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _compare.clamp(0.0, 1.0),
                                  alignment: Alignment.centerLeft,
                                  child: Image.memory(gen, fit: BoxFit.cover),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final bytes = (vm.showOriginal && hasOrig) ? orig : gen;
                      if (bytes != null && bytes.isNotEmpty) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(bytes, fit: BoxFit.cover),
                        );
                      }
                      return Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 64,
                          color: iconColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Consumer<HomeViewModel>(builder: (context, vm, _) {
                final canToggle = (vm.originalImageBytes != null && vm.originalImageBytes!.isNotEmpty);
                if (!canToggle) return const SizedBox.shrink();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilterChip(
                      label: Text(vm.showOriginal ? '원본 보기' : '일러스트 보기'),
                      selected: vm.showOriginal,
                      onSelected: (_) {
                        setState(() => _compareMode = false);
                        vm.toggleShowOriginal();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('비교 모드'),
                      selected: _compareMode,
                      onSelected: (_) {
                        if (vm.showOriginal) vm.setShowOriginal(false);
                        setState(() => _compareMode = !_compareMode);
                      },
                    ),
                  ],
                );
              }),
              if (_compareMode)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Slider(
                    value: _compare,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => _compare = v),
                  ),
                ),
              Consumer<HomeViewModel>(
                builder: (context, vm, _) {
                  final String text = vm.diaryText ?? '여기에 AI가 생성한 일기가 표시됩니다.';
                  return Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Consumer<HomeViewModel>(builder: (context, vm, _) {
                final bool hasText = (vm.diaryText != null && vm.diaryText!.trim().isNotEmpty);
                final bool hasImage = (vm.generatedImageBytes != null && vm.generatedImageBytes!.isNotEmpty);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '다시 생성',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: hasImage && !vm.isLoading
                          ? () async {
                              await context.read<HomeViewModel>().regenerateDiary();
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: '일기 복사',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: hasText
                          ? () async {
                              await Clipboard.setData(ClipboardData(text: vm.diaryText ?? ''));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('일기를 클립보드에 복사했습니다.')),
                                );
                              }
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: '공유',
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: (hasText || hasImage)
                          ? () async {
                              final vm = context.read<HomeViewModel>();
                              XFile? imageFile;
                              if (hasImage) {
                                final file = await vm.writeImageTempFile();
                                if (file != null) {
                                  imageFile = XFile(file.path);
                                }
                              }
                              final content = vm.diaryText ?? '';
                              if (imageFile != null) {
                                await Share.shareXFiles([imageFile], text: content);
                              } else {
                                await Share.share(content.isEmpty ? 'AI 그림일기' : content);
                              }
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: '갤러리에 저장',
                      icon: const Icon(Icons.download_rounded),
                      onPressed: hasImage
                          ? () async {
                              final ok = await context.read<HomeViewModel>().saveImageToGallery();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(ok ? '갤러리에 저장했습니다.' : '저장에 실패했습니다.')),
                                );
                              }
                            }
                          : null,
                    ),
                  ],
                );
              }),
              const Spacer(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: Consumer<HomeViewModel>(
            builder: (context, vm, _) {
              return ElevatedButton(
                onPressed: vm.isLoading ? null : () => vm.createAiDiary(),
                child: vm.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('AI 그림일기 만들기'),
              );
            },
          ),
        ),
      ),
    );
  }
}


