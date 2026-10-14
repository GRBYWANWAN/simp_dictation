import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _engineName;
  String? _languageCode;

  /// 初始化 TTS 引擎
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 1. 优先指定 Google TTS 引擎，没有则回退到系统默认
      try {
        final engines = await _tts.getEngines;
        if (engines is List && engines.contains('com.google.android.tts')) {
          await _tts.setEngine('com.google.android.tts');
          _engineName = 'com.google.android.tts';
        } else if (engines is List && engines.isNotEmpty) {
          _engineName = engines.first.toString();
        }
      } catch (_) {}

      // 2. 从实际语言列表匹配中文
      try {
        final langs = await _tts.getLanguages;
        if (langs is List) {
          final langStrs = langs.map((e) => e.toString()).toList();
          for (final code in ['zh-CN', 'zh_CN', 'cmn-Hans-CN', 'zh-TW', 'zh']) {
            if (langStrs.any((l) => l == code || l.startsWith(code))) {
              _languageCode = code;
              break;
            }
          }
          if (_languageCode == null) {
            for (final l in langStrs) {
              if (l.toLowerCase().startsWith('zh') ||
                  l.toLowerCase().contains('chinese')) {
                _languageCode = l;
                break;
              }
            }
          }
        }
      } catch (_) {}

      if (_languageCode != null) {
        try {
          await _tts.setLanguage(_languageCode!);
        } catch (_) {}
      }

      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      await _tts.awaitSynthCompletion(true);

      _tts.setErrorHandler((msg) {});

      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  /// 完整诊断：返回每一步的结果
  Future<Map<String, String>> diagnose() async {
    final result = <String, String>{};

    // 引擎信息
    try {
      final engines = await _tts.getEngines;
      result['引擎列表'] = engines is List ? engines.join(', ') : '$engines';
    } catch (e) {
      result['引擎列表'] = '失败: $e';
    }
    result['使用引擎'] = _engineName ?? '(跟随系统)';

    // 语言
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        result['语言总数'] = '${langs.length}';
        final zh = langs
            .map((e) => e.toString())
            .where((s) => s.toLowerCase().startsWith('zh'))
            .toList();
        result['可用中文'] = zh.isEmpty ? '(无)' : zh.take(6).join(', ');
      }
    } catch (e) {
      result['语言'] = '获取失败: $e';
    }
    result['匹配语言'] = _languageCode ?? '(跟随系统)';

    // 语言可用性
    try {
      final avail = await _tts.isLanguageAvailable('zh-CN');
      result['zh-CN可用性'] = '$avail';
    } catch (e) {
      result['zh-CN可用性'] = '检测失败: $e';
    }

    // 完整初始化后 speak 返回值
    await init();
    try {
      final r = await _tts.speak('测试').timeout(
        const Duration(seconds: 6),
        onTimeout: () => 'TIMEOUT',
      );
      result['speak返回值'] = '$r (1=成功,0=失败,timeout=回调丢失)';
    } catch (e) {
      result['speak返回值'] = '异常: $e';
    }

    return result;
  }

  /// 测试语音
  Future<void> playTestRaw(String text) async {
    await init();
    await speak(text, repeat: 1, timeout: 8);
  }

  Future<void> playTest() async {
    await playTestRaw('你好，这是语音测试');
  }

  /// 朗读文字
  Future<void> speak(String text, {int repeat = 1, int timeout = 8}) async {
    if (text.isEmpty) return;
    await init();

    for (int i = 0; i < repeat; i++) {
      try {
        await _tts.stop();
        await _tts.speak(text).timeout(
          Duration(seconds: timeout),
          onTimeout: () {
            _tts.stop();
          },
        );
      } catch (_) {}
      if (i < repeat - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {}
  }

  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
