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

  Future<void> addBookmark(int videoId, int timeInSeconds, String note) async {
    final bm = VideoBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      videoId: videoId,
      timeInSeconds: timeInSeconds,
      note: note,
      createdAt: DateTime.now(),
    );
    _bookmarks.add(bm);
    await _saveBookmarks();
  }

  Future<void> deleteBookmark(String id) async {
    _bookmarks.removeWhere((b) => b.id == id);
    await _saveBookmarks();
  }

  Future<void> updateBookmarkNote(String id, String note) async {
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx >= 0) { _bookmarks[idx].note = note; await _saveBookmarks(); }
  }

  List<VideoBookmark> getBookmarksForVideo(int videoId) {
    return _bookmarks.where((b) => b.videoId == videoId).toList()
      ..sort((a, b) => a.timeInSeconds.compareTo(b.timeInSeconds));
  }

  // ===== Video CRUD =====

  List<VideoItem> get allVideos => List.of(_videos);
  List<String> get allTags => List.of(_tags);

  List<VideoItem> getVideosByTag(String tag) {
    return _videos.where((v) => v.tags.contains(tag)).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Map<String, int> get tagCounts {
    final map = <String, int>{};
    for (final tag in _tags) {
      map[tag] = _videos.where((v) => v.tags.contains(tag)).length;
    }
    return map;
  }

  VideoItem? getVideo(int id) {
    try { return _videos.firstWhere((v) => v.id == id); } catch (_) { return null; }
  }

  Future<void> addTag(String tag) async {
    if (!_tags.contains(tag)) { _tags.add(tag); await _saveTags(); }
  }

  Future<void> removeTag(String tag) async {
    _tags.remove(tag); await _saveTags();
  }

  Future<int> importVideo(File sourceFile, List<String> tags) async {
    final path = sourceFile.path;
    final fileName = path.split(Platform.pathSeparator).last;
    final id = _nextId++;
    final destName = '$id-$fileName';
    final destPath = '${_videosDir.path}/$destName';
    await sourceFile.copy(destPath);
    final fileSize = await File(destPath).length();

    bool hasCover = false;
    try {
      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: destPath, thumbnailPath: '${_coversDir.path}/$id.jpg',
        imageFormat: ImageFormat.JPEG, maxWidth: 200, quality: 70,
      );
      hasCover = thumbPath != null;
    } catch (_) {}

    for (final tag in tags) { if (!_tags.contains(tag)) _tags.add(tag); }

    _videos.add(VideoItem(
      id: id, name: fileName, addedAt: DateTime.now(),
      fileName: destName, fileSize: fileSize, tags: tags, hasCover: hasCover,
    ));
    await _saveMeta(); await _saveTags();
    return id;
  }

  Future<void> deleteVideo(int id) async {
    final video = getVideo(id);
    if (video == null) return;
    try { await File('${_videosDir.path}/${video.fileName}').delete(); } catch (_) {}
    try { await File('${_coversDir.path}/$id.jpg').delete(); } catch (_) {}
    _videos.removeWhere((v) => v.id == id);
    _bookmarks.removeWhere((b) => b.videoId == id);
    await _saveMeta(); await _saveBookmarks();
  }

  Future<void> updateProgress(int id, int progress) async {
    final video = getVideo(id);
    if (video == null) return;
    video.progress = progress; await _saveMeta();
  }

  Future<void> updateDuration(int id, int duration) async {
    final video = getVideo(id);
    if (video == null) return;
    video.duration = duration; await _saveMeta();
  }

  String? getCoverPath(int videoId) {
    final path = '${_coversDir.path}/$videoId.jpg';
    return File(path).existsSync() ? path : null;
  }

  String? getVideoPath(int videoId) {
    final video = getVideo(videoId);
    if (video == null) return null;
    final path = '${_videosDir.path}/${video.fileName}';
    return File(path).existsSync() ? path : null;
  }

  // ===== Backup =====

  Future<void> exportBackup(String outputPath) async {
    final file = File(outputPath);
    final sink = file.openWrite();
    int headerSize = 8;
    for (final video in _videos) {
      final nameBytes = utf8.encode(video.name);
      final tagStr = video.tags.join(',');
      final tagBytes = utf8.encode(tagStr);
      headerSize += 4 + nameBytes.length + 4 + tagBytes.length + 4;
    }
    final headerData = BytesBuilder();
    _writeInt32(headerData, _videos.length);
    _writeInt32(headerData, headerSize);
    for (final video in _videos) {
      final nameBytes = utf8.encode(video.name);
      final tagStr = video.tags.join(',');
      final tagBytes = utf8.encode(tagStr);
      _writeInt32(headerData, nameBytes.length);
      headerData.add(nameBytes);
      _writeInt32(headerData, tagBytes.length);
      headerData.add(tagBytes);
      _writeInt32(headerData, video.fileSize);
    }
    sink.add(headerData.toBytes());
    for (final video in _videos) {
      final data = await File('${_videosDir.path}/${video.fileName}').readAsBytes();
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
    if (count <= 0 || count > 5000 || headerSize > bytes.length) throw FormatException('Invalid backup format');

    int dataOffset = headerSize;
    offset = 8;
    int imported = 0;
    for (int i = 0; i < count; i++) {
      final nameLen = view.getUint32(offset, Endian.little); offset += 4;
      final name = utf8.decode(bytes.sublist(offset, offset + nameLen)); offset += nameLen;
      final tagLen = view.getUint32(offset, Endian.little); offset += 4;
      final tagStr = utf8.decode(bytes.sublist(offset, offset + tagLen)); offset += tagLen;
      final dataLen = view.getUint32(offset, Endian.little); offset += 4;
      final tags = tagStr.isNotEmpty ? tagStr.split(',') : <String>['默认'];
      final comicData = bytes.sublist(dataOffset, dataOffset + dataLen);
      dataOffset += dataLen;
      final id = _nextId++;
      final destPath = '${_videosDir.path}/$id-$name';
      await File(destPath).writeAsBytes(comicData);

      bool hasCover = false;
      try {
        final thumbPath = await VideoThumbnail.thumbnailFile(
          video: destPath, thumbnailPath: '${_coversDir.path}/$id.jpg',
          imageFormat: ImageFormat.JPEG, maxWidth: 200, quality: 70,
        );
        hasCover = thumbPath != null;
      } catch (_) {}

      for (final tag in tags) { if (!_tags.contains(tag)) _tags.add(tag); }
      _videos.add(VideoItem(id: id, name: name, addedAt: DateTime.now(), fileName: '$id-$name', fileSize: dataLen, tags: tags, hasCover: hasCover));
      imported++;
    }
    await _saveMeta(); await _saveTags();
    return imported;
  }

  static void _writeInt32(BytesBuilder builder, int value) {
    final bytes = Uint8List(4);
    final bd = ByteData.view(bytes.buffer);
    bd.setUint32(0, value, Endian.little);
    builder.add(bytes);
  }
}
