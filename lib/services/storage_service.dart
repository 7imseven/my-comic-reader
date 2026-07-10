import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/comic.dart';
import 'comic_index.dart';
import 'zip_page_reader.dart';

class StorageService {
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;
  StorageService._();

  late Directory _appDir;
  late Directory _comicsDir;
  late Directory _coversDir;
  List<Comic> _comics = [];
  int _nextId = 1;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _appDir = await getApplicationDocumentsDirectory();
    _comicsDir = Directory('${_appDir.path}/comics');
    _coversDir = Directory('${_appDir.path}/covers');
    if (!_comicsDir.existsSync()) _comicsDir.createSync(recursive: true);
    if (!_coversDir.existsSync()) _coversDir.createSync(recursive: true);
    await _loadMeta();
    _initialized = true;
  }

  String get _metaPath => '${_appDir.path}/meta.json';

  Future<void> _loadMeta() async {
    final file = File(_metaPath);
    if (!file.existsSync()) {
      _comics = [];
      return;
    }
    try {
      final text = await file.readAsString();
      final list = json.decode(text) as List<dynamic>;
      _comics = list.map((e) => Comic.fromJson(e as Map<String, dynamic>)).toList();
      _nextId = _comics.isEmpty ? 1 : _comics.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
    } catch (_) {
      _comics = [];
      _nextId = 1;
    }
  }

  Future<void> _saveMeta() async {
    final text = json.encode(_comics.map((c) => c.toJson()).toList());
    await File(_metaPath).writeAsString(text);
  }

  List<Comic> get allComics => List.of(_comics);

  Comic? getComic(int id) {
    try { return _comics.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }

  /// Import a ZIP file into the app sandbox, building a ComicIndex.
  Future<int> importComic(File sourceFile) async {
    final path = sourceFile.path;
    final fileName = path.split(Platform.pathSeparator).last;
    final id = _nextId++;
    final destName = '$id-$fileName';
    final destPath = '${_comicsDir.path}/$destName';

    // Copy file to sandbox
    await sourceFile.copy(destPath);

    // Parse ZIP central directory (metadata only, no decompression)
    final entries = await ZipCentralDirectoryReader.read(destPath);
    final imageEntries = entries
        .where((e) => _isImage(e.fileName))
        .toList();
    imageEntries.sort((a, b) => _compareNames(a.fileName, b.fileName));

    final totalPages = imageEntries.length;

    // Build PageEntry list and detect chapters from folder structure
    final pages = <PageEntry>[];
    final chapterNames = <int, String>{};
    final chapterPages = <int, List<int>>{};
    String? currentFolder;
    int chapterIdx = 0;

    for (int i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final folder = _getFolderName(entry.fileName);

      if (folder != currentFolder) {
        if (currentFolder != null) chapterIdx++;
        currentFolder = folder;
      }

      if (folder != null && !chapterNames.containsKey(chapterIdx)) {
        chapterNames[chapterIdx] = folder;
      }

      pages.add(PageEntry(
        pageIndex: i,
        fileName: entry.fileName,
        offsetInZip: entry.dataOffset,
        compressedSize: entry.compressedSize,
        uncompressedSize: entry.uncompressedSize,
        imageFormat: _getExtension(entry.fileName),
        chapterIdx: chapterIdx,
      ));
      chapterPages.putIfAbsent(chapterIdx, () => []).add(i);
    }

    // Build chapter list
    final chapters = chapterPages.entries.map((e) {
      final idx = e.key;
      return ChapterEntry(
        chapterIdx: idx,
        name: chapterNames[idx] ?? '',
        startPageIndex: e.value.first,
        pageCount: e.value.length,
      );
    }).toList();

    // If no folder-based chapters, treat as single chapter
    if (chapters.isEmpty && pages.isNotEmpty) {
      chapters.add(ChapterEntry(
        chapterIdx: 0,
        name: '',
        startPageIndex: 0,
        pageCount: pages.length,
      ));
    }

    // Save index
    final index = ComicIndex(comicId: id, totalPages: totalPages, pages: pages, chapters: chapters);
    await _saveIndex(id, index);

    // Extract cover thumbnail using ZipPageReader (no Archive needed)
    bool hasCover = false;
    if (imageEntries.isNotEmpty) {
      try {
        final reader = ZipPageReader();
        await reader.open(destPath);
        final coverData = await reader.readEntry(
          imageEntries.first.dataOffset,
          imageEntries.first.compressedSize,
          imageEntries.first.uncompressedSize,
        );
        reader.close();
        final thumbData = _makeThumbnail(coverData);
        await File('${_coversDir.path}/$id.jpg').writeAsBytes(thumbData);
        hasCover = true;
      } catch (_) {}
    }

    final comic = Comic(
      id: id,
      name: fileName,
      addedAt: DateTime.now(),
      progress: 0,
      totalPages: totalPages,
      fileName: destName,
      fileSize: await File(destPath).length(),
      hasCover: hasCover,
    );

    _comics.add(comic);
    await _saveMeta();
    return id;
  }

  Future<void> deleteComic(int id) async {
    final comic = getComic(id);
    if (comic == null) return;

    final filePath = '${_comicsDir.path}/${comic.fileName}';
    try { await File(filePath).delete(); } catch (_) {}
    try { await File('${_coversDir.path}/$id.jpg').delete(); } catch (_) {}
    // Remove index file
    try { await File('${_appDir.path}/index_$id.json').delete(); } catch (_) {}

    _comics.removeWhere((c) => c.id == id);
    await _saveMeta();
  }

  /// Scan sandbox for comic files not in metadata
  Future<int> scanSandbox() async {
    final knownIds = _comics.map((c) => c.id).toSet();
    final files = _comicsDir.listSync().whereType<File>().toList();
    int restored = 0;
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final dashIdx = name.indexOf('-');
      if (dashIdx <= 0) continue;
      final id = int.tryParse(name.substring(0, dashIdx));
      if (id == null || knownIds.contains(id)) continue;

      final comic = Comic(
        id: id, name: name.substring(dashIdx + 1), addedAt: DateTime.now(),
        fileName: name, fileSize: await f.length(),
        hasCover: File('${_coversDir.path}/$id.jpg').existsSync(),
      );
      _comics.add(comic);
      knownIds.add(id);
      restored++;
    }
    if (restored > 0) {
      _nextId = _comics.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
      await _saveMeta();
    }
    return restored;
  }

  Future<void> updateProgress(int id, int progress) async {
    final comic = getComic(id);
    if (comic == null) return;
    comic.progress = progress;
    await _saveMeta();
  }

  Future<void> updateTotalPages(int id, int totalPages) async {
    final comic = getComic(id);
    if (comic == null) return;
    comic.totalPages = totalPages;
    await _saveMeta();
  }

  /// Load ZIP archive from sandbox, fix Chinese file name encoding
  Future<Archive?> loadZip(int comicId) async {
    final comic = getComic(comicId);
    if (comic == null) return null;
    final path = '${_comicsDir.path}/${comic.fileName}';
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      await _fixArchiveNames(archive);
      return archive;
    } catch (_) {
      return null;
    }
  }

  /// Fix garbled file names in archive (GBK → UTF-8)
  Future<void> _fixArchiveNames(Archive archive) async {
    for (final file in archive.files) {
      if (_looksLikeGarbled(file.name)) {
        try {
          final rawBytes = latin1.encode(file.name);
          final fixed = await CharsetConverter.decode('GBK', rawBytes);
          file.name = fixed;
        } catch (_) {}
      }
    }
  }

  /// Heuristic: name has high bytes but no CJK → likely garbled
  bool _looksLikeGarbled(String name) {
    bool hasHigh = false;
    for (final c in name.runes) {
      if (c > 0x7F && c < 0x400) hasHigh = true;
      if (c >= 0x4E00 && c <= 0x9FFF) return false;
    }
    return hasHigh;
  }

  /// Get sorted list of image files from the archive
  List<ArchiveFile> getImageFiles(Archive archive) {
    final files = archive.files
        .where((f) => f.isFile && _isImage(f.name))
        .toList();
    files.sort((a, b) => _compareNames(a.name, b.name));
    return files;
  }

  /// Get cover image file path
  String? getCoverPath(int comicId) {
    final path = '${_coversDir.path}/$comicId.jpg';
    if (File(path).existsSync()) return path;
    return null;
  }

  /// Group images into chapters based on folder structure
  List<Chapter> getChapters(List<ArchiveFile> images) {
    final Map<String, List<String>> groups = {};
    for (final f in images) {
      final path = f.name;
      final parts = path.split('/');
      String chapter;
      if (parts.length > 1 && parts[0].isNotEmpty) {
        chapter = parts.sublist(0, parts.length - 1).join(' / ');
      } else {
        chapter = '';
      }
      groups.putIfAbsent(chapter, () => []).add(path);
    }

    final chapters = groups.entries.map((e) => Chapter(
      name: e.key,
      imageNames: e.value,
    )).toList();

    chapters.sort((a, b) {
      if (a.name.isEmpty && b.name.isEmpty) return 0;
      if (a.name.isEmpty) return -1;
      if (b.name.isEmpty) return 1;
      return _compareNames(a.name, b.name);
    });

    return chapters;
  }

  // ===== Backup =====

  Future<void> exportBackup(String outputPath) async {
    final file = File(outputPath);
    final sink = file.openWrite();

    int headerSize = 8;
    for (final comic in _comics) {
      final nameBytes = utf8.encode(comic.name);
      headerSize += 4 + nameBytes.length + 4;
    }

    final headerData = BytesBuilder();
    _writeInt32(headerData, _comics.length);
    _writeInt32(headerData, headerSize);

    for (final comic in _comics) {
      final nameBytes = utf8.encode(comic.name);
      _writeInt32(headerData, nameBytes.length);
      headerData.add(nameBytes);
      _writeInt32(headerData, comic.fileSize);
    }

    sink.add(headerData.toBytes());

    for (final comic in _comics) {
      final dataPath = '${_comicsDir.path}/${comic.fileName}';
      final data = await File(dataPath).readAsBytes();
      sink.add(data);
    }

    await sink.close();
  }

  Future<int> importBackup(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final view = ByteData.view(bytes.buffer);

    int offset = 0;
    final count = view.getUint32(offset, Endian.little); offset += 4;
    final headerSize = view.getUint32(offset, Endian.little); offset += 4;

    if (count <= 0 || count > 5000 || headerSize > bytes.length) {
      throw FormatException('Invalid backup format');
    }

    // Parse header to get entries
    int dataOffset = headerSize;
    offset = 8;
    int imported = 0;

    for (int i = 0; i < count; i++) {
      final nameLen = view.getUint32(offset, Endian.little); offset += 4;
      final name = utf8.decode(bytes.sublist(offset, offset + nameLen)); offset += nameLen;
      final dataLen = view.getUint32(offset, Endian.little); offset += 4;

      // Read actual comic data
      if (dataOffset + dataLen > bytes.length) throw FormatException('Corrupted backup');
      final comicData = bytes.sublist(dataOffset, dataOffset + dataLen);
      dataOffset += dataLen;

      // Save to sandbox
      final id = _nextId++;
      final destName = '$id-$name';
      final destPath = '${_comicsDir.path}/$destName';
      await File(destPath).writeAsBytes(comicData);

      // Count pages and extract cover
      final archive = ZipDecoder().decodeBytes(comicData);
      final imageFiles = archive.files
          .where((f) => f.isFile && _isImage(f.name))
          .toList();
      final totalPages = imageFiles.length;

      final comic = Comic(
        id: id,
        name: name,
        addedAt: DateTime.now(),
        totalPages: totalPages,
        fileName: destName,
        fileSize: dataLen,
        hasCover: false,
      );

      if (imageFiles.isNotEmpty) {
        try {
          final sorted = imageFiles..sort((a, b) => _compareNames(a.name, b.name));
          final coverData = sorted.first.content as Uint8List;
          final thumbData = _makeThumbnail(coverData);
          await File('${_coversDir.path}/$id.jpg').writeAsBytes(thumbData);
          comic.hasCover = true;
        } catch (_) {}
      }

      _comics.add(comic);
      imported++;
    }

    await _saveMeta();
    return imported;
  }

  // ===== Index & ZIP Reader =====

  Future<void> _saveIndex(int comicId, ComicIndex index) async {
    final json = jsonEncode(index.toJson());
    await File('${_appDir.path}/index_$comicId.json').writeAsString(json);
  }

  Future<ComicIndex> loadIndex(int comicId) async {
    final text = await File('${_appDir.path}/index_$comicId.json').readAsString();
    return ComicIndex.fromJson(jsonDecode(text));
  }

  Future<ZipPageReader> openZipForComic(int comicId) async {
    final comic = getComic(comicId);
    if (comic == null) throw Exception('Comic not found');
    final reader = ZipPageReader();
    await reader.open('${_comicsDir.path}/${comic.fileName}');
    return reader;
  }

  static String? _getFolderName(String path) {
    final parts = path.split('/');
    return parts.length > 1 ? parts[0] : null;
  }

  static String _getExtension(String name) {
    final dot = name.lastIndexOf('.');
    return (dot >= 0) ? name.substring(dot + 1).toLowerCase() : '';
  }

  // ===== Helpers =====

  static bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
        lower.endsWith('.png') || lower.endsWith('.gif') ||
        lower.endsWith('.webp') || lower.endsWith('.bmp');
  }

  static int _compareNames(String a, String b) {
    final aParts = _splitName(a);
    final bParts = _splitName(b);
    final minLen = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < minLen; i++) {
      final aP = aParts[i];
      final bP = bParts[i];
      if (aP is num && bP is num) {
        if (aP != bP) return (aP - bP).sign.toInt();
      } else {
        final cmp = aP.toString().compareTo(bP.toString());
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  static List<dynamic> _splitName(String s) {
    final parts = <dynamic>[];
    final buf = StringBuffer();
    bool? isNum;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      final chIsNum = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
      if (isNum == null) {
        isNum = chIsNum;
        buf.write(ch);
      } else if (chIsNum == isNum) {
        buf.write(ch);
      } else {
        parts.add(isNum ? int.parse(buf.toString()) : buf.toString());
        buf.clear();
        buf.write(ch);
        isNum = chIsNum;
      }
    }
    if (buf.isNotEmpty) {
      parts.add(isNum! ? int.parse(buf.toString()) : buf.toString());
    }
    return parts;
  }

  static Uint8List _makeThumbnail(Uint8List imageData) {
    if (imageData.length > 500 * 1024) {
      return imageData.sublist(0, 500 * 1024);
    }
    return imageData;
  }

  static void _writeInt32(BytesBuilder builder, int value) {
    final bytes = Uint8List(4);
    final bd = ByteData.view(bytes.buffer);
    bd.setUint32(0, value, Endian.little);
    builder.add(bytes);
  }
}

class Chapter {
  final String name;
  final List<String> imageNames;

  Chapter({required this.name, required this.imageNames});
}
