import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

class GeminiService {
  GeminiService();

  String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static const String _geminiTextEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
  static const String _geminiImageEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent';

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
      if (locationHint != null && locationHint.trim().isNotEmpty)
        '위치 힌트: $locationHint',
      if (routeSummary != null && routeSummary.trim().isNotEmpty)
        '동선 요약: $routeSummary',
      if (eventSummary != null && eventSummary.trim().isNotEmpty)
        '캘린더 요약: $eventSummary',
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
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic>? candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final Map<String, dynamic> top = candidates.first as Map<String, dynamic>;
      final Map<String, dynamic>? content =
          top['content'] as Map<String, dynamic>?;
      final List<dynamic>? parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;

      final Map<String, dynamic> firstPart =
          parts.first as Map<String, dynamic>;
      final String? text = firstPart['text'] as String?;
      return (text == null || text.trim().isEmpty) ? null : text.trim();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> generateIllustrationBytes({
    required String diaryText,
    required Uint8List? fallbackImageBytes,
    bool enableCloud = false,
    int? width,
    int? height,
    String? style,
  }) async {
    final hasReferencePhoto =
        fallbackImageBytes != null && fallbackImageBytes.isNotEmpty;

    // Reference-photo generation can distort faces and personal memories.
    // For diary pages, keep real photos on-device and apply a conservative
    // photo-preserving treatment instead of synthesizing a new scene.
    if (enableCloud && apiKey.isNotEmpty && !hasReferencePhoto) {
      final cloudImage = await _generateCloudIllustrationBytes(
        diaryText: diaryText,
        fallbackImageBytes: null,
        width: width,
        height: height,
        style: style,
      );
      if (cloudImage != null) return cloudImage;
    }

    if (fallbackImageBytes == null || fallbackImageBytes.isEmpty) {
      return _generateLocalDiaryCardImage(diaryText,
          width: width, height: height);
    }
    return _generateLocalPastelImage(
      fallbackImageBytes,
      width: width,
      height: height,
      style: style,
    );
  }

