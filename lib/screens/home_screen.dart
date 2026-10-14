import 'package:flutter/material.dart';
import '../models/word_list.dart';
import '../services/storage_service.dart';
import '../services/file_service.dart';
import 'dictation_screen.dart';
import 'mistake_book_screen.dart';

/// 主页面 - 词单管理
class HomeScreen extends StatefulWidget {
  final StorageService storage;
  final FileService fileService;

  const HomeScreen({
    super.key,
    required this.storage,
    required this.fileService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _wordsController = TextEditingController();
  final _scrollController = ScrollController();

  List<WordList> _wordLists = [];
  String? _selectedListId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wordsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() => _loading = true);
    final lists = await widget.storage.loadWordLists();
    setState(() {
      _wordLists = lists;
      _loading = false;
    });
  }

  /// 解析编辑框文本为词语列表
  List<String> get _currentWords =>
      widget.fileService.parseWords(_wordsController.text);

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

  /// 保存词单（新建或更新）
  Future<void> _saveList() async {
    final name = _nameController.text.trim();
    final words = _currentWords;

    if (name.isEmpty) {
      _showSnack('请输入词单名称', error: true);
      return;
    }
    if (words.isEmpty) {
      _showSnack('请输入至少一个词语', error: true);
      return;
    }

    // 如果选中了已有词单且名称相同，则更新；否则新建
    WordList? existing;
    if (_selectedListId != null) {
      try {
        existing = _wordLists.firstWhere((l) => l.id == _selectedListId);
      } catch (_) {
        existing = null;
      }
    }

    if (existing != null && existing.name == name) {
      // 更新已有词单
      final updated = existing.copyWith(words: words);
      await widget.storage.upsertWordList(updated);
      _showSnack('词单「$name」已更新（${words.length} 个词语）');
    } else {
      // 检查名称是否重复
      final dup = _wordLists.any((l) => l.name == name && l.id != _selectedListId);
      if (dup) {
        _showSnack('已存在同名词单「$name」', error: true);
        return;
      }
      // 新建词单
      final newList = WordList(
        id: 'list_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        words: words,
      );
      await widget.storage.upsertWordList(newList);
      _selectedListId = newList.id;
      _showSnack('词单「$name」已保存（${words.length} 个词语）');
    }
    await _loadLists();
  }

  /// 加载选中词单到编辑框
  void _loadSelectedList(String? id) {
    if (id == null) return;
    try {
      final list = _wordLists.firstWhere((l) => l.id == id);
      setState(() {
        _selectedListId = id;
        _nameController.text = list.name;
        _wordsController.text = list.words.join('\n');
      });
      _showSnack('已加载「${list.name}」（${list.wordCount} 个词语）');
    } catch (_) {}
  }

