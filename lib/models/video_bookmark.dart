class VideoBookmark {
  final String id; // unique id
  final int videoId;
  final int timeInSeconds;
  String note;
  final DateTime createdAt;

  VideoBookmark({
    required this.id,
    required this.videoId,
    required this.timeInSeconds,
    required this.note,
    required this.createdAt,
  });

  String get formattedTime {
    final h = timeInSeconds ~/ 3600;
    final m = (timeInSeconds % 3600) ~/ 60;
    final s = timeInSeconds % 60;
    if (h > 0) return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
    return '${_pad(m)}:${_pad(s)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoId': videoId,
    'timeInSeconds': timeInSeconds,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory VideoBookmark.fromJson(Map<String, dynamic> json) => VideoBookmark(
    id: json['id'] as String,
    videoId: json['videoId'] as int,
    timeInSeconds: json['timeInSeconds'] as int,
    note: json['note'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
  );
}
