import 'dart:typed_data';

class DayContext {
  final DateTime date;
  final List<DaySegment> segments;
  final Uint8List? representativeImageBytes;

  const DayContext({
    required this.date,
    required this.segments,
    this.representativeImageBytes,
  });

  String toPromptSummary() {
    if (segments.isEmpty) return '';
    return segments.map((segment) => segment.toPromptLine()).join('\n');
  }
}

class DaySegment {
  final DateTime start;
  final DateTime end;
  final String title;
  final String source;
  final String? calendarName;
  final int photoCount;
  final String? placeHint;
  final double confidence;
  final bool included;

  const DaySegment({
    required this.start,
    required this.end,
    required this.title,
    required this.source,
    this.calendarName,
    this.photoCount = 0,
    this.placeHint,
    this.confidence = 0.5,
    this.included = true,
  });

  String get timeRange => '${_hhmm(start)}-${_hhmm(end)}';

  String toPromptLine() {
    final parts = <String>[
      '- $timeRange $title',
      if (calendarName != null && calendarName!.trim().isNotEmpty) '캘린더: $calendarName',
      if (photoCount > 0) '사진 $photoCount장',
      if (placeHint != null && placeHint!.trim().isNotEmpty) '장소 힌트: $placeHint',
      '추론 신뢰도: ${(confidence * 100).round()}%',
    ];
    return parts.join(' / ');
  }

  static String _hhmm(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