  /// 删除选中词单
  Future<void> _deleteSelectedList() async {
    if (_selectedListId == null) {
      _showSnack('请先选择要删除的词单', error: true);
      return;
    }
    final list = _wordLists.firstWhere(
      (l) => l.id == _selectedListId,
      orElse: () => WordList(id: '', name: '', isBuiltIn: true),
    );
    if (list.isBuiltIn) {
      _showSnack('错题本不能删除，只能清空内容', error: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除词单「${list.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteWordList(list.id);
      setState(() {
        _selectedListId = null;
        _nameController.clear();
        _wordsController.clear();
      });
      await _loadLists();
      _showSnack('词单「${list.name}」已删除');
    }
  }

  /// 打开错题本管理页面
  void _openMistakeBook() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MistakeBookScreen(storage: widget.storage),
      ),
    );
    // 返回后刷新词单列表（错题本数量可能变化）
    await _loadLists();
  }

  /// 清空错题本
  Future<void> _clearMistakeBook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空错题本'),
        content: const Text('确定要清空错题本中的所有词语吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.storage.clearMistakeBook();
      await _loadLists();
      // 如果当前正在查看错题本，清空编辑框
      if (_selectedListId == WordList.mistakeBookId) {
        _wordsController.clear();
      }
      _showSnack('错题本已清空');
    }
  }

  /// 导入 TXT
  Future<void> _importTxt() async {
    try {
      final content = await widget.fileService.importTxt();
      if (content == null) {
        _showSnack('已取消导入');
        return;
      }
      final words = widget.fileService.parseWords(content);
      if (words.isEmpty) {
        _showSnack('文件中没有找到有效词语', error: true);
        return;
      }
      setState(() {
        _wordsController.text = words.join('\n');
      });
      _showSnack('已导入 ${words.length} 个词语');
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  /// 导出 TXT
  Future<void> _exportTxt() async {
    final words = _currentWords;
    if (words.isEmpty) {
      _showSnack('编辑框为空，没有可导出的词语', error: true);
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? '词单导出'
        : _nameController.text.trim();
    try {
      final path = await widget.fileService.exportTxt(words, fileName: name);
      if (path != null) {
        _showSnack('已导出到: $path');
      } else {
        _showSnack('已取消导出');
      }
    } catch (e) {
      _showSnack(e.toString(), error: true);
    }
  }

  /// 清空编辑框
  void _clearEditor() {
    setState(() {
      _nameController.clear();
      _wordsController.clear();
      _selectedListId = null;
    });
  }

  /// 开始听写
  void _startDictation() {
    final words = _currentWords;
    if (words.isEmpty) {
      _showSnack('请先输入或加载词语', error: true);
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? '临时听写'
        : _nameController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DictationScreen(
          wordListName: name,
          words: words,
          storage: widget.storage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('简易听写'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '管理错题本',
            icon: const Icon(Icons.menu_book),
            onPressed: _openMistakeBook,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 词单选择区
                  _buildListSelector(),
                  const SizedBox(height: 16),
                  // 词单名称
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '词单名称',
                      hintText: '例如：三年级上册第一单元',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 词语编辑框
                  TextField(
                    controller: _wordsController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: '词语列表',
                      hintText: '一行一个词语，或用空格/逗号分隔\n例如：\n苹果\n香蕉\n橘子',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _wordsController.clear()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前共 ${_currentWords.length} 个词语',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // 操作按钮区
                  _buildActionButtons(),
                  const SizedBox(height: 24),
                  // 开始听写大按钮
                  ElevatedButton.icon(
                    onPressed: _startDictation,
                    icon: const Icon(Icons.play_circle_fill, size: 28),
                    label: const Text('开始听写', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 词单选择下拉
  Widget _buildListSelector() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedListId,
            decoration: const InputDecoration(
              labelText: '选择已有词单',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_open),
            ),
            items: _wordLists.map((list) {
              final isMistake = list.id == WordList.mistakeBookId;
              return DropdownMenuItem<String>(
                value: list.id,
                child: Row(
                  children: [
                    Icon(
                      isMistake ? Icons.error_outline : Icons.list_alt,
                      size: 18,
                      color: isMistake ? Colors.orange : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        list.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${list.wordCount}词',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: _loadSelectedList,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '删除选中词单',
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleteSelectedList,
          style: IconButton.styleFrom(
            foregroundColor: Colors.red,
          ),
        ),
      ],
    );
  }

  /// 操作按钮
  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _saveList,
          icon: const Icon(Icons.save),
          label: const Text('保存词单'),
        ),
        OutlinedButton.icon(
          onPressed: _clearEditor,
          icon: const Icon(Icons.refresh),
          label: const Text('清空编辑'),
        ),
        OutlinedButton.icon(
          onPressed: _importTxt,
          icon: const Icon(Icons.file_open),
          label: const Text('导入TXT'),
        ),
        OutlinedButton.icon(
          onPressed: _exportTxt,
          icon: const Icon(Icons.file_download),
          label: const Text('导出TXT'),
        ),
      ],
    );
  }
}
