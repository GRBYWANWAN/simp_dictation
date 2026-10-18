import 'package:flutter/services.dart';

/// 屏幕关闭/锁屏后，持有 PARTIAL_WAKE_LOCK 保持 CPU 不休眠，
/// 这样 Dart 的倒计时定时器不会被系统冻结，TTS 能在黑屏后继续自动播报下一个词。
/// 实际的 native 唤醒锁由 android/app 里的 MainActivity（MethodChannel "dictation/wakelock"）实现。
class WakeLockService {
  static const MethodChannel _channel = MethodChannel('dictation/wakelock');

  /// 开始持有唤醒锁（开始听写时调用）
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enable');
    } catch (_) {}
  }

  /// 释放唤醒锁（停止/完成听写时调用）
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disable');
    } catch (_) {}
  }
}
