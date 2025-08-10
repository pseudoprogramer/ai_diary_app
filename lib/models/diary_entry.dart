import 'dart:convert';

class DiaryEntry {
  final String id; // e.g., timestamp-based
  final String text;
  final String imagePath; // local file path
  final DateTime createdAt;
  final DateTime? photoTakenAt;
  final String? placeLabel;
  final double? latitude;
  final double? longitude;

  const DiaryEntry({
    required this.id,
    required this.text,
    required this.imagePath,
    required this.createdAt,
    this.photoTakenAt,
    this.placeLabel,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'photoTakenAt': photoTakenAt?.toIso8601String(),
        'placeLabel': placeLabel,
        'latitude': latitude,
        'longitude': longitude,
      };

  static DiaryEntry fromJson(Map<String, dynamic> json) => DiaryEntry(
        id: json['id'] as String,
        text: json['text'] as String,
        imagePath: json['imagePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        photoTakenAt: (json['photoTakenAt'] as String?) != null
            ? DateTime.parse(json['photoTakenAt'] as String)
            : null,
        placeLabel: json['placeLabel'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  String toJsonString() => jsonEncode(toJson());
  static DiaryEntry fromJsonString(String s) => fromJson(jsonDecode(s) as Map<String, dynamic>);
}



