import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/comic.dart';
import '../services/storage_service.dart';
import 'reader_page.dart';

class ComicListPage extends StatefulWidget {
  const ComicListPage({super.key});
  @override
  State<ComicListPage> createState() => _ComicListPageState();
}

class _ComicListPageState extends State<ComicListPage> {
  final StorageService _storage = StorageService();
  List<Comic> _comics = [];

  @override
  void initState() { super.initState(); _reload(); }

  void _reload() {
    setState(() { _comics = _storage.allComics; _comics.sort((a, b) => b.addedAt.compareTo(a.addedAt)); });
  }

  Future<void> _importComic() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'cbz']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在导入...'), duration: Duration(seconds: 1)));
    try {
      await _storage.importComic(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 导入成功'), duration: Duration(seconds: 2)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 导入失败: $e')));
    }
  }

  Future<void> _deleteComic(Comic comic) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除漫画'),
      content: Text('确定删除「${comic.name}」？\n此操作不可恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (confirm != true) return;
    await _storage.deleteComic(comic.id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)));
  }

  Future<void> _exportBackup() async {
    try {
      final comics = _storage.allComics;
      if (comics.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有漫画可导出')));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在打包备份...'), duration: Duration(seconds: 1)));

      final date = DateTime.now().toIso8601String().substring(0, 10);
      final fileName = 'comic-backup-$date.cbackup';

      // Save to temp directory (safe for iOS async share sheet)
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      await _storage.exportBackup(filePath);

      if (!mounted) return;

      if (Platform.isIOS) {
        // iOS: share sheet → user saves to Files/iCloud (don't delete file, iOS will clean up temp)
        await Share.shareXFiles([XFile(filePath)], subject: '漫画备份', text: '漫画备份文件，共 ${comics.length} 部');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 备份已导出'), duration: Duration(seconds: 2)));
        }
      } else {
        // Android: copy to visible external storage
        String externalDir;
        try {
          final ext = await getExternalStorageDirectory();
          externalDir = ext?.path ?? tempDir.path;
        } catch (_) {
          externalDir = tempDir.path;
        }
        final backupDir = Directory('$externalDir/ComicBackups');
        if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
        await File(filePath).copy('${backupDir.path}/$fileName');
        try { await File(filePath).delete(); } catch (_) {}

        if (mounted) {
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: const Row(children: [Icon(Icons.check_circle, size: 22, color: Color(0xFF4CAF50)), SizedBox(width: 8), Text('备份成功', style: TextStyle(fontSize: 17))]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('共 ${comics.length} 部漫画已导出'),
              const SizedBox(height: 12),
              const Text('文件位置：', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 4),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
                child: const Text('连电脑 → ComicBackups 文件夹\n或在文件管理器搜索 "ComicBackups"', style: TextStyle(fontSize: 12, color: Color(0xFF666666)))),
              const SizedBox(height: 8),
              Text('将备份文件保存到电脑或云端，\n换手机或重装 App 后可以恢复。', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 导出失败: $e')));
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['cbackup']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    try {
      final count = await _storage.importBackup(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 导入 $count 部漫画'), duration: const Duration(seconds: 2)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 导入失败: $e')));
    }
  }

  void _openComic(Comic comic) { Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderPage(comicId: comic.id))); }

  void _showStorageInfo() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.info_outline, size: 20, color: Color(0xFF4E6EF2)), SizedBox(width: 8), Text('存储信息', style: TextStyle(fontSize: 17))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoRow('漫画数量', '${_comics.length} 部'),
        const Divider(height: 16), _infoRow('存储位置', 'App 内部沙盒'),
        const SizedBox(height: 4),
        Text('所有漫画文件保存在 App 的私有目录中。\n手机的文件 App 搜索不到这些文件。\n删除桌面原始的 ZIP 文件不会影响 App 内的漫画。', style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5)),
        const Divider(height: 16), _infoRow('备份建议', '定期导出备份到电脑或云端'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
    ));
  }

  Widget _infoRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF888888)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('📚 我的漫画'), backgroundColor: Colors.white, elevation: 0.5,
        actions: [
          IconButton(icon: const Icon(Icons.info_outline, size: 20), tooltip: '存储信息', onPressed: _showStorageInfo),
          IconButton(icon: const Icon(Icons.upload_file_outlined, size: 20), tooltip: '导入备份', onPressed: _importBackup),
          IconButton(icon: const Icon(Icons.download_outlined, size: 20), tooltip: '导出备份', onPressed: _exportBackup),
        ],
      ),
      body: _comics.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('📭', style: TextStyle(fontSize: 48)), SizedBox(height: 12),
              Text('还没有漫画', style: TextStyle(color: Color(0xFF999999), fontSize: 15)),
              SizedBox(height: 4), Text('点击下方按钮导入', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            ]))
          : RefreshIndicator(onRefresh: () async => _reload(),
              child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), itemCount: _comics.length,
                itemBuilder: (context, index) => _buildComicItem(_comics[index]))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importComic, backgroundColor: const Color(0xFF4E6EF2), foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20), label: const Text('导入漫画')),
    );
  }

  Widget _buildComicItem(Comic comic) {
    final coverPath = _storage.getCoverPath(comic.id);
    return Card(margin: const EdgeInsets.only(bottom: 10), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => _openComic(comic),
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 56, height: 76,
            child: coverPath != null ? Image.file(File(coverPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _coverPlaceholder()) : _coverPlaceholder())),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(comic.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${comic.formattedDate} · ${comic.progress > 0 ? '已读至第${comic.progress}页' : '未读'}', style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          ])),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCCCCCC)), onPressed: () => _deleteComic(comic)),
        ]))),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4E6EF2), Color(0xFF6C8AFF)]), borderRadius: BorderRadius.circular(6)),
      child: const Center(child: Text('📖', style: TextStyle(fontSize: 24))));
  }
}
