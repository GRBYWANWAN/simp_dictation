import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../services/wake_lock_service.dart';

/// 听写状态枚举
enum DictationStatus { idle, running, paused, finished }

/// 听写模式
enum DictationMode { auto, manual }

/// 听写页面
class DictationScreen extends StatefulWidget {
  final String wordListName;
  final List<String> words;
  final StorageService storage;

  const DictationScreen({
    super.key,
    required this.wordListName,
    required this.words,
    required this.storage,
  });

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final TtsService _tts = TtsService();
  final ScrollController _logScroll = ScrollController();
  final List<String> _logs = [];
  // 数字输入框控制器（保证异步加载设置后框内显示的是保存值）
  final TextEditingController _intervalCtrl =
      TextEditingController(text: '5');
  final TextEditingController _repeatIntervalCtrl =
      TextEditingController(text: '1');

  // 听写配置
  DictationMode _mode = DictationMode.auto;
  int _readCount = 1;
  int _intervalSeconds = 5; // 词与词之间的基础间隔（秒）
  int _repeatIntervalSeconds = 1; // 朗读2遍时，两遍之间的间隔（秒）
  bool _shuffle = true;
  double _speed = 1.0; // 语速：0.75 / 1.0 / 1.25
  bool _beepEnabled = true; // 每个词前播放提示音

  /// 自动模式下每个词播报完后的总等待秒数
  /// 读2遍时 = 基础间隔 + 两遍间隔
  int get _totalInterval =>
      _intervalSeconds + (_readCount == 2 ? _repeatIntervalSeconds : 0);

  // 运行状态
  DictationStatus _status = DictationStatus.idle;
  List<String> _shuffledWords = [];
  int _currentIndex = -1;
  Timer? _countdownTimer;
  int _countdown = 0;
  bool _isSpeaking = false;

