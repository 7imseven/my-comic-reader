import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/comic.dart';
import '../services/storage_service.dart';
import '../services/comic_index.dart';
import '../services/zip_page_reader.dart';

class ReaderPage extends StatefulWidget {
  final int comicId;
  const ReaderPage({super.key, required this.comicId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final StorageService _storage = StorageService();
  final ScrollController _scrollController = ScrollController();
  final Map<int, Uint8List?> _pageData = {};
  final Map<int, double> _pageAspectRatios = {};
  final Set<int> _zoomedPages = {};

  Comic? _comic;
  ComicIndex? _index;
  ZipPageReader? _zipReader;
  List<Chapter> _chapters = [];
  int _totalPages = 0;
  int _currentPage = 0;
  bool _topBarVisible = true;
  bool _isLoading = true;
  String? _error;

  // Draggable scrollbar
  double _scrollbarPosition = 0;
  double _scrollbarHeight = 40;
  bool _isDragging = false;
  int _dragPreviewPage = 0;


  @override
  void initState() {
    super.initState();
    _initReader();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageData.clear();
    _pageAspectRatios.clear();
    _zipReader?.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initReader() async {
    try {
      _comic = _storage.getComic(widget.comicId);
      if (_comic == null) {
        setState(() => _error = '漫画不存在');
        return;
      }

      // Load pre-built index (metadata only, ~300KB)
      _index = await _storage.loadIndex(widget.comicId);
      _totalPages = _index!.totalPages;

      // Build chapter list from index (compatible with existing Chapter model)
      _chapters = _index!.chapters.map((c) => Chapter(
        name: c.name,
        imageNames: _index!.pages
            .where((p) => p.chapterIdx == c.chapterIdx)
            .map((p) => p.fileName)
            .toList(),
      )).toList();

      // Open ZIP for random-access page reading
      _zipReader = await _storage.openZipForComic(widget.comicId);

      if (_comic!.totalPages == 0) {
        _storage.updateTotalPages(widget.comicId, _totalPages);
      }

      setState(() => _isLoading = false);

      // Load target page and jump to progress position
      if (_comic!.progress > 0) {
        final targetIdx = _comic!.progress - 1;
        _lazyLoadAsync(targetIdx);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final offset = (_comic!.progress - 1) * MediaQuery.of(context).size.height * 0.8;
          _scrollController.jumpTo(offset.clamp(0, _scrollController.position.maxScrollExtent));
        });
      } else {
        _lazyLoadAsync(0);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  /// Batch-load a range of pages asynchronously to avoid blocking the UI
  void _batchLoad(int start, int end) {
    for (int i = start; i <= end; i++) {
      if (i >= 0 && i < _totalPages) {
        _lazyLoadAsync(i);
      }
    }
  }

  Future<void> _lazyLoadAsync(int pageIndex) async {
    if (_pageData.containsKey(pageIndex)) return;
    if (_zipReader == null || _index == null) return;
    // Yield to let UI update between image loads
    await Future.delayed(Duration.zero);
    try {
      final page = _index!.pages[pageIndex];
      final data = await _zipReader!.readEntry(
        page.offsetInZip, page.compressedSize, page.uncompressedSize,
        compressionMethod: page.compressionMethod,
      );
      _pageData[pageIndex] = data;
      // 预解码到 ImageCache：与 Image.memory(data) 使用同一 MemoryImage key
      if (mounted) precacheImage(MemoryImage(data), context);
      _cacheAspectRatio(pageIndex, data);
      _evictOutsideWindow(pageIndex, windowSize: 40);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _cacheAspectRatio(int pageIndex, Uint8List data) {
    if (_pageAspectRatios.containsKey(pageIndex)) return;
    try {
      ui.instantiateImageCodec(data).then((c) {
        c.getNextFrame().then((frameInfo) {
          final w = frameInfo.image.width.toDouble();
          final h = frameInfo.image.height.toDouble();
          if (w > 0 && h > 0 && mounted) {
            setState(() { _pageAspectRatios[pageIndex] = w / h; });
          }
          c.dispose();
        });
      });
    } catch (_) {}
  }

  /// Evict pages outside the sliding window to keep memory bounded.
  /// Keeps [windowSize] pages centered on [centerIdx].
  void _evictOutsideWindow(int centerIdx, {int windowSize = 40}) {
    final half = windowSize ~/ 2;
    final start = (centerIdx - half).clamp(0, _totalPages);
    final end = (centerIdx + half).clamp(0, _totalPages);
    _pageData.removeWhere((key, _) => key < start || key > end);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final viewH = _scrollController.position.viewportDimension;
    final scrollY = _scrollController.position.pixels;
    final estPageH = viewH * 0.8;
    final page = (scrollY / estPageH).round() + 1;
    final newPage = page.clamp(1, _totalPages);

    setState(() {
      _currentPage = newPage;
    });

    _saveProgress(newPage);

    // Lazy load pages around current position
    // Preload ahead for smooth scrolling
    final startIdx = (newPage - 1 - 10).clamp(0, _totalPages - 1);
    final endIdx = (newPage - 1 + 20).clamp(0, _totalPages - 1);
    _batchLoad(startIdx, endIdx);

    // Update scrollbar
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      final ratio = scrollY / maxScroll;
      final trackHeight = MediaQuery.of(context).size.height * 0.85;
      final thumbH = (trackHeight * (viewH / (maxScroll + viewH))).clamp(30.0, trackHeight);
      setState(() {
        _scrollbarPosition = (trackHeight - thumbH) * ratio;
        _scrollbarHeight = thumbH;
      });
    }
  }

  void _saveProgress(int page) {
    final comic = _storage.getComic(widget.comicId);
    if (comic != null && comic.progress != page) {
      _storage.updateProgress(widget.comicId, page);
    }
  }

  void _toggleTopBar() {
    setState(() => _topBarVisible = !_topBarVisible);
  }

  void _toggleZoom(int pageIndex) {
    setState(() {
      if (_zoomedPages.contains(pageIndex)) {
        _zoomedPages.remove(pageIndex);
      } else {
        _zoomedPages.add(pageIndex);
      }
    });
  }

  void _scrollToChapter(int chapterIdx) {
    if (chapterIdx < 0 || chapterIdx >= _chapters.length) return;

    // O(1) lookup from index if available, otherwise fall back to iteration
    int targetPage;
    if (_index != null && chapterIdx < _index!.chapters.length) {
      targetPage = _index!.chapters[chapterIdx].startPageIndex + 1;
    } else {
      targetPage = 1;
      for (int i = 0; i < chapterIdx; i++) {
        targetPage += _chapters[i].imageNames.length;
      }
    }

    final targetIdx = targetPage - 1;
    // Preload focused range around target chapter
    _batchLoad(targetIdx - 10, targetIdx + 30);
    // Trigger rebuild to start loading
    setState(() => _currentPage = targetPage);

    // Delay scroll slightly to let images begin loading
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_scrollController.hasClients) return;
      final estPos = targetIdx * MediaQuery.of(context).size.height * 0.78;
      _scrollController.animateTo(
        estPos.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4E6EF2)),
                    ),
                    SizedBox(height: 12),
                    Text('加载中...', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('❌ $_error', style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 15)),
                    ),
                  )
                : Stack(
                    children: [
                      GestureDetector(
                        onTap: _toggleTopBar,
                        child: _buildReaderContent(),
                      ),
                      if (_topBarVisible) _buildTopBar(),
                      _buildScrollbar(),
      if (_isDragging)
        Positioned.fill(
          child: Container(color: Colors.transparent),
        ),
                      if (_chapters.length > 1)
                        Positioned(
                          right: 16,
                          bottom: MediaQuery.of(context).padding.bottom + 80,
                          child: GestureDetector(
                            onTap: _showChapterMenu,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.list, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildReaderContent() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: 36,
        bottom: MediaQuery.of(context).padding.bottom + 80,
      ),
      itemCount: _computeItemCount(),
      itemBuilder: (context, index) => _buildItem(index),
    );
  }

  int _computeItemCount() {
    int count = 0;
    for (int ci = 0; ci < _chapters.length; ci++) {
      if (_chapters[ci].name.isNotEmpty) count++;
      count += _chapters[ci].imageNames.length; // images only, no separators
      if (ci < _chapters.length - 1 && _chapters[ci].name.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  int _globalPageIndex = 0;
  int _currentItemIdx = 0;

  Widget _buildItem(int itemIdx) {
    _currentItemIdx = 0;
    _globalPageIndex = 0;

    for (int ci = 0; ci < _chapters.length; ci++) {
      if (_chapters[ci].name.isNotEmpty) {
        if (_currentItemIdx == itemIdx) {
          return _buildChapterSeparator(ci, _chapters[ci].name);
        }
        _currentItemIdx++;
      }
      for (int pi = 0; pi < _chapters[ci].imageNames.length; pi++) {
        _globalPageIndex++;
        if (_currentItemIdx == itemIdx) {
          return _buildPageImage(_globalPageIndex - 1, _chapters[ci].imageNames[pi]);
        }
        _currentItemIdx++;
      }
      if (ci < _chapters.length - 1 && _chapters[ci].name.isNotEmpty) {
        if (_currentItemIdx == itemIdx) {
          return _buildNextChapterLink(ci + 1, _chapters[ci + 1].name);
        }
        _currentItemIdx++;
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildChapterSeparator(int index, String name) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.folder, size: 16, color: Color(0xFF4E6EF2)),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4E6EF2),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPageImage(int pageIndex, String imageName) {
    final data = _pageData[pageIndex];
    final isZoomed = _zoomedPages.contains(pageIndex);

    if (data == null) {
      final screenW = MediaQuery.of(context).size.width;
      final ratio = _pageAspectRatios[pageIndex] ?? 1.4;
      return Container(
        width: double.infinity,
        height: screenW / ratio,
        color: const Color(0xFF222222),
        child: const Center(
          child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF555555)),
          ),
        ),
      );
    }

    // Target decode size for memory efficiency (~2x screen width is plenty)
    final screenWidth = MediaQuery.of(context).size.width;
    final cacheW = (screenWidth * 2).round();

    if (isZoomed) {
      return GestureDetector(
        onDoubleTap: () => _toggleZoom(pageIndex),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.85,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.memory(data, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return GestureDetector(
      onDoubleTap: () => _toggleZoom(pageIndex),
      child: Image.memory(
        data,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        cacheWidth: cacheW,
        errorBuilder: (_, __, ___) => _imageError(),
      ),
    );
  }

  Widget _imageError() {
    return Container(
      height: 300,
      color: const Color(0xFF222222),
      child: const Center(
        child: Text('图片加载失败', style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
      ),
    );
  }

  Widget _buildNextChapterLink(int chapterIdx, String chapterName) {
    return GestureDetector(
      onTap: () => _scrollToChapter(chapterIdx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF4E6EF2)),
              const SizedBox(width: 4),
              Text('↓ $chapterName', style: const TextStyle(color: Color(0xFF4E6EF2), fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _topBarVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: MediaQuery.of(context).padding.top + 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 12, bottom: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _chapters.length > 1 ? _showChapterMenu : null,
                      child: Text(
                        _chapters.length > 1 && _getCurrentChapterName().isNotEmpty
                            ? _getCurrentChapterName()
                            : _comic?.name ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Text(
                    '$_currentPage/$_totalPages',
                    style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getCurrentChapterName() {
    int cumPages = 0;
    for (int i = 0; i < _chapters.length; i++) {
      cumPages += _chapters[i].imageNames.length;
      if (_currentPage <= cumPages) {
        return _chapters[i].name;
      }
    }
    return '';
  }

  Widget _buildScrollbar() {
    final screenH = MediaQuery.of(context).size.height;
    final trackTop = 60.0;
    final trackBottom = screenH - 60;
    final trackHeight = trackBottom - trackTop;
    final double thumbTop = _scrollbarPosition;

    return Positioned(
      right: 0,
      top: trackTop,
      bottom: screenH - trackBottom,
      child: GestureDetector(
        onTapDown: (details) => _onScrollbarDrag(details.localPosition.dy, trackHeight),
        onVerticalDragStart: (details) => _onScrollbarDragStart(details.localPosition.dy, trackHeight),
        onVerticalDragUpdate: (details) => _onScrollbarDrag(details.localPosition.dy, trackHeight),
        onVerticalDragEnd: (_) => _onScrollbarDragEnd(),
        child: SizedBox(
          width: 32,
          height: trackHeight,
          child: Stack(
            children: [
              // Track
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Thumb
              Positioned(
                right: 11,
                top: thumbTop,
                child: Container(
                  width: 6,
                  height: _scrollbarHeight,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? const Color(0xFF4E6EF2)
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Page preview overlay
              if (_isDragging)
                Positioned(
                  right: 24,
                  top: (thumbTop + _scrollbarHeight / 2 - 16).clamp(0.0, trackHeight - 32),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4E6EF2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_dragPreviewPage/$_totalPages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onScrollbarDragStart(double localY, double trackHeight) {
    setState(() => _isDragging = true);
    _scrollToRatio(localY / trackHeight, trackHeight);
  }

  void _onScrollbarDrag(double localY, double trackHeight) {
    final ratio = (localY / trackHeight).clamp(0.0, 1.0);
    final targetPage = (ratio * (_totalPages - 1)).round() + 1;
    setState(() => _dragPreviewPage = targetPage.clamp(1, _totalPages));
    _scrollToRatio(ratio, trackHeight);
  }

  void _onScrollbarDragEnd() {
    setState(() => _isDragging = false);
  }

  void _scrollToRatio(double ratio, double trackHeight) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetY = ratio * maxScroll;
    _scrollController.jumpTo(targetY.clamp(0, maxScroll));

    // Update thumb position immediately
    final viewH = _scrollController.position.viewportDimension;
    final thumbH = (trackHeight * (viewH / (maxScroll + viewH))).clamp(30.0, trackHeight);
    setState(() {
      _scrollbarPosition = (trackHeight - thumbH) * ratio;
      _scrollbarHeight = thumbH;
    });
  }

  void _showChapterMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        int cumPages = 0;
        int currentChap = 0;
        for (int i = 0; i < _chapters.length; i++) {
          cumPages += _chapters[i].imageNames.length;
          if (_currentPage <= cumPages) {
            currentChap = i;
            break;
          }
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('📋 目录', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const Divider(color: Color(0xFF333333), height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _chapters.length,
                  itemBuilder: (_, i) {
                    final chap = _chapters[i];
                    final isCurrent = i == currentChap;
                    return ListTile(
                      title: Text(
                        chap.name.isNotEmpty ? chap.name : '(单本)',
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF4E6EF2) : const Color(0xFFCCCCCC),
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      trailing: Text(
                        '${chap.imageNames.length}页',
                        style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _scrollToChapter(i);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
