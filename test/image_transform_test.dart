import 'dart:typed_data';

import 'package:ai_diary/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('local diary transform keeps image visibly bright', () {
    final source = image_lib.Image(width: 96, height: 96);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          155 + (x % 40),
          118 + (y % 35),
          86 + ((x + y) % 45),
        );
      }
    }

    final transformed = debugRenderPainterlyImageForTest(
      Uint8List.fromList(image_lib.encodeJpg(source)),
    );
    final decoded = image_lib.decodeImage(transformed);

    expect(decoded, isNotNull);
    expect(_averageLuma(decoded!), greaterThan(60));
  });
}

double _averageLuma(image_lib.Image image) {
  var total = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final p = image.getPixel(x, y);
      total += (p.rNormalized * 255) * 0.299 +
          (p.gNormalized * 255) * 0.587 +
          (p.bNormalized * 255) * 0.114;
      count++;
    }
  }
  return total / count;
}