  String get _currentWord =>
      (_currentIndex >= 0 && _currentIndex < _shuffledWords.length)
          ? _shuffledWords[_currentIndex]
          : '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tts.dispose();
    // 离开页面时确保释放唤醒锁
    WakeLockService.disable();
    _intervalCtrl.dispose();
    _repeatIntervalCtrl.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.init();
  }

  /// 加载保存的设置
  Future<void> _loadSettings() async {
    final s = await widget.storage.loadSettings();
    setState(() {
      _mode = s['mode'] == 'manual' ? DictationMode.manual : DictationMode.auto;
      _readCount = (s['readCount'] as int?) ?? 1;
      _intervalSeconds = (s['interval'] as int?) ?? 5;
      _repeatIntervalSeconds = (s['repeatInterval'] as int?) ?? 1;
      _shuffle = (s['shuffle'] as bool?) ?? true;
      _speed = (s['speed'] as num?)?.toDouble() ?? 1.0;
      _beepEnabled = (s['beep'] as bool?) ?? true;
    });
    _intervalCtrl.text = '$_intervalSeconds';
    _repeatIntervalCtrl.text = '$_repeatIntervalSeconds';
    await _tts.setSpeed(_speed);
    _tts.setBeepEnabled(_beepEnabled);
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    await widget.storage.saveSettings({
      'mode': _mode == DictationMode.auto ? 'auto' : 'manual',
      'readCount': _readCount,
      'interval': _intervalSeconds,
      'repeatInterval': _repeatIntervalSeconds,
      'shuffle': _shuffle,
      'speed': _speed,
      'beep': _beepEnabled,
    });
  }

  /// 添加日志
  void _log(String msg) {
    final time = DateTime.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add('[$stamp] $msg');
    });
    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 显示 Snackbar
  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 测试语音：诊断 TTS 并播放测试音，弹窗显示诊断信息
  Future<void> _showDiagnosis() async {
    _log('🔊 正在诊断并播放测试语音...');
    final diag = await _tts.diagnose();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TTS 诊断信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: diag.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${e.key}：${e.value}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 开始听写
  void _start() async {
    if (widget.words.isEmpty) {
      _showSnack('没有词语', error: true);
      return;
    }

    // 初始化 TTS
    await _tts.init();

    // 准备词语列表
    _shuffledWords = List.from(widget.words);
    if (_shuffle) {
      _shuffledWords.shuffle();
    }
    _currentIndex = -1;
    _status = DictationStatus.running;
    _logs.clear();
    _log('开始听写：${widget.wordListName}（共 ${_shuffledWords.length} 个词语）');
    _log('模式：${_mode == DictationMode.auto ? '自动定时' : '手动'}，'
        '朗读 $_readCount 遍，词间间隔 $_intervalSeconds 秒'
        '${_readCount == 2 ? '，两遍间隔 $_repeatIntervalSeconds 秒' : ''}');
    _saveSettings();
    // 持有 PARTIAL_WAKE_LOCK：屏幕可关，但 CPU 不休眠，黑屏后倒计时照常走、TTS 自动播下一个词
    await WakeLockService.enable();
    _nextWord();
  }

  /// 播报下一个词语
  Future<void> _nextWord() async {
    if (_status != DictationStatus.running) return;

    _currentIndex++;
    if (_currentIndex >= _shuffledWords.length) {
      _finish();
      return;
    }

    final word = _shuffledWords[_currentIndex];
    _log('▶ 第 ${_currentIndex + 1}/${_shuffledWords.length} 个词：$word');
    setState(() => _isSpeaking = true);

    try {
      // 每个词语前先播放"叮咚"提示音，间隔 1 秒后再播报词语
      if (_beepEnabled) {
        await _tts.playBeep();
        if (_status != DictationStatus.running) return;
        await Future.delayed(const Duration(seconds: 1));
        if (_status != DictationStatus.running) return;
      }
      await _tts.speak(
        word,
        repeat: _readCount,
        repeatIntervalSeconds: _repeatIntervalSeconds,
      );
    } catch (e) {
      _log('⚠ 播报出错：$e');
    }

    if (!mounted) return;
    setState(() => _isSpeaking = false);

    if (_status != DictationStatus.running) return;

    if (_mode == DictationMode.auto) {
      // 自动模式：倒计时后自动下一个
      _startCountdown();
    } else {
      // 手动模式：等待用户点击
      _log('⏸ 等待点击「下一条」');
      setState(() {});
    }
  }

  /// 开始倒计时
  void _startCountdown() {
    _countdown = _totalInterval;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
      });
      if (_countdown <= 0) {
        timer.cancel();
        _nextWord();
      }
    });
  }

  /// 手动下一个词（自动模式下可跳过当前词：取消倒计时立即下一条）
  void _manualNext() {
    if (_status != DictationStatus.running) return;
    _countdownTimer?.cancel();
    setState(() => _isSpeaking = false);
    _nextWord();
  }

  /// 暂停
  void _pause() {
    if (_status != DictationStatus.running) return;
    _countdownTimer?.cancel();
    _tts.stop();
    setState(() {
      _status = DictationStatus.paused;
      _isSpeaking = false;
    });
    _log('⏸ 已暂停');
  }

  /// 继续
  void _resume() {
    if (_status != DictationStatus.paused) return;
    setState(() => _status = DictationStatus.running);
    _log('▶ 继续听写');
    if (_mode == DictationMode.auto) {
      // 继续时重新播报当前词
      _currentIndex--;
      _nextWord();
    }
  }

  /// 停止
  void _stop() {
    _countdownTimer?.cancel();
    _tts.stop();
    WakeLockService.disable();
    setState(() {
      _status = DictationStatus.idle;
      _currentIndex = -1;
      _isSpeaking = false;
      _countdown = 0;
    });
    _log('⏹ 已停止听写');
  }

  /// 完成
  void _finish() {
    _countdownTimer?.cancel();
    WakeLockService.disable();
    setState(() {
      _status = DictationStatus.finished;
      _isSpeaking = false;
    });
    _log('🎉 听写完成！共 ${_shuffledWords.length} 个词语');
    _showSnack('听写完成！');
  }

  /// 加入错题本
  Future<void> _addToMistakeBook() async {
    if (_currentWord.isEmpty) {
      _showSnack('当前没有词语', error: true);
      return;
    }
    final added = await widget.storage.addToMistakeBook(_currentWord);
    if (added) {
      _log('📌 已加入错题本：$_currentWord');
      _showSnack('「$_currentWord」已加入错题本');
    } else {
      _log('📌 错题本已存在：$_currentWord');
      _showSnack('「$_currentWord」已在错题本中');
    }
  }

  /// 重新播报当前词
  Future<void> _replayCurrent() async {
    if (_currentWord.isEmpty) return;
    _log('🔁 重播：$_currentWord');
    setState(() => _isSpeaking = true);
    await _tts.speak(
      _currentWord,
      repeat: _readCount,
      repeatIntervalSeconds: _repeatIntervalSeconds,
    );
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wordListName),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 上方内容：超高时可滚动，避免被裁切
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // 配置区（仅空闲时可改）
                    _buildConfigPanel(),
                    const Divider(height: 1),
                    // 状态显示区
                    _buildStatusPanel(),
                    const Divider(height: 1),
                    // 控制按钮区
                    _buildControlPanel(),
                  ],
                ),
              ),
            ),
            // 日志区：固定高度，始终贴底
            SizedBox(
              height: 150,
              child: _buildLogPanel(),
            ),
          ],
        ),
      ),
    );
  }

  /// 配置面板
  Widget _buildConfigPanel() {
    final disabled = _status != DictationStatus.idle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              const Text('模式：', style: TextStyle(fontWeight: FontWeight.bold)),
              ChoiceChip(
                label: const Text('自动定时'),
                selected: _mode == DictationMode.auto,
                onSelected: disabled
                    ? null
                    : (v) => setState(() => _mode = DictationMode.auto),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('手动'),
                selected: _mode == DictationMode.manual,
                onSelected: disabled
                    ? null
                    : (v) => setState(() => _mode = DictationMode.manual),
              ),
              const SizedBox(width: 12),
              // 测试按钮放在「手动」后面，任何时候都可点击测试
              OutlinedButton.icon(
                onPressed: _showDiagnosis,
                icon: const Icon(Icons.volume_up, size: 16),
                label: const Text('测试'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('朗读：', style: TextStyle(fontWeight: FontWeight.bold)),
              ChoiceChip(
                label: const Text('1遍'),
                selected: _readCount == 1,
                onSelected: disabled ? null : (v) => setState(() => _readCount = 1),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('2遍'),
                selected: _readCount == 2,
                onSelected: disabled ? null : (v) => setState(() => _readCount = 2),
              ),
              const SizedBox(width: 16),
              if (_mode == DictationMode.auto) ...[
                const Text('间隔：', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !disabled,
                    decoration: const InputDecoration(
                      suffixText: '秒',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) {
                        setState(() => _intervalSeconds = n);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          // 朗读2遍时：两遍之间的间隔用数字输入框，可任意填写正整数秒
          if (_readCount == 2) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('两遍间隔：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    controller: _repeatIntervalCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !disabled,
                    decoration: const InputDecoration(
                      suffixText: '秒',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) {
                        setState(() => _repeatIntervalSeconds = n);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_mode == DictationMode.auto)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    '每词总间隔 $_totalInterval 秒'
                    '（基础 $_intervalSeconds + 两遍 $_repeatIntervalSeconds）',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('语速：', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final rate in [0.5, 0.75, 1.0, 1.25]) ...[
                ChoiceChip(
                  label: Text(rate.toString()),
                  selected: _speed == rate,
                  onSelected: disabled
                      ? null
                      : (v) async {
                          setState(() => _speed = rate);
                          await _tts.setSpeed(rate);
                        },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('提示音：', style: TextStyle(fontWeight: FontWeight.bold)),
              Switch(
                value: _beepEnabled,
                onChanged: disabled
                    ? null
                    : (v) => setState(() => _beepEnabled = v),
              ),
              const Spacer(),
              const Text('随机打乱：', style: TextStyle(fontWeight: FontWeight.bold)),
              Switch(
                value: _shuffle,
                onChanged: disabled ? null : (v) => setState(() => _shuffle = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 状态面板（紧凑布局，避免控制按钮被底部日志遮挡）
  Widget _buildStatusPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // 进度
          LinearProgressIndicator(
            value: _shuffledWords.isEmpty
                ? 0
                : (_currentIndex + 1) / _shuffledWords.length,
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(
            _status == DictationStatus.idle
                ? '点击「开始」进行听写'
                : _status == DictationStatus.finished
                    ? '听写完成 🎉'
                    : '进度：${_currentIndex + 1} / ${_shuffledWords.length}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          // 当前词提示（不显示具体词，避免作弊）
          if (_isSpeaking)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 6),
                Text('正在播报...',
                    style: TextStyle(color: Colors.blue, fontSize: 13)),
              ],
            )
          else if (_mode == DictationMode.auto &&
              _countdown > 0 &&
              _status == DictationStatus.running)
            Text(
              '$_countdown 秒后播报下一个词',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            )
          else if (_mode == DictationMode.manual &&
              _status == DictationStatus.running)
            const Text(
              '请点击「下一条」继续',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
        ],
      ),
    );
  }

  /// 控制面板
  Widget _buildControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          if (_status == DictationStatus.idle ||
              _status == DictationStatus.finished)
            ElevatedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          if (_status == DictationStatus.running)
            ElevatedButton.icon(
              onPressed: _pause,
              icon: const Icon(Icons.pause),
              label: const Text('暂停'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          if (_status == DictationStatus.paused)
            ElevatedButton.icon(
              onPressed: _resume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('继续'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          if (_status == DictationStatus.running ||
              _status == DictationStatus.paused)
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          if (_status == DictationStatus.running ||
              _status == DictationStatus.paused) ...[
            OutlinedButton.icon(
              onPressed: _replayCurrent,
              icon: const Icon(Icons.replay),
              label: const Text('重播'),
            ),
            // 下一条：运行中（自动/手动模式）都显示，放在「重播」后面。
            // 自动模式下点击会取消当前倒计时，立即跳到下一个词。
            if (_status == DictationStatus.running)
              ElevatedButton.icon(
                onPressed: _manualNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('下一条'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addToMistakeBook,
              icon: const Icon(Icons.bookmark_add),
              label: const Text('加入错题本'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange),
            ),
          ],
        ],
      ),
    );
  }

  /// 日志面板
  Widget _buildLogPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '实时日志',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _logs[i],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
