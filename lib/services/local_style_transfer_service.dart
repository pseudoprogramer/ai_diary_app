import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:tflite_flutter/tflite_flutter.dart';

class LocalStyleTransferService {
  LocalStyleTransferService();

  static const int _styleSize = 256;
  static const int _contentSize = 384;
  static const int _styleChannels = 3;
  static const int _styleVectorSize = 100;

  static Interpreter? _stylePredictor;
  static Interpreter? _styleTransformer;

  Future<Uint8List> stylize(
    Uint8List sourceBytes, {
    String? style,
    double strength = 0.58,
  }) async {
    final decoded = image_lib.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    final source = image_lib.bakeOrientation(decoded);
    final content = _centerCropSquare(source);
    final contentInput = _resizeForModel(content, _contentSize);
    final styleInput = _makeStyleReference(style);

    final predictor = await _loadStylePredictor();
    final transformer = await _loadStyleTransformer();

    final styleBottleneck = _emptyStyleBottleneck();
    predictor.run(
      _imageToTensor(styleInput),
      styleBottleneck,
    );

    final output = _emptyImageTensor(_contentSize, _contentSize);
    transformer.runForMultipleInputs(
      [
        _imageToTensor(contentInput),
        styleBottleneck,
      ],
      {
        0: output,
      },
    );

    final stylized = _tensorToImage(output.first);
    final blended = _blendImages(
      original: contentInput,
      stylized: stylized,
      strength: strength.clamp(0.0, 0.82),
    );
    final polished = _polishDiaryImage(blended);
    return Uint8List.fromList(image_lib.encodeJpg(polished, quality: 90));
  }

