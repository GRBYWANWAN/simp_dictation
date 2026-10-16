import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  // 提示音专用播放器（播放打包好的真实"嘀"音，保证一定发声）
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _initialized = false;
  String? _engineName;
  String? _languageCode;

  // 语速倍率（Android: 1.0=正常，0.75=慢，1.25=快）
  double _rate = 1.0;
  // 是否在每个词语前播放提示音
  bool _beepEnabled = true;

  /// 设置语速倍率（0.75 / 1.0 / 1.25）
  Future<void> setSpeed(double rate) async {
    _rate = rate;
    if (_initialized) {
      try {
        await _tts.setSpeechRate(rate);
      } catch (_) {}
    }
  }

  /// 设置是否开启提示音
  void setBeepEnabled(bool enabled) {
    _beepEnabled = enabled;
  }

  /// 播放提示音（Windows Ding.wav "叮咚"提示音，由听写页在每个词前调用）
  /// 不依赖 TTS 引擎，确保一定能发声
  Future<void> playBeep() async {
    try {
      // 从头播放打包好的提示音
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource('sounds/ding.wav'));
    } catch (_) {}
    // 等待提示音播完（音频约 0.4 秒）
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// 初始化 TTS 引擎（已优化：秒级响应，完全跟随手机系统当前选择的引擎）
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 1. 直接使用系统当前默认的 TTS 引擎（不主动显式抢占 setEngine），
      // 这样能完美跟随系统设置中切换的引擎（如 Google 或无障碍引擎），并省去几十秒的等待和延迟。
      _engineName = '手机系统默认引擎';

      // 2. 快速获取系统当前引擎支持的语言（单次获取，不轮询等待）
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

      // 如果未匹配到具体代码，兜底使用标准 zh-CN
      _languageCode ??= 'zh-CN';

      try {
        await _tts.setLanguage(_languageCode!);
      } catch (_) {}

      // 3. 一次性设置基础参数
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
  /// [repeat] 朗读遍数
  /// [repeatIntervalSeconds] 朗读两遍时，第一遍与第二遍之间的间隔（秒）
  Future<void> speak(String text, {
    int repeat = 1,
    int timeout = 8,
    int repeatIntervalSeconds = 1,
  }) async {
    if (text.isEmpty) return;
    await init();
    // 每次播报前确保使用当前语速
    try {
      await _tts.setSpeechRate(_rate);
    } catch (_) {}

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
        await Future.delayed(Duration(seconds: repeatIntervalSeconds));
      }
    }
  }

  /// 切换系统引擎后重置初始化状态（可在设置更改或页面返回时调用）
  void reset() {
    _initialized = false;
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _beepPlayer.stop();
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
    try {
      await _beepPlayer.dispose();
    } catch (_) {}
  }
}