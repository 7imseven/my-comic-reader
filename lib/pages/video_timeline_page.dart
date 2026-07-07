import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/video_storage_service.dart';

class VideoTimelinePage extends StatefulWidget {
  final int videoId;
  final String videoName;
  const VideoTimelinePage({super.key, required this.videoId, required this.videoName});
  @override
  State<VideoTimelinePage> createState() => _VideoTimelinePageState();
}

class _VideoTimelinePageState extends State<VideoTimelinePage> {
  final VideoStorageService _storage = VideoStorageService();
  List<MapEntry<int, String>> _thumbs = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _storage.init();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_storage.isGeneratingThumbs(widget.videoId)) {
        _load();
      } else {
        _refreshTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _load() {
    _thumbs = _storage.getTimelineThumbnails(widget.videoId);
    if (mounted) setState(() {});
  }

  void _viewImage(String path, int timeMs) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white,
        title: Text(_formatTime(timeMs), style: const TextStyle(color: Colors.white))),
      body: Center(child: InteractiveViewer(maxScale: 4, child: Image.file(File(path), fit: BoxFit.contain))),
    )));
  }

  String _formatTime(int ms) {
    final sec = ms ~/ 1000;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isGen = _storage.isGeneratingThumbs(widget.videoId);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text(widget.videoName, style: const TextStyle(fontSize: 15, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF222222), foregroundColor: Colors.white,
      ),
      body: _thumbs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (isGen) const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4E6EF2))),
              const SizedBox(height: 12),
              Text(isGen ? '正在生成缩略图...' : '暂无缩略图', style: const TextStyle(color: Color(0xFF888888))),
            ]))
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 16 / 9),
                itemCount: _thumbs.length + (isGen ? 1 : 0),
                itemBuilder: (_, i) {
                  if (isGen && i == _thumbs.length) {
                    return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4E6EF2))));
                  }
                  final entry = _thumbs[i];
                  return GestureDetector(
                    onTap: () => _viewImage(entry.value, entry.key),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(borderRadius: BorderRadius.circular(6),
                        child: Image.file(File(entry.value), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF333333)))),
                      Positioned(left: 4, bottom: 4, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(_formatTime(entry.key), style: const TextStyle(color: Colors.white, fontSize: 10)),
                      )),
                    ]),
                  );
                },
              ),
            ),
    );
  }
}