  Future<Uint8List?> _generateCloudIllustrationBytes({
    required String diaryText,
    required Uint8List? fallbackImageBytes,
    int? width,
    int? height,
    String? style,
  }) async {
    try {
      final prompt = [
        'Create a warm illustrated diary-page image.',
        'Style: ${style?.trim().isNotEmpty == true ? style!.trim() : 'pastel watercolor diary with visible brush strokes'}.',
        'Use the reference photo only as composition and color inspiration.',
        'Do not make the image dark, black, gloomy, or heavily filtered.',
        'Keep it bright, painterly, soft, and emotionally calm.',
        if (width != null || height != null)
          'Preferred size hint: ${width ?? 'auto'} x ${height ?? 'auto'}.',
        'Diary text context:',
        diaryText,
      ].join('\n');

      final parts = <Map<String, Object?>>[
        {'text': prompt},
      ];
      if (fallbackImageBytes != null && fallbackImageBytes.isNotEmpty) {
        final prepared = await compute(_prepareCloudReferenceImage, {
          'bytes': fallbackImageBytes,
        });
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(prepared),
          },
        });
      }

      final body = {
        'contents': [
          {'parts': parts}
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
        },
      };

      final response = await http
          .post(
            Uri.parse(_geminiImageEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = (candidates.first as Map<String, dynamic>)['content']
          as Map<String, dynamic>?;
      final partsJson = content?['parts'] as List<dynamic>?;
      if (partsJson == null) return null;

      for (final part in partsJson) {
        final map = part as Map<String, dynamic>;
        final inlineData = map['inlineData'] as Map<String, dynamic>? ??
            map['inline_data'] as Map<String, dynamic>?;
        final data = inlineData?['data'] as String?;
        if (data != null && data.isNotEmpty) {
          return base64Decode(data);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Uint8List _generateLocalDiaryCardImage(String diaryText,
      {int? width, int? height}) {
    final int w = (width ?? 960).clamp(512, 1536).toInt();
    final int h = (height ?? 960).clamp(512, 1536).toInt();
    final canvas = image_lib.Image(width: w, height: h);
    final hash = diaryText.codeUnits
        .fold<int>(0, (value, unit) => (value + unit) & 0xFF);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x / w;
        final dy = y / h;
        final r = (246 - (dy * 22) + (hash % 14)).round().clamp(0, 255);
        final g = (235 - (dx * 12) + (hash % 10)).round().clamp(0, 255);
        final b = (218 + (dy * 18) - (hash % 8)).round().clamp(0, 255);
        canvas.setPixelRgb(x, y, r, g, b);
      }
    }

    final margin = (w * 0.12).round();
    final top = (h * 0.18).round();
    final bottom = (h * 0.78).round();
    for (var y = top; y < bottom; y += 38) {
      for (var x = margin; x < w - margin; x++) {
        canvas.setPixelRgb(x, y, 226, 208, 188);
      }
    }
    for (var y = (h * 0.24).round(); y < (h * 0.62).round(); y++) {
      final double t = (y - h * 0.24) / (h * 0.38);
      final center = (w * (0.45 + 0.08 * t)).round();
      final radius = (w * (0.12 + 0.03 * t)).round();
      for (var x = center - radius; x <= center + radius; x++) {
        if (x < 0 || x >= w) continue;
        final dist = (x - center).abs() / radius;
        if (dist <= 1) {
          final alpha = 1 - dist;
          final r = (220 + 18 * alpha).round();
          final g = (196 + 22 * alpha).round();
          final b = (172 + 24 * alpha).round();
          canvas.setPixelRgb(x, y, r, g, b);
        }
      }
    }

    return Uint8List.fromList(image_lib.encodeJpg(canvas, quality: 92));
  }

  Future<Uint8List> _generateLocalPastelImage(
    Uint8List sourceBytes, {
    int? width,
    int? height,
    String? style,
  }) async {
    final message = <String, Object?>{
      'bytes': sourceBytes,
      'width': width,
      'height': height,
      'style': style,
    };
    try {
      return await compute(_renderPainterlyImage, message);
    } catch (_) {
      try {
        return _renderPainterlyImage(message);
      } catch (_) {
        return _generateLocalPastelImageLegacy(sourceBytes);
      }
    }
  }

  Future<Uint8List> _generateLocalPastelImageLegacy(
      Uint8List sourceBytes) async {
    try {
      final img = image_lib.decodeImage(sourceBytes);
      if (img == null) return sourceBytes;

      final source = image_lib.copyResize(
        img,
        width: img.width > 640 ? 640 : img.width,
        interpolation: image_lib.Interpolation.average,
      );
      final softened = image_lib.gaussianBlur(source, radius: 1);
      final base = image_lib.adjustColor(
        softened,
        saturation: 0.9,
        brightness: 1.05,
        contrast: 1.05,
        gamma: 0.9,
      );
      final painted = _paintBrushStrokes(base);
      final output = _averageLuma(painted) < 28 ? base : painted;

      return Uint8List.fromList(image_lib.encodeJpg(output, quality: 92));
    } catch (_) {
      return sourceBytes;
    }
  }

  image_lib.Image _paintBrushStrokes(image_lib.Image source) {
    final w = source.width;
    final h = source.height;
    final canvas = image_lib.Image(width: w, height: h);
    final paper = image_lib.gaussianBlur(source, radius: 7);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = _readRgb(paper, x, y);
        final texture = _textureAt(x, y);
        final r = (p.r * 0.82 + 244 * 0.18 + texture).round().clamp(0, 255);
        final g = (p.g * 0.82 + 236 * 0.18 + texture).round().clamp(0, 255);
        final b = (p.b * 0.82 + 222 * 0.18 + texture).round().clamp(0, 255);
        canvas.setPixelRgb(x, y, r, g, b);
      }
    }

    _paintStrokeLayer(canvas, source,
        step: 13, length: 24, width: 5, opacity: 0.5);
    _paintStrokeLayer(canvas, source,
        step: 8, length: 17, width: 4, opacity: 0.62);
    _paintStrokeLayer(canvas, source,
        step: 5, length: 9, width: 2, opacity: 0.48);
    _softenStrongEdges(canvas, source);

    return image_lib.adjustColor(
      canvas,
      saturation: 1.08,
      brightness: 1.03,
      contrast: 0.97,
      gamma: 0.98,
    );
  }

  void _paintStrokeLayer(
    image_lib.Image canvas,
    image_lib.Image source, {
    required int step,
    required int length,
    required int width,
    required double opacity,
  }) {
    for (var y = step ~/ 2; y < source.height; y += step) {
      for (var x = step ~/ 2; x < source.width; x += step) {
        final jitter = _hash2(x, y);
        final sx = (x + jitter % step - step ~/ 2).clamp(0, source.width - 1);
        final sy =
            (y + (jitter ~/ 7) % step - step ~/ 2).clamp(0, source.height - 1);
        final color =
            _sampleColor(source, sx, sy, radius: math.max(1, step ~/ 3));
        final angle =
            _strokeAngle(source, sx, sy) + ((jitter % 17) - 8) * 0.025;
        final strokeLength = length + (jitter % 7) - 3;
        _drawBrushStroke(
          canvas,
          sx,
          sy,
          color,
          angle: angle,
          halfLength: math.max(4, strokeLength),
          halfWidth: width,
          opacity: opacity,
        );
      }
    }
  }

  void _drawBrushStroke(
    image_lib.Image canvas,
    int cx,
    int cy,
    _Rgb color, {
    required double angle,
    required int halfLength,
    required int halfWidth,
    required double opacity,
  }) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final minX = (cx - halfLength - halfWidth).clamp(0, canvas.width - 1);
    final maxX = (cx + halfLength + halfWidth).clamp(0, canvas.width - 1);
    final minY = (cy - halfLength - halfWidth).clamp(0, canvas.height - 1);
    final maxY = (cy + halfLength + halfWidth).clamp(0, canvas.height - 1);

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final dx = x - cx;
        final dy = y - cy;
        final localX = dx * cosA + dy * sinA;
        final localY = -dx * sinA + dy * cosA;
        if (localX.abs() > halfLength) continue;

        final taper = 1 - (localX.abs() / halfLength) * 0.55;
        final edge = localY.abs() / (halfWidth * taper + 0.5);
        if (edge > 1) continue;

        final bristle = 0.78 + (_hash2(x, y) % 18) / 100;
        final alpha = opacity * (1 - edge * edge) * bristle;
        _blendPixel(
          canvas,
          x,
          y,
          (color.r * bristle).round().clamp(0, 255),
          (color.g * bristle).round().clamp(0, 255),
          (color.b * bristle).round().clamp(0, 255),
          alpha.clamp(0, 1),
        );
      }
    }
  }

  void _softenStrongEdges(image_lib.Image canvas, image_lib.Image source) {
    for (var y = 2; y < source.height - 2; y += 2) {
      for (var x = 2; x < source.width - 2; x += 2) {
        final gradient =
            (_luma(source, x + 2, y) - _luma(source, x - 2, y)).abs() +
                (_luma(source, x, y + 2) - _luma(source, x, y - 2)).abs();
        if (gradient < 38) continue;
        final p = _readRgb(source, x, y);
        _blendPixel(
          canvas,
          x,
          y,
          (p.r * 0.72).round(),
          (p.g * 0.72).round(),
          (p.b * 0.72).round(),
          0.24,
        );
      }
    }
  }

  _Rgb _sampleColor(image_lib.Image image, int cx, int cy,
      {required int radius}) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var count = 0;
    for (var y = cy - radius; y <= cy + radius; y++) {
      if (y < 0 || y >= image.height) continue;
      for (var x = cx - radius; x <= cx + radius; x++) {
        if (x < 0 || x >= image.width) continue;
        final p = _readRgb(image, x, y);
        r += p.r;
        g += p.g;
        b += p.b;
        count++;
      }
    }
    if (count == 0) return const _Rgb(230, 220, 205);
    return _Rgb(
      (r / count).round(),
      (g / count).round(),
      (b / count).round(),
    );
  }

  double _strokeAngle(image_lib.Image image, int x, int y) {
    final left = _luma(image, (x - 2).clamp(0, image.width - 1), y);
    final right = _luma(image, (x + 2).clamp(0, image.width - 1), y);
    final top = _luma(image, x, (y - 2).clamp(0, image.height - 1));
    final bottom = _luma(image, x, (y + 2).clamp(0, image.height - 1));
    return math.atan2(bottom - top, right - left) + math.pi / 2;
  }

  double _luma(image_lib.Image image, int x, int y) {
    final p = _readRgb(image, x, y);
    return p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
  }

  double _averageLuma(image_lib.Image image) {
    var total = 0.0;
    var count = 0;
    final step = math.max(1, math.min(image.width, image.height) ~/ 80);
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        total += _luma(image, x, y);
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  _Rgb _readRgb(image_lib.Image image, int x, int y) {
    final p = image.getPixel(x, y);
    return _Rgb(
      (p.rNormalized * 255).round().clamp(0, 255),
      (p.gNormalized * 255).round().clamp(0, 255),
      (p.bNormalized * 255).round().clamp(0, 255),
    );
  }

  int _textureAt(int x, int y) => (_hash2(x, y) % 17) - 8;

  int _hash2(int x, int y) {
    var v = x * 374761393 + y * 668265263;
    v = (v ^ (v >> 13)) * 1274126177;
    return (v ^ (v >> 16)) & 0x7fffffff;
  }

  void _blendPixel(
    image_lib.Image image,
    int x,
    int y,
    int r,
    int g,
    int b,
    double alpha,
  ) {
    final dst = image.getPixel(x, y);
    final inv = 1 - alpha;
    image.setPixelRgb(
      x,
      y,
      ((dst.rNormalized * 255) * inv + r * alpha).round().clamp(0, 255),
      ((dst.gNormalized * 255) * inv + g * alpha).round().clamp(0, 255),
      ((dst.bNormalized * 255) * inv + b * alpha).round().clamp(0, 255),
    );
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
    final memoLine =
        memo.trim().isEmpty ? '' : "\n\n메모로 남긴 '$memo'라는 말이 오늘의 중심에 조용히 남았다.";
    final photoLine =
        photoCount == 0 ? '' : '\n\n사진 $photoCount장이 오늘의 색을 붙잡아 주었다.';

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

Uint8List _renderPainterlyImage(Map<String, Object?> message) {
  final sourceBytes = message['bytes'] as Uint8List;
  final width = message['width'] as int?;
  final height = message['height'] as int?;

  final decoded = image_lib.decodeImage(sourceBytes);
  if (decoded == null) return sourceBytes;

  final oriented = image_lib.bakeOrientation(decoded);
  final maxSide = _targetMaxSide(oriented, width: width, height: height);
  final resized = _resizeByMaxSide(oriented, maxSide);

  final softened = image_lib.gaussianBlur(resized, radius: 2);
  final vivid = image_lib.adjustColor(
    softened,
    saturation: 1.18,
    brightness: 1.09,
    contrast: 1.06,
    gamma: 0.92,
  );
  final detail = image_lib.adjustColor(
    resized,
    saturation: 1.05,
    brightness: 1.04,
    contrast: 1.02,
    gamma: 0.95,
  );

  final canvas = image_lib.Image(width: vivid.width, height: vivid.height);
  final cx = (canvas.width - 1) / 2;
  final cy = (canvas.height - 1) / 2;
  final maxRadius = math.sqrt(cx * cx + cy * cy);

  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final p = _readRgbFast(vivid, x, y);
      final d = _readRgbFast(detail, x, y);
      final q = _posterizePastel(p, x, y);
      final texture = (_hashFast(x, y) % 13) - 6;
      final dist = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      final vignette = (1 - (dist / maxRadius) * 0.06).clamp(0.92, 1.0);
      final r = ((q.r * 0.72 + d.r * 0.16 + 250 * 0.12 + texture) * vignette)
          .round();
      final g = ((q.g * 0.72 + d.g * 0.16 + 242 * 0.12 + texture) * vignette)
          .round();
      final b = ((q.b * 0.72 + d.b * 0.16 + 230 * 0.12 + texture) * vignette)
          .round();
      canvas.setPixelRgb(
        x,
        y,
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      );
    }
  }

  _drawPainterlyStrokeLayer(canvas, vivid, step: 11, length: 13, opacity: 0.30);
  _drawPainterlyStrokeLayer(canvas, vivid, step: 7, length: 8, opacity: 0.24);
  _drawSubtleDiaryEdges(canvas, resized);

  final adjusted = _averageLumaFast(canvas) < 44
      ? image_lib.adjustColor(canvas, brightness: 1.18, contrast: 0.9)
      : canvas;

  return Uint8List.fromList(image_lib.encodeJpg(adjusted, quality: 88));
}

