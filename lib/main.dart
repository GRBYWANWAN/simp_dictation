import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/storage_service.dart';
import 'services/file_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化前台服务与主界面的通信端口（锁屏继续播报用）
  FlutterForegroundTask.initCommunicationPort();
  runApp(const DictationApp());
}

class DictationApp extends StatefulWidget {
  const DictationApp({super.key});

  @override
  State<DictationApp> createState() => _DictationAppState();
}

class _DictationAppState extends State<DictationApp> {
  final StorageService _storage = StorageService();
  final FileService _fileService = FileService();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // 最多等待 8 秒；即使本地存储初始化异常或 platform channel 卡顿，
      // 也不能让用户永远停在"正在初始化"。
      await _storage.init().timeout(const Duration(seconds: 8));
    } catch (e) {
      // 存储初始化失败也继续进入主页（读取时各接口均有容错）
      debugPrint('storage init failed: $e');
    } finally {
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '简易听写',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 1,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: _ready
          ? HomeScreen(storage: _storage, fileService: _fileService)
          : const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在初始化...'),
                  ],
                ),
              ),
            ),
    );
  }
}
