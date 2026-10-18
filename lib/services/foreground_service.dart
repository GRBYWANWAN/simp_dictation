import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台服务入口回调（必须是顶层函数或静态方法）
@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(KeepAliveTaskHandler());
}

/// 保活任务处理器：本身不做任何重复工作（eventAction = nothing），
/// 仅借助前台服务 + PARTIAL_WAKE_LOCK 让 App 在锁屏/黑屏时保持进程与 CPU 活跃，
/// 从而使听写页面（主 isolate）的倒计时定时器与 TTS 继续自动播报。
class KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  // 点击通知回到 App 依赖悬浮窗(SYSTEM_ALERT_WINDOW)特殊权限，
  // 为避免额外授权这里不处理；用户点桌面图标/最近任务即可回到听写页，
  // 不影响核心的锁屏继续播报。
  @override
  void onNotificationPressed() {}
}

/// 前台服务的统一封装：初始化、请求权限、启动、停止
class ForegroundService {
  static const int _serviceId = 256;

  /// 应用启动时调用一次，配置通知渠道与唤醒锁
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dictation_service',
        channelName: '听写后台服务',
        channelDescription: '锁屏或黑屏时继续听写播报',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 不需要后台 isolate 重复执行任务，只用前台服务保活，最省电
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// 请求通知权限（Android 13+ 前台服务需要显示常驻通知）
  static Future<void> requestPermission() async {
    try {
      final perm =
          await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}
  }

  /// 听写开始时启动前台服务（应在 App 处于前台、用户点击开始时调用）
  static Future<void> start(String title, String text) async {
    try {
      await requestPermission();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: _serviceId,
          notificationTitle: title,
          notificationText: text,
          callback: startForegroundTaskCallback,
        );
      }
    } catch (_) {}
  }

  /// 更新通知文字（用于显示进度）
  static Future<void> update(String title, String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
          callback: startForegroundTaskCallback,
        );
      }
    } catch (_) {}
  }

  /// 听写停止/完成时关闭前台服务
  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}
