/// 漫画页面索引。
/// 导入时由 ZIP 中央目录构建，保存为 {comicDir}/index_{comicId}.json。
/// 阅读时直接从索引中获取偏移量，无需重新解析 ZIP。
class ComicIndex {
  final int comicId;
  final int totalPages;
  final List<PageEntry> pages;
  final List<ChapterEntry> chapters;

  ComicIndex({
    required this.comicId,
    required this.totalPages,
    required this.pages,
    required this.chapters,
  });

  Map<String, dynamic> toJson() => {
    'comicId': comicId,
    'totalPages': totalPages,
    'pages': pages.map((p) => p.toJson()).toList(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };

  factory ComicIndex.fromJson(Map<String, dynamic> json) => ComicIndex(
    comicId: json['comicId'] as int,
    totalPages: json['totalPages'] as int,
    pages: (json['pages'] as List<dynamic>)
        .map((e) => PageEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    chapters: (json['chapters'] as List<dynamic>)
        .map((e) => ChapterEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 单个页面的索引条目。
class PageEntry {
  final int pageIndex;
  final String fileName;
  final int offsetInZip;      // 压缩数据在 ZIP 中的起始字节偏移
  final int compressedSize;   // 压缩后大小
  final int uncompressedSize; // 原始大小
  final String imageFormat;   // "jpg", "png", "webp" 等
  final int chapterIdx;
  final int compressionMethod; // 0=Stored, 8=Deflated

  PageEntry({
    required this.pageIndex,
    required this.fileName,
    required this.offsetInZip,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.imageFormat,
    required this.chapterIdx,
    this.compressionMethod = 8,
  });

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'fileName': fileName,
    'offsetInZip': offsetInZip,
    'compressedSize': compressedSize,
    'uncompressedSize': uncompressedSize,
    'imageFormat': imageFormat,
    'chapterIdx': chapterIdx,
    'compressionMethod': compressionMethod,
  };

  factory PageEntry.fromJson(Map<String, dynamic> json) => PageEntry(
    pageIndex: json['pageIndex'] as int,
    fileName: json['fileName'] as String,
    offsetInZip: json['offsetInZip'] as int,
    compressedSize: json['compressedSize'] as int,
    uncompressedSize: json['uncompressedSize'] as int,
    imageFormat: json['imageFormat'] as String,
    chapterIdx: json['chapterIdx'] as int,
    compressionMethod: json['compressionMethod'] as int? ?? 8,
  );
}

/// 章节信息。
class ChapterEntry {
  final int chapterIdx;
  final String name;
  final int startPageIndex; // 0-based 起始页码
  final int pageCount;

  ChapterEntry({
    required this.chapterIdx,
    required this.name,
    required this.startPageIndex,
    required this.pageCount,
  });

  Map<String, dynamic> toJson() => {
    'chapterIdx': chapterIdx,
    'name': name,
    'startPageIndex': startPageIndex,
    'pageCount': pageCount,
  };

  factory ChapterEntry.fromJson(Map<String, dynamic> json) => ChapterEntry(
    chapterIdx: json['chapterIdx'] as int,
    name: json['name'] as String,
    startPageIndex: json['startPageIndex'] as int,
    pageCount: json['pageCount'] as int,
  );
}
