import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/video_storage_service.dart';
import 'video_list_page.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});
  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  final VideoStorageService _storage = VideoStorageService();
  List<String> _tags = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _tags = _storage.allTags;
      _counts = _storage.tagCounts;
      _tags.sort((a, b) => _counts[b]!.compareTo(_counts[a]!));
    });
  }

  Future<void> _importVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    // Show tag selection dialog
    final selectedTags = await _showTagPicker();
    if (selectedTags == null || selectedTags.isEmpty) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在导入视频...'), duration: Duration(seconds: 1)),
    );

    try {
      await _storage.importVideo(File(path), selectedTags);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 导入成功'), duration: Duration(seconds: 2)),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 导入失败: $e')),
      );
    }
  }

  Future<List<String>?> _showTagPicker() async {
    final selected = <String>{};
    final controller = TextEditingController();
    final tags = List<String>.of(_storage.allTags);

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择标签'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: '新建标签...',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty && !tags.contains(v.trim())) {
                            setDialogState(() => tags.add(v.trim()));
                            controller.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        final v = controller.text.trim();
                        if (v.isNotEmpty && !tags.contains(v)) {
                          setDialogState(() {
                            tags.add(v);
                            selected.add(v);
                          });
                          controller.clear();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (tags.isEmpty)
                  const Text('还没有标签，输入名称创建')
                else
                  Flexible(
                    child: Wrap(
                      spacing: 8, runSpacing: 4,
                      children: tags.map((tag) => FilterChip(
                        label: Text(tag),
                        selected: selected.contains(tag),
                        onSelected: (v) {
                          setDialogState(() {
                            if (v) { selected.add(tag); } else { selected.remove(tag); }
                          });
                        },
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: selected.isNotEmpty ? () => Navigator.pop(ctx, selected.toList()) : null,
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTag(String tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除标签「$tag」？该标签下的视频不会删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _storage.removeTag(tag);
      _reload();
    }
  }

  void _openTag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoListPage(tag: tag)),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('🎬 隐私视频'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: _tags.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('🎥', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text('还没有分类', style: TextStyle(color: Color(0xFF999999), fontSize: 15)),
              SizedBox(height: 4),
              Text('导入第一个视频创建分类', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: _tags.length,
              itemBuilder: (_, index) {
                final tag = _tags[index];
                final count = _counts[tag] ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openTag(tag),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4E6EF2).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.folder_outlined, color: Color(0xFF4E6EF2), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tag, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                          const SizedBox(height: 2),
                          Text('$count 个视频', style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                        ])),
                        if (tag != '默认')
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCCCCCC)),
                            onPressed: () => _deleteTag(tag),
                          ),
                        const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC)),
                      ]),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importVideo,
        backgroundColor: const Color(0xFF4E6EF2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('导入视频'),
      ),
    );
  }
}