@visibleForTesting
Uint8List debugRenderPainterlyImageForTest(Uint8List sourceBytes) {
  return _renderPainterlyImage({'bytes': sourceBytes});
}

_Rgb _posterizePastel(_Rgb color, int x, int y) {
  int quantize(int v, int levels) {
    final q = (v / 255 * (levels - 1)).round();
    return (q * 255 / (levels - 1)).round().clamp(0, 255);
  }

  final levels = 11 + (_hashFast(x ~/ 24, y ~/ 24) % 4);
  final r = quantize(color.r, levels);
  final g = quantize(color.g, levels);
  final b = quantize(color.b, levels);
  final luma = (r * 0.299 + g * 0.587 + b * 0.114);
  final lift = luma < 86 ? 24 : 12;
  return _Rgb(
    (r * 0.86 + 255 * 0.14 + lift).round().clamp(0, 255),
    (g * 0.86 + 246 * 0.14 + lift).round().clamp(0, 255),
    (b * 0.86 + 232 * 0.14 + lift).round().clamp(0, 255),
  );
}

void _drawPainterlyStrokeLayer(
  image_lib.Image canvas,
  image_lib.Image source, {
  required int step,
  required int length,
  required double opacity,
}) {
  for (var y = step ~/ 2; y < source.height; y += step) {
    for (var x = step ~/ 2; x < source.width; x += step) {
      final jitter = _hashFast(x, y);
      final sx = (x + jitter % step - step ~/ 2).clamp(0, source.width - 1);
      final sy =
          (y + (jitter ~/ 9) % step - step ~/ 2).clamp(0, source.height - 1);
      final color = _posterizePastel(_readRgbFast(source, sx, sy), sx, sy);
      final angle = _strokeAngleFast(source, sx, sy) + ((jitter % 21) - 10) * 0.025;
      final strokeLength = math.max(4, length + (jitter % 7) - 3);
      _drawPainterlyStroke(
        canvas,
        sx,
        sy,
        color,
        angle: angle,
        length: strokeLength,
        opacity: opacity,
      );
    }
  }
}

