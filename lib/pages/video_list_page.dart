import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/video_storage_service.dart';
import 'video_player_page.dart';
import 'video_timeline_page.dart';

class VideoListPage extends StatefulWidget {
  final String tag;
  const VideoListPage({super.key, required this.tag});
  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  final VideoStorageService _storage = VideoStorageService();
  List<VideoItem> _videos = [];

  @override
  void initState() {
    super.initState();
    _initAndReload();
  }

  Future<void> _initAndReload() async {
    await _storage.init();
    _reload();
  }

  void _reload() {
    setState(() {
      _videos = _storage.getVideosByTag(widget.tag);
    });
  }

  Future<void> _deleteVideo(VideoItem video) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除视频'),
        content: Text('确定删除「${video.name}」？\n此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _storage.deleteVideo(video.id);
    _reload();
  }

  void _openVideo(VideoItem video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlayerPage(videoId: video.id)),
    ).then((_) => _reload());
  }

  Future<void> _renameVideo(VideoItem video) async {
    final controller = TextEditingController(text: video.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名视频'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '输入新名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != video.name) {
      await _storage.renameVideo(video.id, newName);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('📁 ${widget.tag}'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: _videos.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('📭', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text('该分类下没有视频', style: TextStyle(color: Color(0xFF999999), fontSize: 15)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              itemCount: _videos.length,
              itemBuilder: (_, index) => _buildVideoItem(_videos[index]),
            ),
    );
  }

  Widget _buildVideoItem(VideoItem video) {
    final coverPath = _storage.getCoverPath(video.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openVideo(video),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80, height: 60,
                child: coverPath != null
                    ? Image.file(File(coverPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _coverPlaceholder())
                    : _coverPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(video.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF333333)), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                video.duration > 0 ? video.formattedDuration : '加载中...',
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
              if (video.progress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('已播至 ${video.formattedProgress}', style: const TextStyle(fontSize: 11, color: Color(0xFFBBBBBB))),
                ),
            ])),
            IconButton(icon: const Icon(Icons.grid_view_outlined, size: 18, color: Color(0xFFBBBBBB)), onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoTimelinePage(videoId: video.id, videoName: video.name)));
            }),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFCCCCCC)), onPressed: () => _renameVideo(video)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCCCCCC)), onPressed: () => _deleteVideo(video)),
          ]),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: const Color(0xFFEEEEEE),
      child: const Center(child: Icon(Icons.play_arrow, color: Color(0xFFBBBBBB), size: 28)),
    );
  }
}
