import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _languageSet = false;
  String? _initError;

  /// 初始化
  Future<String?> init() async {
    if (_initialized) return _initError;

    try {
      // 让 speak 在播报完成后才返回
      await _tts.awaitSpeakCompletion(true);
      await _tts.awaitSynthCompletion(true);

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);

      // 先查询引擎支持的语言列表，确认中文是否可用
      // 部分引擎（"使用系统语言"模式）不支持显式 setLanguage，强行设置反而静音
      bool zhFound = false;
      try {
        final langs = await _tts.getLanguages;
        if (langs is List) {
          for (final l in langs) {
            final s = l.toString().toLowerCase();
            if (s.startsWith('zh') || s.contains('chinese')) {
              zhFound = true;
              break;
            }
          }
        }
      } catch (_) {
        // 查询失败则不强制设置
      }

      if (zhFound) {
        // 列表中有中文，尝试精确设置
        dynamic r = await _tts.setLanguage('zh-CN');
        if (r == -1 || r == -2 || r == false) {
          r = await _tts.setLanguage('zh');
        }
        if (r != -1 && r != -2 && r != false) {
          _languageSet = true;
        }
      }
      // 没找到中文或设置失败：不设置语言，跟随系统（系统为中文时能正常朗读）

      _tts.setErrorHandler((msg) {
        // 运行时错误，不阻断
      });

      _initialized = true;
      _initError = null;
    } catch (e) {
      _initError = 'TTS 初始化失败：$e';
      _initialized = true;
    }
    return _initError;
  }

  /// 播放一段测试语音
  Future<void> playTest() async {
    await init();
    await _tts.speak('你好，这是语音测试').timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }

  /// 播报词语，可指定朗读次数
  Future<void> speak(String text, {int repeat = 1}) async {
    await init();

    for (int i = 0; i < repeat; i++) {
      try {
        await _tts.speak(text).timeout(
          const Duration(seconds: 15),
          onTimeout: () => null,
        );
      } catch (_) {
        // 忽略单次错误
      }
      if (i < repeat - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  /// 停止播报
  Future<void> stop() async {
    await _tts.stop();
  }

  /// 暂停播报
  Future<void> pause() async {
    await _tts.pause();
  }

  /// 设置语速
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  /// 释放资源
  Future<void> dispose() async {
    await _tts.stop();
  }
}
