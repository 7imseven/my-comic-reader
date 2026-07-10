import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';

/// 从 ZIP 中央目录读取的单个条目元数据。
class ZipEntryMeta {
  final String fileName;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
  int dataOffset; // 压缩数据在文件中的起始偏移（从 Local File Header 计算得出）

  ZipEntryMeta({
    required this.fileName,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.dataOffset,
  });
}

/// ZIP 中央目录解析器。
/// 只读取 EOCD + Central Directory（文件最后几 KB），不加载任何压缩数据。
class ZipCentralDirectoryReader {
  static Future<List<ZipEntryMeta>> read(String zipPath) async {
    final file = await File(zipPath).open();
    try {
      final length = await file.length();

      // ── 1. 查找 End of Central Directory Record ──
      // EOCD 签名 0x06054b50，位于文件末尾的 65557 字节内
      // ZIP 规范：最大 comment 长度 65535 + 固定 22 字节 = 65557
      const maxEocdSize = 65557;
      final eocdSearchSize = (length < maxEocdSize) ? length : maxEocdSize;
      await file.setPosition(length - eocdSearchSize);
      final tail = await file.read(eocdSearchSize);

      int eocdOffset = -1;
      for (int i = tail.length - 22; i >= 0; i--) {
        if (tail[i] == 0x50 && tail[i + 1] == 0x4b &&
            tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
          eocdOffset = (length - eocdSearchSize) + i;
          break;
        }
      }
      if (eocdOffset < 0) {
        throw FormatException('Cannot find End of Central Directory Record');
      }

      // ── 2. 从 EOCD 中读取 Central Directory 偏移和大小 ──
      // EOCD layout:
      //   0: signature (4)
      //   4: disk number (2)
      //   6: disk with central dir (2)
      //   8: entries on this disk (2)
      //  10: total entries (2)
      //  12: central directory size (4)
      //  16: central directory offset (4)
      //  20: comment length (2)
      //  22: comment (n)
      final eocdLocalOffset = eocdOffset - (length - eocdSearchSize);
      final cdOffset = ByteData.view(tail.buffer, eocdLocalOffset + 16, 4).getUint32(0, Endian.little);
      final cdSize = ByteData.view(tail.buffer, eocdLocalOffset + 12, 4).getUint32(0, Endian.little);

      // ── 3. 读取 Central Directory ──
      await file.setPosition(cdOffset);
      final cdBytes = await file.read(cdSize);
      final cdView = ByteData.view(cdBytes.buffer);

      // ── 4. 解析每个条目 ──
      final entries = <ZipEntryMeta>[];
      final localOffsets = <int>[];
      int pos = 0;
      while (pos + 46 <= cdBytes.length) {
        // Central Directory entry signature
        final sig = cdView.getUint32(pos, Endian.little);
        if (sig != 0x02014b50) break;

        final nameLen = cdView.getUint16(pos + 28, Endian.little);
        final extraLen = cdView.getUint16(pos + 30, Endian.little);
        final commentLen = cdView.getUint16(pos + 32, Endian.little);
        final localHeaderOffset = cdView.getUint32(pos + 42, Endian.little);
        final compressedSize = cdView.getUint32(pos + 20, Endian.little);
        final uncompressedSize = cdView.getUint32(pos + 24, Endian.little);
        final crc32 = cdView.getUint32(pos + 16, Endian.little);

        final rawName = cdBytes.sublist(pos + 46, pos + 46 + nameLen);
        final fileName = await fixGarbledName(rawName);

        entries.add(ZipEntryMeta(
          fileName: fileName,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          crc32: crc32,
          dataOffset: 0, // 稍后计算
        ));
        localOffsets.add(localHeaderOffset);

        pos += 46 + nameLen + extraLen + commentLen;
      }

      // ── 5. 读取 Local File Header 计算每个条目的 dataOffset ──
      // Local file header: signature(4) + version(2) + flags(2) + method(2)
      //   + time(2) + date(2) + crc32(4) + compSize(4) + uncompSize(4)
      //   + nameLen(2) + extraLen(2) = 30 bytes fixed
      // dataOffset = localHeaderOffset + 30 + nameLen + extraLen
      for (int i = 0; i < entries.length; i++) {
        await file.setPosition(localOffsets[i]);
        final localHeader = await file.read(30);
        final lhView = ByteData.view(localHeader.buffer);
        final lhNameLen = lhView.getUint16(26, Endian.little);
        final lhExtraLen = lhView.getUint16(28, Endian.little);
        entries[i].dataOffset = localOffsets[i] + 30 + lhNameLen + lhExtraLen;
      }

      return entries;
    } finally {
      await file.close();
    }
  }

  static Future<String> fixGarbledName(Uint8List rawBytes) async {
    // Try UTF-8 first (modern ZIPs use bit 11 flag for UTF-8)
    String decoded;
    try {
      decoded = utf8.decode(rawBytes);
    } on FormatException {
      // Not valid UTF-8, use Latin-1 as raw string
      decoded = String.fromCharCodes(rawBytes);
    }

    // Check if the result looks garbled (high bytes but no CJK)
    if (_looksLikeGarbled(decoded)) {
      try {
        return await CharsetConverter.decode('GBK', rawBytes);
      } catch (_) {
        try {
          return await CharsetConverter.decode('GB2312', rawBytes);
        } catch (_) {}
      }
    }
    return decoded;
  }

  /// Heuristic: name has high bytes but no CJK → likely garbled
  static bool _looksLikeGarbled(String name) {
    bool hasHigh = false;
    for (final c in name.runes) {
      if (c > 0x7F && c < 0x400) hasHigh = true;
      if (c >= 0x4E00 && c <= 0x9FFF) return false;
    }
    return hasHigh;
  }
}

/// ZIP 单页读取器。
/// 根据偏移量从 ZIP 中随机读取并解压单个条目的数据。
/// 使用 archive 包的 Inflate 解码 raw deflate 流。
class ZipPageReader {
  RandomAccessFile? _file;
  bool _isOpen = false;

  // Sequential task queue: serializes RandomAccessFile access
  // to prevent concurrent seek+read race conditions.
  Future<void>? _previousTask;

  Future<void> open(String zipPath) async {
    _file = await File(zipPath).open();
    _isOpen = true;
  }

  /// 读取指定偏移量的条目，解压后返回图片数据。
  /// 通过任务队列保证 RandomAccessFile 的顺序访问。
  Future<Uint8List> readEntry(int dataOffset, int compressedSize, int uncompressedSize) async {
    // Chain: wait for previous read to finish before starting this one
    final previous = _previousTask;
    final completer = Completer<void>();
    _previousTask = completer.future;
    if (previous != null) await previous;

    try {
      final file = _file;
      if (file == null) throw StateError('ZipPageReader not opened');
      await file.setPosition(dataOffset);
      final compressed = await file.read(compressedSize);
      return Inflate(compressed, uncompressedSize).getBytes() as Uint8List;
    } finally {
      completer.complete();
    }
  }

  void close() {
    _file?.closeSync();
    _isOpen = false;
    _file = null;
  }

  bool get isOpen => _isOpen;
}
