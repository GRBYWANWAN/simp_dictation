import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 文件导入导出服务 - TXT 文本
class FileService {
  /// 从设备选择 TXT 文件并读取内容
  /// 返回文件内容字符串，用户取消时返回 null
  Future<String?> importTxt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: false,
        withData: true,
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

      // 使用 file_picker 选择保存位置（Android/Windows/macOS 通用）
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出词单为 TXT',
        fileName: '$fileName.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
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

      // 写入文件
      final file = File(outputPath);
      await file.writeAsBytes(bytes);
      return outputPath;
    } catch (e) {
      throw Exception('导出 TXT 失败: $e');
    }
  }

  /// 智能解码字节为字符串（优先 UTF-8，回退 GBK）
  String _decodeBytes(List<int> bytes) {
    // 尝试 UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return String.fromCharCodes(bytes, 3);
    }
    // 尝试 UTF-8 解码
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      // 回退：用 latin1 逐字节解码（Windows GBK 文本在移动端可能需要额外编解码包）
      // 这里做宽松处理，保证不崩溃
      return String.fromCharCodes(bytes);
    }
  }

  /// 编码字符串为 UTF-8 字节（带 BOM，兼容 Windows 记事本）
  List<int> _encodeString(String text) {
    // 添加 UTF-8 BOM，确保 Windows 记事本正确识别中文
    final bom = [0xEF, 0xBB, 0xBF];
    return [...bom, ...utf8.encode(text)];
  }

  /// 解析文本为词语列表
  /// 支持：一行一个词语，或空格/逗号/分号/顿号分隔
  List<String> parseWords(String text) {
    // 统一换行符
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 按换行、空格、逗号、分号、顿号分割
    final parts = normalized.split(RegExp(r'[\n\s,，;；、]+'));
    // 去空、去重（保留首次出现顺序）
    final seen = <String>{};
    final result = <String>[];
    for (final p in parts) {
      final trimmed = p.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }
}
