class VideoItem {
  final int id;
  String name;
  final DateTime addedAt;
  int progress; // seconds
  int duration; // total seconds
  final String fileName; // relative path in sandbox
  int fileSize;
  final List<String> tags;
  bool hasCover;

  VideoItem({
    required this.id,
    required this.name,
    required this.addedAt,
    this.progress = 0,
    this.duration = 0,
    required this.fileName,
    this.fileSize = 0,
    required this.tags,
    this.hasCover = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'progress': progress,
    'duration': duration,
    'fileName': fileName,
    'fileSize': fileSize,
    'tags': tags,
    'hasCover': hasCover,
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: json['id'] as int,
    name: json['name'] as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
    progress: json['progress'] as int? ?? 0,
    duration: json['duration'] as int? ?? 0,
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int? ?? 0,
    tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    hasCover: json['hasCover'] as bool? ?? false,
  );

  String get formattedDate {
    final d = addedAt;
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  }

  String get formattedDuration {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) return '${h}:${_pad(m)}:${_pad(s)}';
    return '${m}:${_pad(s)}';
  }

  String get formattedProgress {
    final h = progress ~/ 3600;
    final m = (progress % 3600) ~/ 60;
    final s = progress % 60;
    if (h > 0) return '${h}:${_pad(m)}:${_pad(s)}';
    return '${m}:${_pad(s)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
