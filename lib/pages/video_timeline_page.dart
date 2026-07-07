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
  bool _isGenerating = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _thumbs = _storage.getTimelineThumbnails(widget.videoId);
    _isGenerating = false;
    if (mounted) setState(() {});
  }

  void _viewImage(String path, int timeMs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(_formatTime(timeMs), style: const TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final sec = ms ~/ 1000;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text(widget.videoName, style: const TextStyle(fontSize: 15, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF222222),
        foregroundColor: Colors.white,
      ),
      body: _isGenerating
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4E6EF2)))
          : _thumbs.isEmpty
              ? const Center(child: Text('缩略图生成中，请稍后...', style: TextStyle(color: Color(0xFF888888))))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 16 / 9,
                  ),
                  itemCount: _thumbs.length,
                  itemBuilder: (_, i) {
                    final entry = _thumbs[i];
                    return GestureDetector(
                      onTap: () => _viewImage(entry.value, entry.key),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(File(entry.value), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF333333))),
                          ),
                          Positioned(
                            left: 4, bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                              child: Text(_formatTime(entry.key), style: const TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
