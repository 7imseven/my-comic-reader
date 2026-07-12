import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/video_item.dart';
import '../models/video_bookmark.dart';

class VideoStorageService {
  static final VideoStorageService _instance = VideoStorageService._();
  factory VideoStorageService() => _instance;
  VideoStorageService._();

  late Directory _appDir;
  late Directory _videosDir;
  late Directory _coversDir;
  List<VideoItem> _videos = [];
  List<String> _tags = [];
  List<VideoBookmark> _bookmarks = [];
  int _nextId = 1;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    _appDir = await getApplicationDocumentsDirectory();
    _videosDir = Directory('${_appDir.path}/videos');
    _coversDir = Directory('${_appDir.path}/video_covers');
    if (!_videosDir.existsSync()) _videosDir.createSync(recursive: true);
    if (!_coversDir.existsSync()) _coversDir.createSync(recursive: true);
    await _loadMeta();
    await _loadBookmarks();
    _initialized = true;
  }

  String get _metaPath => '${_appDir.path}/meta_videos.json';
  String get _tagsPath => '${_appDir.path}/meta_video_tags.json';
  String get _bookmarksPath => '${_appDir.path}/meta_video_bookmarks.json';

  Future<void> _loadMeta() async {
    final file = File(_metaPath);
    if (file.existsSync()) {
      try {
        final text = await file.readAsString();
        final list = json.decode(text) as List<dynamic>;
        _videos = list.map((e) => VideoItem.fromJson(e as Map<String, dynamic>)).toList();
        _nextId = _videos.isEmpty ? 1 : _videos.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
      } catch (_) { _videos = []; _nextId = 1; }
    }
    final tagFile = File(_tagsPath);
    if (tagFile.existsSync()) {
      try {
        final text = await tagFile.readAsString();
        _tags = (json.decode(text) as List<dynamic>).map((e) => e as String).toList();
      } catch (_) { _tags = []; }
    }
    if (_tags.isEmpty) _tags = ['默认'];
  }

  Future<void> _saveMeta() async {
    await File(_metaPath).writeAsString(json.encode(_videos.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveTags() async {
    await File(_tagsPath).writeAsString(json.encode(_tags));
  }

  // ===== Bookmarks =====

  Future<void> _loadBookmarks() async {
    final file = File(_bookmarksPath);
    if (file.existsSync()) {
      try {
        final text = await file.readAsString();
        final list = json.decode(text) as List<dynamic>;
        _bookmarks = list.map((e) => VideoBookmark.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) { _bookmarks = []; }
    }
  }

  Future<void> _saveBookmarks() async {
    await File(_bookmarksPath).writeAsString(json.encode(_bookmarks.map((b) => b.toJson()).toList()));
  }

  List<VideoBookmark> getBookmarksForVideo(int videoId) {
    return _bookmarks.where((b) => b.videoId == videoId).toList()
      ..sort((a, b) => a.timeInSeconds.compareTo(b.timeInSeconds));
  }

  // ===== Public API with lazy init =====

  Future<List<VideoItem>> getAllVideos() async { await _ensureInit(); return List.of(_videos); }

  Future<List<String>> getAllTags() async { await _ensureInit(); return List.of(_tags); }

  Future<List<VideoItem>> getVideosByTag(String tag) async {
    await _ensureInit();
    return _videos.where((v) => v.tags.contains(tag)).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<Map<String, int>> getTagCounts() async {
    await _ensureInit();
    final map = <String, int>{};
    for (final tag in _tags) { map[tag] = _videos.where((v) => v.tags.contains(tag)).length; }
    return map;
  }

  Future<VideoItem?> getVideo(int id) async { await _ensureInit(); return _videos.cast<VideoItem?>().firstWhere((v) => v!.id == id, orElse: () => null); }

  Future<void> addTag(String tag) async { await _ensureInit(); if (!_tags.contains(tag)) { _tags.add(tag); await _saveTags(); } }

  Future<void> removeTag(String tag) async {
    await _ensureInit();
    _tags.remove(tag);
    for (final v in _videos) {
      if (v.tags.contains(tag)) { v.tags.remove(tag); if (v.tags.isEmpty) v.tags.add('默认'); }
    }
    await _saveMeta(); await _saveTags();
  }

  Future<void> renameVideo(int id, String newName) async {
    await _ensureInit();
    try { _videos.firstWhere((v) => v.id == id).name = newName; await _saveMeta(); } catch (_) {}
  }

  Future<int> importVideo(File sourceFile, List<String> tags) async {
    await _ensureInit();
    final path = sourceFile.path;
    final fileName = path.split(Platform.pathSeparator).last;
    final id = _nextId++;
    final destName = '$id-$fileName';
    final destPath = '${_videosDir.path}/$destName';
    await sourceFile.copy(destPath);
    final fileSize = await File(destPath).length();

    for (final tag in tags) { if (!_tags.contains(tag)) _tags.add(tag); }
    _videos.add(VideoItem(id: id, name: fileName, addedAt: DateTime.now(), fileName: destName, fileSize: fileSize, tags: tags, hasCover: false));
    await _saveMeta(); await _saveTags();

    // 缩略图异步生成，不阻塞导入流程
    // iOS 上 VideoThumbnail 可能因不支持的格式(avi/mkv等)阻塞平台通道，
    // 放在 import 返回后独立执行，即使挂死也不影响导入
    _generateThumbnailAsync(id, destPath);
    return id;
  }

  void _generateThumbnailAsync(int videoId, String videoPath) {
    // 异步执行，不阻塞调用者。成功时更新 hasCover 并保存元数据
    VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: '${_coversDir.path}/$videoId.jpg',
      imageFormat: ImageFormat.JPEG,
      maxWidth: 200,
      quality: 70,
      timeMs: 10000,
    ).then((thumbPath) {
      if (thumbPath == null) return;
      final idx = _videos.indexWhere((v) => v.id == videoId);
      if (idx < 0) return;
      _videos[idx].hasCover = true;
      _saveMeta();
    }).catchError((_) {
      // 缩略图生成失败不影响功能
    });
  }

  Future<int> scanSandbox() async {
    await _ensureInit();
    final knownIds = _videos.map((v) => v.id).toSet();
    final files = _videosDir.listSync().whereType<File>().toList();
    int restored = 0;
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      // Parse "123-filename.mp4" format
      final dashIdx = name.indexOf('-');
      if (dashIdx <= 0) continue;
      final id = int.tryParse(name.substring(0, dashIdx));
      if (id == null || knownIds.contains(id)) continue;

      final fileName = name.substring(dashIdx + 1);
      final video = VideoItem(
        id: id, name: fileName, addedAt: DateTime.now(),
        fileName: name, fileSize: await f.length(),
        tags: ['默认'], hasCover: File('${_coversDir.path}/$id.jpg').existsSync(),
      );
      _videos.add(video);
      knownIds.add(id);
      restored++;
    }
    if (restored > 0) {
      _nextId = _videos.map((v) => v.id).reduce((a, b) => a > b ? a : b) + 1;
      await _saveMeta();
    }
    return restored;
  }

  Future<void> deleteVideo(int id) async {
    await _ensureInit();
    // Get file info before removing from list
    String? fileName;
    try {
      final v = _videos.firstWhere((v) => v.id == id);
      fileName = v.fileName;
    } catch (_) {}
    _videos.removeWhere((v) => v.id == id);
    if (fileName != null) {
      try { await File('${_videosDir.path}/$fileName').delete(); } catch (_) {}
    }
    try { await File('${_coversDir.path}/$id.jpg').delete(); } catch (_) {}
    _bookmarks.removeWhere((b) => b.videoId == id);
    await _saveMeta(); await _saveBookmarks();
  }

  Future<void> updateProgress(int id, int progress) async {
    await _ensureInit();
    try { _videos.firstWhere((v) => v.id == id).progress = progress; await _saveMeta(); } catch (_) {}
  }

  Future<void> updateDuration(int id, int duration) async {
    await _ensureInit();
    try { _videos.firstWhere((v) => v.id == id).duration = duration; await _saveMeta(); } catch (_) {}
  }

  String? getCoverPath(int videoId) {
    final path = '${_coversDir.path}/$videoId.jpg';
    return File(path).existsSync() ? path : null;
  }

  Future<String?> getVideoPath(int videoId) async {
    await _ensureInit();
    try {
      final v = _videos.firstWhere((v) => v.id == videoId);
      final path = '${_videosDir.path}/${v.fileName}';
      return File(path).existsSync() ? path : null;
    } catch (_) { return null; }
  }

  Future<void> addBookmark(int videoId, int timeInSeconds, String note) async {
    await _ensureInit();
    _bookmarks.add(VideoBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(), videoId: videoId,
      timeInSeconds: timeInSeconds, note: note, createdAt: DateTime.now(),
    ));
    await _saveBookmarks();
  }

  Future<void> deleteBookmark(String id) async { _bookmarks.removeWhere((b) => b.id == id); await _saveBookmarks(); }

  Future<void> updateBookmarkNote(String id, String note) async {
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx >= 0) { _bookmarks[idx].note = note; await _saveBookmarks(); }
  }

  // ===== Backup =====

  Future<void> exportBackup(String outputPath) async { await _ensureInit();
    final sink = File(outputPath).openWrite();
    int headerSize = 8;
    for (final video in _videos) { final nb = utf8.encode(video.name); final tb = utf8.encode(video.tags.join(',')); headerSize += 4 + nb.length + 4 + tb.length + 4; }
    final hd = BytesBuilder();
    _writeInt32(hd, _videos.length); _writeInt32(hd, headerSize);
    for (final video in _videos) {
      final nb = utf8.encode(video.name); final tb = utf8.encode(video.tags.join(','));
      _writeInt32(hd, nb.length); hd.add(nb); _writeInt32(hd, tb.length); hd.add(tb); _writeInt32(hd, video.fileSize);
    }
    sink.add(hd.toBytes());
    for (final video in _videos) { sink.add(await File('${_videosDir.path}/${video.fileName}').readAsBytes()); }
    await sink.close();
  }

  Future<int> importBackup(String filePath) async { await _ensureInit();
    final bytes = await File(filePath).readAsBytes(); final view = ByteData.view(bytes.buffer);
    int o = 0; final count = view.getUint32(o, Endian.little); o += 4; final hs = view.getUint32(o, Endian.little); o += 4;
    if (count <= 0 || count > 5000 || hs > bytes.length) throw FormatException('Invalid backup format');
    int dOff = hs; o = 8; int imported = 0;
    for (int i = 0; i < count; i++) {
      final nl = view.getUint32(o, Endian.little); o += 4;
      final name = utf8.decode(bytes.sublist(o, o + nl)); o += nl;
      final tl = view.getUint32(o, Endian.little); o += 4;
      final tags = utf8.decode(bytes.sublist(o, o + tl)).split(',').where((s) => s.isNotEmpty).toList(); o += tl;
      final dl = view.getUint32(o, Endian.little); o += 4;
      final data = bytes.sublist(dOff, dOff + dl); dOff += dl;
      final id = _nextId++; final dp = '${_videosDir.path}/$id-$name';
      await File(dp).writeAsBytes(data);
      for (final tag in tags) { if (!_tags.contains(tag)) _tags.add(tag); }
      _videos.add(VideoItem(id: id, name: name, addedAt: DateTime.now(), fileName: '$id-$name', fileSize: dl, tags: tags.isEmpty ? ['默认'] : tags, hasCover: false));
      _generateThumbnailAsync(id, dp);
      imported++;
    }
    await _saveMeta(); await _saveTags(); return imported;
  }

  static void _writeInt32(BytesBuilder builder, int value) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, value, Endian.little);
    builder.add(bytes);
  }
}
