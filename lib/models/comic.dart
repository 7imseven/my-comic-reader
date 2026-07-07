class Comic {
  final int id;
  final String name;
  final DateTime addedAt;
  int progress;
  int totalPages;
  final String fileName; // relative path in app sandbox
  int fileSize;
  bool hasCover;

  Comic({
    required this.id,
    required this.name,
    required this.addedAt,
    this.progress = 0,
    this.totalPages = 0,
    required this.fileName,
    this.fileSize = 0,
    this.hasCover = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'progress': progress,
    'totalPages': totalPages,
    'fileName': fileName,
    'fileSize': fileSize,
    'hasCover': hasCover,
  };

  factory Comic.fromJson(Map<String, dynamic> json) => Comic(
    id: json['id'] as int,
    name: json['name'] as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
    progress: json['progress'] as int? ?? 0,
    totalPages: json['totalPages'] as int? ?? 0,
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int? ?? 0,
    hasCover: json['hasCover'] as bool? ?? false,
  );

  String get formattedDate {
    final d = addedAt;
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
