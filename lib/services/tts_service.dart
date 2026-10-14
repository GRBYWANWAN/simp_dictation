import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音播报服务
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Completer<void>? _speakCompleter;

  /// 初始化 TTS 引擎，设置中文语音
  Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });
    _tts.setErrorHandler((msg) {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.completeError(msg.toString());
      }
    });

    _initialized = true;
  }

  /// 播报词语，可指定朗读次数
  /// 所有次数播报完成后 Future 才完成
  Future<void> speak(String text, {int repeat = 1}) async {
    await init();
    for (int i = 0; i < repeat; i++) {
      _speakCompleter = Completer<void>();
      await _tts.speak(text);
      try {
        await _speakCompleter!.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            // 超时兜底，避免卡死
          },
        );
      } catch (_) {
        // 忽略单次错误，继续下一次
      }
      // 两次朗读之间短暂停顿
      if (i < repeat - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  /// 停止播报
  Future<void> stop() async {
    await _tts.stop();
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
  }

  /// 暂停播报
  Future<void> pause() async {
    await _tts.pause();
  }

  /// 设置语速 (0.0 ~ 1.0)
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  /// 设置语言
  Future<void> setLanguage(String lang) async {
    await _tts.setLanguage(lang);
  }

  /// 释放资源
  Future<void> dispose() async {
    await _tts.stop();
  }
}
