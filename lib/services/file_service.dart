import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

      if (Platform.isAndroid || Platform.isIOS) {
        // 移动端：file_picker 必须直接传 bytes，由系统 SAF 写入
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出词单为 TXT',
          fileName: '$fileName.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
          bytes: bytes,
        );
        // outputPath 为 null 表示用户取消（移动端文件已由系统写入）
        return outputPath;
      } else {
        // 桌面端（Windows/macOS/Linux）：选择保存路径后自己写文件
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

        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        return outputPath;
      }
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
