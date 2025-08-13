import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

class GeminiService {
  GeminiService();

  String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  // v1beta REST endpoint for text generation
  static const String _geminiTextEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  Future<String> generateDiaryText({
    required DateTime photoTakenAt,
    String? locationHint,
    String? routeSummary,
    String? eventSummary,
  }) async {
    if (apiKey.isEmpty) {
      return '환경 변수에 GEMINI_API_KEY가 설정되지 않았습니다.';
    }

    final String dateStr = _formatKoreanDateTime(photoTakenAt);

    const String systemStyle =
        '너는 감성적인 한국어 그림일기 작가야. 간결하지만 따뜻한 4~6문장으로 오늘의 분위기를 담아줘.'
        ' 구체적인 사물/햇살/바람/색채 같은 감각을 한두 개 녹여주되, 과장되거나 뻔한 표현은 피하고 자연스럽게.'
        ' 해시태그나 불필요한 설명은 쓰지 말고 결과만 작성해.';

    final String userPrompt = [
      '다음 정보를 참고해 일기 본문을 작성해줘:',
      '- 날짜/시간: $dateStr',
      if (locationHint != null && locationHint.trim().isNotEmpty)
        '- 위치: $locationHint',
      if (routeSummary != null && routeSummary.trim().isNotEmpty)
        '- 오늘의 동선 요약: $routeSummary',
      if (eventSummary != null && eventSummary.trim().isNotEmpty)
        '- 오늘의 주요 이벤트: $eventSummary',
    ].join('\n');

    final Map<String, dynamic> body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': '$systemStyle\n\n$userPrompt'}
          ]
        }
      ]
    };

    try {
      final uri = Uri.parse('$_geminiTextEndpoint?key=$apiKey');
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return '텍스트 생성에 실패했습니다 (HTTP ${response.statusCode}).';
      }

      final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic>? candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return '생성된 결과가 없습니다.';
      }

      final Map<String, dynamic> top = candidates.first as Map<String, dynamic>;
      final Map<String, dynamic>? content = top['content'] as Map<String, dynamic>?;
      final List<dynamic>? parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return '생성된 결과가 없습니다.';
      }

      final Map<String, dynamic> firstPart = parts.first as Map<String, dynamic>;
      final String? text = firstPart['text'] as String?;
      return (text == null || text.trim().isEmpty) ? '생성된 결과가 없습니다.' : text.trim();
    } catch (_) {
      return '텍스트 생성 중 오류가 발생했습니다.';
    }
  }

  Future<Uint8List> generateIllustrationBytes({
    required String diaryText,
    required Uint8List fallbackImageBytes,
    bool enableCloud = true,
    int? width,
    int? height,
    String? style,
  }) async {
    // 1) If configured, try remote image generation API
    final String? imageApiUrl = dotenv.env['IMAGE_API_URL'];
    final String? imageApiKey = dotenv.env['IMAGE_API_KEY'];
    if (enableCloud && imageApiUrl != null && imageApiUrl.trim().isNotEmpty) {
      try {
        final uri = Uri.parse(imageApiUrl);
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (imageApiKey != null && imageApiKey.isNotEmpty) {
          headers['Authorization'] = 'Bearer $imageApiKey';
        }
        final Map<String, dynamic> payload = {'prompt': diaryText};
        if (width != null) payload['width'] = width;
        if (height != null) payload['height'] = height;
        if (style != null && style.trim().isNotEmpty) payload['style'] = style;
        final body = jsonEncode(payload);
        final resp = await http
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(resp.body) as Map<String, dynamic>;
          final String? b64 = (json['image_base64'] as String?) ?? (json['image'] as String?);
          if (b64 != null && b64.isNotEmpty) {
            // Strip data URI prefix if present
            final String pure = b64.contains(',') ? b64.split(',').last : b64;
            final Uint8List bytes = base64Decode(pure);
            if (bytes.isNotEmpty) return bytes;
          }
        }
      } catch (_) {
        // Fall through to local filter
      }
    }

    // 2) Fallback: 간단한 파스텔톤 필터 적용 (로컬 처리)
    try {
      final img = image_lib.decodeImage(fallbackImageBytes);
      if (img == null) return fallbackImageBytes;
      final image_lib.Image processed = image_lib.adjustColor(
        img,
        saturation: 0.85,
        brightness: 0.06,
        gamma: 0.96,
      );
      // Use a tiny blur for speed; iOS devices already have strong GPUs but we run on CPU here
      final image_lib.Image blurred = image_lib.gaussianBlur(processed, radius: 0);
      final Uint8List out = Uint8List.fromList(image_lib.encodeJpg(blurred, quality: 92));
      return out;
    } catch (_) {
      return fallbackImageBytes;
    }
  }

  String _formatKoreanDateTime(DateTime dt) {
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}