void _drawPainterlyStroke(
  image_lib.Image canvas,
  int cx,
  int cy,
  _Rgb color, {
  required double angle,
  required int length,
  required double opacity,
}) {
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  final halfWidth = math.max(1, length ~/ 4);
  for (var i = -length; i <= length; i++) {
    final t = i / length;
    final fade = (1 - t.abs() * 0.62) * opacity;
    final centerX = cx + i * cosA;
    final centerY = cy + i * sinA;
    for (var w = -halfWidth; w <= halfWidth; w++) {
      final edge = 1 - (w.abs() / (halfWidth + 1));
      final x = (centerX - w * sinA).round();
      final y = (centerY + w * cosA).round();
      if (x < 0 || x >= canvas.width || y < 0 || y >= canvas.height) continue;
      final bristle = 0.92 + (_hashFast(x, y) % 17) / 100;
      _blendPixelFast(
        canvas,
        x,
        y,
        (color.r * bristle).round().clamp(0, 255),
        (color.g * bristle).round().clamp(0, 255),
        (color.b * bristle).round().clamp(0, 255),
        (fade * edge).clamp(0, 1),
      );
    }
  }
}

double _strokeAngleFast(image_lib.Image image, int x, int y) {
  final left = _lumaFast(image, (x - 2).clamp(0, image.width - 1), y);
  final right = _lumaFast(image, (x + 2).clamp(0, image.width - 1), y);
  final top = _lumaFast(image, x, (y - 2).clamp(0, image.height - 1));
  final bottom = _lumaFast(image, x, (y + 2).clamp(0, image.height - 1));
  return math.atan2(bottom - top, right - left) + math.pi / 2;
}

