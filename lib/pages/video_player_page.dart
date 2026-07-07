import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/video_bookmark.dart';
import '../models/video_item.dart';
import '../services/video_storage_service.dart';

class VideoPlayerPage extends StatefulWidget {
  final int videoId;
  const VideoPlayerPage({super.key, required this.videoId});
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final VideoStorageService _storage = VideoStorageService();
  VideoPlayerController? _controller;
  VideoItem? _video;
  bool _controlsVisible = true;
  bool _isInitialized = false;
  bool _isSeeking = false;
  bool _isFullscreen = false;
  String _seekOverlayText = '';
  String? _seekThumbPath;

  double _dragStartX = 0;
  Duration _dragStartPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  Timer? _hideTimer;

  Future<void> _initPlayer() async {
    _video = _storage.getVideo(widget.videoId);
    if (_video == null || !mounted) return;
    final path = _storage.getVideoPath(widget.videoId);
    if (path == null) return;

    _controller = VideoPlayerController.file(File(path));
    await _controller!.initialize();

    final duration = _controller!.value.duration.inSeconds;
    if (_video!.duration == 0 && duration > 0) {
      _storage.updateDuration(widget.videoId, duration);
      _video!.duration = duration;
    }
    if (_video!.progress > 0) {
      await _controller!.seekTo(Duration(seconds: _video!.progress));
    }
    _controller!.addListener(_onPlayerEvent);

    if (mounted) {
      setState(() => _isInitialized = true);
      _controller!.play();
      _scheduleHide();
    }
  }

  void _onPlayerEvent() {
    if (!mounted || !_isInitialized) return;
    final pos = _controller!.value.position.inSeconds;
    if (pos > 0 && pos % 5 == 0) {
      _storage.updateProgress(widget.videoId, pos);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isSeeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) _scheduleHide();
    });
  }

  void _togglePlayPause() {
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {});
    _scheduleHide();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ===== Swipe to seek =====

  void _onDragStart(DragStartDetails details) {
    if (!_isInitialized) return;
    _dragStartX = details.localPosition.dx;
    _dragStartPosition = _controller!.value.position;
    setState(() => _isSeeking = true);
    _hideTimer?.cancel();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isInitialized) return;
    final screenWidth = context.size?.width ?? 1;
    final deltaX = details.localPosition.dx - _dragStartX;
    final ratio = deltaX / screenWidth;
    final totalSec = _controller!.value.duration.inSeconds;
    final seekSec = (ratio * totalSec * 0.1).round();
    final targetSec = (_dragStartPosition.inSeconds + seekSec).clamp(0, totalSec);

    final sign = seekSec >= 0 ? '+' : '';
    final pct = totalSec > 0 ? (seekSec.abs() * 100 / totalSec).round() : 0;
    _seekOverlayText = '${sign}${_formatDuration(Duration(seconds: seekSec.abs()))} ($pct%)';

    // Look for pre-generated thumbnail at nearest 30s interval
    final nearest30s = (targetSec ~/ 30) * 30 * 1000;
    final thumbs = _storage.getTimelineThumbnails(widget.videoId);
    final match = thumbs.where((e) => e.key == nearest30s).toList();
    _seekThumbPath = match.isNotEmpty ? match.first.value : null;

    setState(() {});
    _controller!.seekTo(Duration(seconds: targetSec));
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isSeeking = false;
      _seekThumbPath = null;
    });
    final pos = _controller!.value.position.inSeconds;
    _storage.updateProgress(widget.videoId, pos);
    _scheduleHide();
  }

  // ===== Bookmarks =====

  void _addBookmark() {
    if (!_isInitialized || _controller == null) return;
    final currentSec = _controller!.value.position.inSeconds;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('书签 (${_formatDuration(Duration(seconds: currentSec))})'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: '输入备注...', border: OutlineInputBorder()), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () {
            _storage.addBookmark(widget.videoId, currentSec, controller.text.trim());
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 书签已添加'), duration: Duration(seconds: 1)));
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  void _showBookmarkList() {
    final bookmarks = _storage.getBookmarksForVideo(widget.videoId);
    if (bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有书签'), duration: Duration(seconds: 1)));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final list = List<VideoBookmark>.of(bookmarks);
        return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('📋 书签', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
          const Divider(color: Color(0xFF333333), height: 1),
          Flexible(child: ListView.builder(shrinkWrap: true, itemCount: list.length, itemBuilder: (_, i) {
            final bm = list[i];
            return Dismissible(
              key: ValueKey(bm.id), direction: DismissDirection.endToStart,
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) { _storage.deleteBookmark(bm.id); list.removeAt(i); },
              child: ListTile(
                leading: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF4E6EF2).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text(bm.formattedTime, style: const TextStyle(color: Color(0xFF4E6EF2), fontSize: 12, fontWeight: FontWeight.bold))),
                title: Text(bm.note.isNotEmpty ? bm.note : '(无备注)', style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(bm.formattedTime, style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                onTap: () { Navigator.pop(ctx); _controller!.seekTo(Duration(seconds: bm.timeInSeconds)); _controller!.play(); },
              ),
            );
          })),
        ]));
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    final screenW = MediaQuery.of(context).size.width;
    final videoW = _controller!.value.size.width;
    final videoH = _controller!.value.size.height;
    final displayH = screenW * videoH / videoW;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: SizedBox(width: screenW, height: _isFullscreen ? double.infinity : displayH, child: VideoPlayer(_controller!))),

          // Swipe overlay + tap
          Positioned.fill(
            child: GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _toggleControls,
              child: Container(color: Colors.transparent),
            ),
          ),

          // Seek overlay
          if (_isSeeking)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              left: 0, right: 0,
              child: Column(children: [
                if (_seekThumbPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_seekThumbPath!), width: 180, height: 100, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(_seekOverlayText, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),

          // Top bar
          if (_controlsVisible)
            Positioned(top: 0, left: 0, right: 0, child: Container(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 4, right: 12, bottom: 8),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Color(0x00000000)])),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22), onPressed: () {
                  final pos = _controller!.value.position.inSeconds;
                  _storage.updateProgress(widget.videoId, pos);
                  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                  Navigator.pop(context);
                }),
                Expanded(child: Text(_video?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            )),

          // Bottom controls
          if (_controlsVisible)
            Positioned(bottom: MediaQuery.of(context).padding.bottom + 8, left: 0, right: 0, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Color(0x00000000)])),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Progress bar
                SizedBox(
                  height: 48,
                  child: Center(
                    child: VideoProgressIndicator(
                      _controller!, allowScrubbing: true, padding: EdgeInsets.zero,
                      colors: const VideoProgressColors(playedColor: Color(0xFF4E6EF2), bufferedColor: Color(0x55FFFFFF), backgroundColor: Color(0x33FFFFFF)),
                    ),
                  ),
                ),
                Row(children: [
                  IconButton(icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 28), onPressed: _togglePlayPause),
                  Text('${_formatDuration(position)} / ${_formatDuration(duration)}', style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.bookmark_outline, color: Colors.white, size: 22), onPressed: _showBookmarkList),
                  IconButton(icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white, size: 22), onPressed: _addBookmark),
                  IconButton(icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 22), onPressed: _toggleFullscreen),
                ]),
              ]),
            )),
        ],
      ),
    );
  }
}
