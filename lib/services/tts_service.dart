import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _languageAvailable = true;
  String? _initError;

  /// 初始化为中文语音
  /// 返回错误信息，null 表示成功
  Future<String?> init() async {
    if (_initialized) return _initError;

    try {
      // 关键：让 speak 方法在播报完成后才返回
      await _tts.awaitSpeakCompletion(true);
      await _tts.awaitSynthCompletion(true);

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.45);

      // 设置中文
      // Android 返回值：0=LANG_AVAILABLE, 1=LANG_COUNTRY_AVAILABLE,
      //               2=LANG_COUNTRY_VAR_AVAILABLE, -1=缺数据, -2=不支持
      // iOS 返回：true/false
      var langResult = await _tts.setLanguage('zh-CN');
      if (_isLangFailed(langResult)) {
        langResult = await _tts.setLanguage('zh');
        if (_isLangFailed(langResult)) {
          // 部分引擎（如"系统语言"模式）不支持显式设置语言，但系统语言本身是中文，
          // 仍能正常朗读中文，因此不标记为不可用，只记录警告
          _initError = '未能显式设置中文语音（引擎可能跟随系统语言）';
        }
      }

      _tts.setErrorHandler((msg) {
        // 运行时错误，不阻断流程
      });

      _initialized = true;
      return null; // 始终允许尝试播报
    } catch (e) {
      _initError = 'TTS 初始化失败：$e';
      _initialized = true;
      // 即使初始化异常也不阻止尝试播报
      return null;
    }
  }

  /// 判断语言设置是否失败
  /// 注意：Android 上 0/1/2 都是成功，只有负数才是失败
  bool _isLangFailed(dynamic result) {
    if (result == null) return false;
    if (result is bool) return !result;
    if (result is int) return result < 0;
    return false;
  }

  /// 播报词语，可指定朗读次数
  Future<void> speak(String text, {int repeat = 1}) async {
    await init();

    for (int i = 0; i < repeat; i++) {
      try {
        // awaitSpeakCompletion(true) 后，speak 会在播报完成时才完成
        await _tts.speak(text).timeout(
          const Duration(seconds: 15),
          onTimeout: () => null,
        );
      } catch (_) {
        // 忽略单次错误
      }
      // 两次朗读之间停顿
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
