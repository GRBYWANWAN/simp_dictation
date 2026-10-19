import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _initialized = false;
  String? _engineName;
  String? _languageCode;

  double _rate = 1.0;
  bool _beepEnabled = true;
  int _speakToken = 0;

  Future<void> setSpeed(double rate) async {
    _rate = rate;
    if (_initialized) {
      try {
        await _tts.setSpeechRate(rate);
      } catch (_) {}
    }
  }

  void setBeepEnabled(bool enabled) {
    _beepEnabled = enabled;
  }

  Future<void> playBeep() async {
    try {
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource('sounds/ding.wav'));
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));
  }

  Future<void> init() async {
    if (_initialized) return;

    try {
      _engineName = '手机系统默认引擎';
      try {
        final langs = await _tts.getLanguages;
        if (langs is List && langs.isNotEmpty) {
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

      _languageCode ??= 'zh-CN';

      try {
        await _tts.setLanguage(_languageCode!);
      } catch (_) {}

      await _tts.setSpeechRate(_rate);
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

  Future<Map<String, String>> diagnose() async {
    final result = <String, String>{};
    try {
      final engines = await _tts.getEngines;
      result['引擎列表'] = engines is List ? engines.join(', ') : '$engines';
    } catch (e) {
      result['引擎列表'] = '失败: $e';
    }
    result['使用引擎'] = _engineName ?? '(跟随系统)';
    return result;
  }

  Future<void> playTestRaw(String text) async {
    await init();
    await speak(text, repeat: 1, timeout: 8);
  }

  Future<void> playTest() async {
    await playTestRaw('你好，这是语音测试');
  }

  Future<void> _engineStop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// 朗读文字：精准控制每一遍及中间间隔，遇到 token 变化立刻安全退出
  Future<void> speak(String text, {
    int repeat = 1,
    int timeout = 8,
    int repeatIntervalSeconds = 1,
  }) async {
    if (text.isEmpty) return;
    await init();
    
    // 每次开始新朗读时生成全新令牌
    final myToken = ++_speakToken;
    try {
      await _tts.setSpeechRate(_rate);
    } catch (_) {}

    for (int i = 0; i < repeat; i++) {
      if (_speakToken != myToken) return;

      try {
        await _engineStop();
        if (_speakToken != myToken) return;

        await _tts.speak(text).timeout(
          Duration(seconds: timeout),
          onTimeout: () {
            _engineStop();
          },
        );
      } catch (_) {}

      if (_speakToken != myToken) return;

      // 如果不是最后一遍，等待两遍之间的间隔
      if (i < repeat - 1) {
        // 为了让切词响应更灵敏，将大延迟拆分为多次小间隔检查 token
        int elapsed = 0;
        while (elapsed < repeatIntervalSeconds * 1000) {
          if (_speakToken != myToken) return;
          await Future.delayed(const Duration(milliseconds: 100));
          elapsed += 100;
        }
      }
    }
  }

  void reset() {
    _initialized = false;
  }

  Future<void> stop() async {
    // 改变令牌，让所有正在等待或循环的 speak 瞬间失效
    _speakToken++;
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _beepPlayer.stop();
    } catch (_) {}
  }

  Future<void> pause() async {
    _speakToken++;
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
    _speakToken++;
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _beepPlayer.dispose();
    } catch (_) {}
  }
}