void _drawSubtleDiaryEdges(image_lib.Image canvas, image_lib.Image source) {
  for (var y = 2; y < source.height - 2; y += 2) {
    for (var x = 2; x < source.width - 2; x += 2) {
      final gradient =
          (_lumaFast(source, x + 2, y) - _lumaFast(source, x - 2, y)).abs() +
              (_lumaFast(source, x, y + 2) - _lumaFast(source, x, y - 2)).abs();
      if (gradient < 42) continue;
      final p = _readRgbFast(source, x, y);
      final edgeTone = _posterizePastel(p, x, y);
      _blendPixelFast(
        canvas,
        x,
        y,
        (edgeTone.r * 0.68).round().clamp(0, 255),
        (edgeTone.g * 0.68).round().clamp(0, 255),
        (edgeTone.b * 0.68).round().clamp(0, 255),
        0.16,
      );
    }
  }
}

Uint8List _prepareCloudReferenceImage(Map<String, Object?> message) {
  final sourceBytes = message['bytes'] as Uint8List;
  final decoded = image_lib.decodeImage(sourceBytes);
  if (decoded == null) return sourceBytes;
  final oriented = image_lib.bakeOrientation(decoded);
  final resized = _resizeByMaxSide(oriented, 1024);
  return Uint8List.fromList(image_lib.encodeJpg(resized, quality: 86));
}

