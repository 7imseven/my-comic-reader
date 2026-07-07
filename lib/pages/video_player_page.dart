import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
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

  // Swipe-to-seek
  double _dragStartX = 0;
  Duration _dragStartPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    _video = _storage.getVideo(widget.videoId);
    if (_video == null || !mounted) return;

    final path = _storage.getVideoPath(widget.videoId);
    if (path == null) return;

    _controller = VideoPlayerController.file(File(path));
    await _controller!.initialize();

    // Detect duration
    final duration = _controller!.value.duration.inSeconds;
    if (_video!.duration == 0 && duration > 0) {
      _storage.updateDuration(widget.videoId, duration);
      _video!.duration = duration;
    }

    // Restore progress
    if (_video!.progress > 0) {
      await _controller!.seekTo(Duration(seconds: _video!.progress));
    }

    _controller!.addListener(_onPlayerEvent);

    if (mounted) {
      setState(() => _isInitialized = true);
      _controller!.play();
      _autoHideControls();
    }
  }

  void _onPlayerEvent() {
    if (!mounted || !_isInitialized) return;
    final pos = _controller!.value.position.inSeconds;
    if (pos > 0 && pos % 5 == 0) {
      _storage.updateProgress(widget.videoId, pos);
    }
  }

  void _autoHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isSeeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) _autoHideControls();
    });
  }

  void _togglePlayPause() {
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {});
    _autoHideControls();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  // ===== Swipe to seek =====

  void _onDragStart(DragStartDetails details) {
    if (!_isInitialized) return;
    _dragStartX = details.localPosition.dx;
    _dragStartPosition = _controller!.value.position;
    setState(() => _isSeeking = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isInitialized) return;
    final screenWidth = context.size?.width ?? 1;
    final deltaX = details.localPosition.dx - _dragStartX;
    final ratio = deltaX / screenWidth; // -1 to 1
    final totalSec = _controller!.value.duration.inSeconds;
    final seekSec = (ratio * totalSec * 0.1).round(); // 10% per full swipe
    final targetSec = (_dragStartPosition.inSeconds + seekSec).clamp(0, totalSec);

    setState(() {
      final sign = seekSec >= 0 ? '+' : '';
      final pct = totalSec > 0 ? (seekSec.abs() * 100 / totalSec).round() : 0;
      _seekOverlayText = '${sign}${_formatDuration(Duration(seconds: seekSec.abs()))} ($pct%)';
    });

    _controller!.seekTo(Duration(seconds: targetSec));
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _isSeeking = false);
    // Save progress on seek
    final pos = _controller!.value.position.inSeconds;
    _storage.updateProgress(widget.videoId, pos);
    _autoHideControls();
  }

  // ===== Progress slider =====

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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
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
          // Video player
          Center(
            child: SizedBox(
              width: screenW,
              height: _isFullscreen ? double.infinity : displayH,
              child: VideoPlayer(_controller!),
            ),
          ),

          // Swipe-to-seek overlay (always active, even when controls hidden)
          Positioned.fill(
            child: GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _toggleControls,
              child: Container(color: Colors.transparent),
            ),
          ),

          // Seek overlay indicator
          if (_isSeeking)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _seekOverlayText,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // Top bar
          if (_controlsVisible)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 4, right: 12, bottom: 8,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    onPressed: () {
                      final pos = _controller!.value.position.inSeconds;
                      _storage.updateProgress(widget.videoId, pos);
                      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                      Navigator.pop(context);
                    },
                  ),
                  Expanded(
                    child: Text(_video?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),

          // Bottom controls
          if (_controlsVisible)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 8,
              left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Progress slider
                  VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF4E6EF2),
                      bufferedColor: Color(0x55FFFFFF),
                      backgroundColor: Color(0x33FFFFFF),
                    ),
                  ),
                  Row(children: [
                    // Play/pause
                    IconButton(
                      icon: Icon(
                        _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white, size: 28,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    // Time
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                    ),
                    const Spacer(),
                    // Fullscreen
                    IconButton(
                      icon: Icon(
                        _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white, size: 22,
                      ),
                      onPressed: _toggleFullscreen,
                    ),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
