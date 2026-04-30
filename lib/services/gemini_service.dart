import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

class GeminiService {
  GeminiService();

  String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static const String _geminiTextEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  Future<String> generateDiaryFromInputs({
    required DateTime date,
    required String mood,
    required String tone,
    required String scheduleText,
    required String memo,
    required int photoCount,
    String? locationHint,
    String? routeSummary,
    String? eventSummary,
  }) async {
    if (apiKey.isEmpty) {
      return _localDiaryFallback(
        date: date,
        mood: mood,
        tone: tone,
        scheduleText: scheduleText,
        memo: memo,
        photoCount: photoCount,
      );
    }

    final String prompt = [
      '너는 한국어 감성 다이어리 에이전트야.',
      '사용자가 입력한 하루의 재료를 바탕으로 실제 일기처럼 자연스럽게 써줘.',
      '문체: $tone',
      '날짜: ${_formatKoreanDateTime(date)}',
      '기분: $mood',
      if (scheduleText.trim().isNotEmpty) '일정:\n$scheduleText',
      if (memo.trim().isNotEmpty) '한 줄 메모: $memo',
      '사진 수: $photoCount장',
      if (locationHint != null && locationHint.trim().isNotEmpty) '위치 힌트: $locationHint',
      if (routeSummary != null && routeSummary.trim().isNotEmpty) '동선 요약: $routeSummary',
      if (eventSummary != null && eventSummary.trim().isNotEmpty) '캘린더 요약: $eventSummary',
      '',
      '출력 형식:',
      '제목 한 줄을 먼저 쓰고, 빈 줄 뒤에 5~8문장의 일기 본문을 써줘.',
      '해시태그, 목록, 설명문은 쓰지 마.',
    ].join('\n');

    return await _postTextPrompt(prompt) ??
        _localDiaryFallback(
          date: date,
          mood: mood,
          tone: tone,
          scheduleText: scheduleText,
          memo: memo,
          photoCount: photoCount,
        );
  }

  Future<String> generateDiaryText({
    required DateTime photoTakenAt,
    String? locationHint,
    String? routeSummary,
    String? eventSummary,
  }) async {
    return generateDiaryFromInputs(
      date: photoTakenAt,
      mood: '평온',
      tone: '감성적으로',
      scheduleText: eventSummary ?? '',
      memo: routeSummary ?? '',
      photoCount: 1,
      locationHint: locationHint,
      routeSummary: routeSummary,
      eventSummary: eventSummary,
    );
  }

  Future<String?> _postTextPrompt(String prompt) async {
    final Map<String, dynamic> body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    };

    try {
      final uri = Uri.parse('$_geminiTextEndpoint?key=$apiKey');
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic>? candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final Map<String, dynamic> top = candidates.first as Map<String, dynamic>;
      final Map<String, dynamic>? content = top['content'] as Map<String, dynamic>?;
      final List<dynamic>? parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;

      final Map<String, dynamic> firstPart = parts.first as Map<String, dynamic>;
      final String? text = firstPart['text'] as String?;
      return (text == null || text.trim().isEmpty) ? null : text.trim();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> generateIllustrationBytes({
    required String diaryText,
    required Uint8List fallbackImageBytes,
    bool enableCloud = false,
    int? width,
    int? height,
    String? style,
  }) async {
    return _generateLocalPastelImage(fallbackImageBytes);
  }

  Future<Uint8List> _generateLocalPastelImage(Uint8List sourceBytes) async {
    try {
      final img = image_lib.decodeImage(sourceBytes);
      if (img == null) return sourceBytes;

      final resized = image_lib.copyResize(
        img,
        width: img.width > 1024 ? 1024 : img.width,
        interpolation: image_lib.Interpolation.average,
      );
      final softened = image_lib.gaussianBlur(resized, radius: 1);
      final pastel = image_lib.adjustColor(
        softened,
        saturation: 0.72,
        brightness: 0.09,
        contrast: 0.92,
        gamma: 0.95,
      );

      return Uint8List.fromList(image_lib.encodeJpg(pastel, quality: 92));
    } catch (_) {
      return sourceBytes;
    }
  }

  String _localDiaryFallback({
    required DateTime date,
    required String mood,
    required String tone,
    required String scheduleText,
    required String memo,
    required int photoCount,
  }) {
    final scheduleLines = scheduleText
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[-•]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final firstMoment = scheduleLines.isEmpty ? '작은 순간들' : scheduleLines.first;
    final memoLine = memo.trim().isEmpty ? '' : "\n\n메모로 남긴 '$memo'라는 말이 오늘의 중심에 조용히 남았다.";
    final photoLine = photoCount == 0 ? '' : '\n\n사진 $photoCount장이 오늘의 색을 붙잡아 주었다.';

    return [
      '오늘의 작은 결',
      '',
      '오늘은 ${date.year}년 ${date.month}월 ${date.day}일, 마음이 $mood 쪽으로 기울어 있던 하루였다.',
      '$firstMoment에서 시작된 시간은 생각보다 천천히 흘렀고, 그 안에 사소하지만 분명한 장면들이 있었다.$memoLine$photoLine',
      '크게 특별한 일이 아니어도 하루를 다시 바라보면 나름의 색과 온도가 있다는 걸 알게 된다.',
      '오늘의 기록은 완벽하지 않아도 충분히 나답고, 그래서 오래 남겨둘 만하다.',
    ].join('\n');
  }

  String _formatKoreanDateTime(DateTime dt) {
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
