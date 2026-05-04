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
    expect(_averageDelta(source, decoded), greaterThan(14));
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

double _averageDelta(image_lib.Image a, image_lib.Image b) {
  var total = 0.0;
  var count = 0;
  final width = a.width < b.width ? a.width : b.width;
  final height = a.height < b.height ? a.height : b.height;
  for (var y = 0; y < height; y += 4) {
    for (var x = 0; x < width; x += 4) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      total += ((pa.rNormalized - pb.rNormalized).abs() +
              (pa.gNormalized - pb.gNormalized).abs() +
              (pa.bNormalized - pb.bNormalized).abs()) *
          255 /
          3;
      count++;
    }
  }
  return total / count;
}