int _targetMaxSide(image_lib.Image source, {int? width, int? height}) {
  final requested = math.max(width ?? 0, height ?? 0);
  if (requested > 0) return requested.clamp(512, 1024).toInt();
  final sourceMax = math.max(source.width, source.height);
  if (sourceMax < 512) return sourceMax;
  return 768;
}

image_lib.Image _resizeByMaxSide(image_lib.Image source, int maxSide) {
  final sourceMax = math.max(source.width, source.height);
  if (sourceMax <= maxSide) return image_lib.Image.from(source);
  if (source.width >= source.height) {
    return image_lib.copyResize(
      source,
      width: maxSide,
      interpolation: image_lib.Interpolation.average,
    );
  }
  return image_lib.copyResize(
    source,
    height: maxSide,
    interpolation: image_lib.Interpolation.average,
  );
}

double _averageLumaFast(image_lib.Image image) {
  var total = 0.0;
  var count = 0;
  final step = math.max(1, math.min(image.width, image.height) ~/ 96);
  for (var y = 0; y < image.height; y += step) {
    for (var x = 0; x < image.width; x += step) {
      total += _lumaFast(image, x, y);
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

double _lumaFast(image_lib.Image image, int x, int y) {
  final p = _readRgbFast(image, x, y);
  return p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
}

_Rgb _readRgbFast(image_lib.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return _Rgb(
    (p.rNormalized * 255).round().clamp(0, 255),
    (p.gNormalized * 255).round().clamp(0, 255),
    (p.bNormalized * 255).round().clamp(0, 255),
  );
}

void _blendPixelFast(
  image_lib.Image image,
  int x,
  int y,
  int r,
  int g,
  int b,
  double alpha,
) {
  final dst = image.getPixel(x, y);
  final inv = 1 - alpha;
  image.setPixelRgb(
    x,
    y,
    ((dst.rNormalized * 255) * inv + r * alpha).round().clamp(0, 255),
    ((dst.gNormalized * 255) * inv + g * alpha).round().clamp(0, 255),
    ((dst.bNormalized * 255) * inv + b * alpha).round().clamp(0, 255),
  );
}

int _hashFast(int x, int y) {
  var v = x * 374761393 + y * 668265263;
  v = (v ^ (v >> 13)) * 1274126177;
  return (v ^ (v >> 16)) & 0x7fffffff;
}

class _Rgb {
  final int r;
  final int g;
  final int b;

  const _Rgb(this.r, this.g, this.b);
}
