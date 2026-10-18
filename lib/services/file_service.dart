import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 文件导入导出服务 - TXT 文本
class FileService {
  // GBK 解码器（容忍个别非法字节，不抛异常）
  static final GbkCodec _gbk = GbkCodec(allowMalformed: true);
  /// 从设备选择 TXT 文件并读取内容
  /// 返回文件内容字符串，用户取消时返回 null
  Future<String?> importTxt() async {
    try {
      // 尽量让文件选择器初始定位到系统 Download 目录
      String? initialDir;
      try {
        final d = await getDownloadsDirectory();
        initialDir = d?.path;
      } catch (_) {}
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: false,
        withData: true,
        initialDirectory: initialDir,
      );
      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      // 优先用 bytes 读取，兼容各平台
      if (file.bytes != null) {
        return _decodeBytes(file.bytes!);
      } else if (file.path != null) {
        final content = await File(file.path!).readAsBytes();
        return _decodeBytes(content);
      }
      return null;
    } catch (e) {
      throw Exception('导入 TXT 失败: $e');
    }
  }

  /// 将词语列表导出为 TXT 文件
  /// [words] 词语列表，每行一个
  /// [fileName] 文件名（不含扩展名）
  /// 返回保存的文件路径，用户取消时返回 null
  Future<String?> exportTxt(List<String> words, {String fileName = '词单导出'}) async {
    try {
      final content = words.join('\n');
      final bytes = _encodeString(content);

      if (Platform.isAndroid) {
        // 优先直接写入系统 Download 目录：导出后用户在 Download 文件夹即可直接找到，
        // 不必再翻目录。若因 Android 分区存储限制写入失败，再回退到系统保存对话框。
        try {
          final dir = await getDownloadsDirectory();
          if (dir != null) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            final path = '${dir.path}/${fileName}_$ts.txt';
            await File(path).writeAsBytes(bytes);
            return path;
          }
        } catch (_) {
          // 直接写 Download 被系统拒绝，回退到 SAF 选择器
        }
        // 回退：由系统 SAF 写入（提示用户选 Download）
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出词单为 TXT（请选 Download 文件夹）',
          fileName: '$fileName.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
          bytes: bytes,
        );
        return outputPath;
      } else {
        // 桌面端（Windows/macOS/Linux）：选择保存路径后自己写文件
        String? downloadsDir;
        try {
          downloadsDir = (await getDownloadsDirectory())?.path;
        } catch (_) {}
        String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出词单为 TXT',
          fileName: '$fileName.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
          initialDirectory: downloadsDir,
        );

        if (outputPath == null) {
          // 用户取消，回退保存到应用文档目录
          final dir = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          outputPath = '${dir.path}/${fileName}_$timestamp.txt';
        }

        // 确保扩展名
        if (!outputPath.toLowerCase().endsWith('.txt')) {
          outputPath = '$outputPath.txt';
        }

        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        return outputPath;
      }
    } catch (e) {
      throw Exception('导出 TXT 失败: $e');
    }
  }

  /// 智能解码字节为字符串
  /// 自动识别常见中文 TXT 编码：UTF-8(含BOM)、UTF-16(记事本"Unicode")、GBK(记事本"ANSI")
  String _decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';

    // 1. UTF-8 BOM（EF BB BF）
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }

    // 2. UTF-16 LE BOM（FF FE）—— 记事本"Unicode"
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, 2, littleEndian: true);
    }

    // 3. UTF-16 BE BOM（FE FF）
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, 2, littleEndian: false);
    }

    // 4. 无 BOM：先尝试严格 UTF-8（无任何非法字节即判定为 UTF-8）
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      // 存在非法字节，需要区分：是"UTF-8 但有个别坏字节"，还是"GBK 文件"
      // 实测：真 GBK 按 UTF-8 解析，替换符占比约 60%+；UTF-8 仅个别坏字节时占比 < 10%
      final asUtf8 = utf8.decode(bytes, allowMalformed: true);
      final replacementCount = '�'.allMatches(asUtf8).length;
      final ratio = asUtf8.isEmpty ? 1.0 : replacementCount / asUtf8.length;
      // 替换符占比低于 25%：基本是 UTF-8，仅个别字节损坏，保留 UTF-8
      if (ratio < 0.25) {
        return asUtf8;
      }
      // 替换符密集：GBK 中文字节天然违反 UTF-8 结构，改用 GBK 解码
      try {
        return _gbk.decode(bytes);
      } catch (_) {
        return asUtf8;
      }
    }
  }

  /// 解码 UTF-16（BMP 内中英文均可，含代理对时用 fromCharCodes 兜底）
  String _decodeUtf16(List<int> bytes, int offset,
      {required bool littleEndian}) {
    final units = <int>[];
    var i = offset;
    while (i + 1 < bytes.length) {
      final b0 = bytes[i];
      final b1 = bytes[i + 1];
      final unit = littleEndian ? (b1 << 8 | b0) : (b0 << 8 | b1);
      units.add(unit);
      i += 2;
    }
    return String.fromCharCodes(units);
  }

  /// 编码字符串为 UTF-8 字节（带 BOM，兼容 Windows 记事本）
  Uint8List _encodeString(String text) {
    // 添加 UTF-8 BOM，确保 Windows 记事本正确识别中文
    final bom = [0xEF, 0xBB, 0xBF];
    return Uint8List.fromList([...bom, ...utf8.encode(text)]);
  }

  /// 解析文本为词语列表
  /// 以"行"为单位，一行一个词（支持英语单词、英语句子、带空格的内容）
  /// 仅按换行分割，不再按空格/逗号等切分，保证整句完整
  List<String> parseWords(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    // 去空、去重（保留首次出现顺序）
    final seen = <String>{};
    final result = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }
}