  Future<Interpreter> _loadStylePredictor() async {
    final existing = _stylePredictor;
    if (existing != null) return existing;
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      'assets/models/style_predict_int8.tflite',
      options: options,
    );
    _stylePredictor = interpreter;
    return interpreter;
  }

  Future<Interpreter> _loadStyleTransformer() async {
    final existing = _styleTransformer;
    if (existing != null) return existing;
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      'assets/models/style_transfer_int8.tflite',
      options: options,
    );
    _styleTransformer = interpreter;
    return interpreter;
  }

  image_lib.Image _centerCropSquare(image_lib.Image source) {
    final side = math.min(source.width, source.height);
    final x = ((source.width - side) / 2).round();
    final y = ((source.height - side) / 2).round();
    return image_lib.copyCrop(source, x: x, y: y, width: side, height: side);
  }

  image_lib.Image _resizeForModel(image_lib.Image source, int size) {
    return image_lib.copyResize(
      source,
      width: size,
      height: size,
      interpolation: image_lib.Interpolation.average,
    );
  }

  List<List<List<List<double>>>> _imageToTensor(image_lib.Image image) {
    return [
      List.generate(image.height, (y) {
        return List.generate(image.width, (x) {
          final pixel = image.getPixel(x, y);
          return [
            pixel.rNormalized.toDouble(),
            pixel.gNormalized.toDouble(),
            pixel.bNormalized.toDouble(),
          ];
        }, growable: false);
      }, growable: false),
    ];
  }

  List<List<List<List<double>>>> _emptyImageTensor(int width, int height) {
    return [
      List.generate(height, (_) {
        return List.generate(width, (_) {
          return List.filled(_styleChannels, 0.0, growable: false);
        }, growable: false);
      }, growable: false),
    ];
  }

  List<List<List<List<double>>>> _emptyStyleBottleneck() {
    return [
      [
        [
          List.filled(_styleVectorSize, 0.0, growable: false),
        ],
      ],
    ];
  }

  image_lib.Image _tensorToImage(List<List<List<double>>> tensor) {
    final height = tensor.length;
    final width = tensor.isEmpty ? 0 : tensor.first.length;
    final image = image_lib.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = tensor[y][x];
        final r = (pixel[0].clamp(0.0, 1.0) * 255).round();
        final g = (pixel[1].clamp(0.0, 1.0) * 255).round();
        final b = (pixel[2].clamp(0.0, 1.0) * 255).round();
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  image_lib.Image _blendImages({
    required image_lib.Image original,
    required image_lib.Image stylized,
    required double strength,
  }) {
    final image = image_lib.Image(width: original.width, height: original.height);
    final keep = 1 - strength;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final a = original.getPixel(x, y);
        final b = stylized.getPixel(x, y);
        final r = ((a.rNormalized * 255) * keep + (b.rNormalized * 255) * strength)
            .round()
            .clamp(0, 255);
        final g = ((a.gNormalized * 255) * keep + (b.gNormalized * 255) * strength)
            .round()
            .clamp(0, 255);
        final bl = ((a.bNormalized * 255) * keep + (b.bNormalized * 255) * strength)
            .round()
            .clamp(0, 255);
        image.setPixelRgb(x, y, r, g, bl);
      }
    }
    return image;
  }

  image_lib.Image _polishDiaryImage(image_lib.Image source) {
    final softened = image_lib.gaussianBlur(source, radius: 1);
    return image_lib.adjustColor(
      softened,
      saturation: 0.82,
      brightness: 1.07,
      contrast: 0.9,
      gamma: 0.94,
    );
  }

  image_lib.Image _makeStyleReference(String? rawStyle) {
    final style = rawStyle?.toLowerCase() ?? '';
    final image = image_lib.Image(width: _styleSize, height: _styleSize);

    for (var y = 0; y < _styleSize; y++) {
      for (var x = 0; x < _styleSize; x++) {
        final dx = x / (_styleSize - 1);
        final dy = y / (_styleSize - 1);
        final noise = (_hash(x, y) % 25) - 12;

        late int r;
        late int g;
        late int b;
        if (style.contains('oil') ||
            style.contains('brush') ||
            style.contains('van') ||
            style.contains('붓')) {
          final swirl = math.sin((dx * 5.4 + dy * 2.8) * math.pi);
          r = (224 + 28 * swirl + 22 * dy + noise).round();
          g = (184 + 34 * math.sin((dx * 3.2 - dy * 4.8) * math.pi) + noise)
              .round();
          b = (112 + 42 * math.cos((dx * 2.5 + dy * 5.0) * math.pi) + noise)
              .round();
        } else if (style.contains('vintage') || style.contains('film')) {
          r = (220 + 18 * dy + noise).round();
          g = (196 + 12 * dx + noise).round();
          b = (166 + 10 * (1 - dy) + noise).round();
        } else {
          r = (232 + 18 * math.sin(dx * math.pi) + noise).round();
          g = (214 + 22 * math.sin((dx + dy) * math.pi) + noise).round();
          b = (196 + 24 * math.cos(dy * math.pi) + noise).round();
        }

        image.setPixelRgb(
          x,
          y,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }
    }

    _drawStyleStrokes(image, style);
    return image_lib.gaussianBlur(image, radius: 1);
  }

  void _drawStyleStrokes(image_lib.Image image, String style) {
    final bold = style.contains('oil') ||
        style.contains('brush') ||
        style.contains('van') ||
        style.contains('붓');
    final step = bold ? 9 : 14;
    final length = bold ? 18 : 11;
    final opacity = bold ? 0.56 : 0.36;

    for (var y = step ~/ 2; y < image.height; y += step) {
      for (var x = step ~/ 2; x < image.width; x += step) {
        final h = _hash(x, y);
        final angle = bold
            ? math.sin((x + h % 17) / 22) * math.pi
            : math.sin((x + y) / 48) * math.pi * 0.35;
        final pixel = image.getPixel(x, y);
        final color = _Rgb(
          (pixel.rNormalized * 255).round(),
          (pixel.gNormalized * 255).round(),
          (pixel.bNormalized * 255).round(),
        );
        _drawStroke(image, x, y, color, angle, length + h % 7, opacity);
      }
    }
  }

  void _drawStroke(
    image_lib.Image image,
    int cx,
    int cy,
    _Rgb color,
    double angle,
    int length,
    double opacity,
  ) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    for (var i = -length; i <= length; i++) {
      final fade = (1 - (i / length).abs()) * opacity;
      final x = (cx + i * cosA).round();
      final y = (cy + i * sinA).round();
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      final dst = image.getPixel(x, y);
      final inv = 1 - fade;
      image.setPixelRgb(
        x,
        y,
        ((dst.rNormalized * 255) * inv + color.r * fade).round().clamp(0, 255),
        ((dst.gNormalized * 255) * inv + color.g * fade).round().clamp(0, 255),
        ((dst.bNormalized * 255) * inv + color.b * fade).round().clamp(0, 255),
      );
    }
  }

  int _hash(int x, int y) {
    var v = x * 374761393 + y * 668265263;
    v = (v ^ (v >> 13)) * 1274126177;
    return (v ^ (v >> 16)) & 0x7fffffff;
  }
}

class _Rgb {
  final int r;
  final int g;
  final int b;

  const _Rgb(this.r, this.g, this.b);
}
