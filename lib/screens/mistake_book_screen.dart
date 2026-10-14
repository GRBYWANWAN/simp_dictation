import 'package:flutter/material.dart';
import '../models/word_list.dart';
import '../services/storage_service.dart';

/// 错题本管理页面 - 勾选框模式批量删除
class MistakeBookScreen extends StatefulWidget {
  final StorageService storage;

  const MistakeBookScreen({super.key, required this.storage});

  @override
  State<MistakeBookScreen> createState() => _MistakeBookScreenState();
}

class _MistakeBookScreenState extends State<MistakeBookScreen> {
  WordList? _mistakeBook;
  final Set<int> _selectedIndices = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMistakeBook();
  }

  Future<void> _loadMistakeBook() async {
    setState(() => _loading = true);
    final book = await widget.storage.getMistakeBook();
    setState(() {
      _mistakeBook = book;
      _selectedIndices.clear();
      _loading = false;
    });
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 切换选中状态
  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// 全选 / 取消全选
  void _toggleSelectAll() {
    final words = _mistakeBook?.words ?? [];
    setState(() {
      if (_selectedIndices.length == words.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(List.generate(words.length, (i) => i));
      }
    });
  }

  /// 删除选中的词语
  Future<void> _deleteSelected() async {
    if (_selectedIndices.isEmpty) {
      _showSnack('请先勾选要删除的词语', error: true);
      return;
    }
    if (_mistakeBook == null) return;

    final count = _selectedIndices.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从错题本中删除选中的 $count 个词语吗？'),
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

    if (confirm != true) return;

    // 按索引降序删除，避免索引错位
    final sortedIndices = _selectedIndices.toList()..sort((a, b) => b - a);
    final newWords = List<String>.from(_mistakeBook!.words);
    for (final idx in sortedIndices) {
      if (idx >= 0 && idx < newWords.length) {
        newWords.removeAt(idx);
      }
    }
    _mistakeBook = _mistakeBook!.copyWith(words: newWords);
    await widget.storage.upsertWordList(_mistakeBook!);
    _showSnack('已删除 $count 个词语');
    await _loadMistakeBook();
  }

  /// 清空全部（带确认）
  Future<void> _clearAll() async {
    final words = _mistakeBook?.words ?? [];
    if (words.isEmpty) {
      _showSnack('错题本已是空的');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空错题本'),
        content: Text('确定要清空全部 ${words.length} 个词语吗？此操作不可恢复。'),
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
      _showSnack('错题本已清空');
      await _loadMistakeBook();
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _mistakeBook?.words ?? [];
    final allSelected = words.isNotEmpty && _selectedIndices.length == words.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本管理'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '清空全部',
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : words.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('错题本是空的',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text('听写时点击「加入错题本」即可添加',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 顶部工具栏：全选 + 选中计数
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: Colors.grey.shade100,
                      child: Row(
                        children: [
                          Checkbox(
                            value: allSelected,
                            onChanged: (_) => _toggleSelectAll(),
                          ),
                          GestureDetector(
                            onTap: _toggleSelectAll,
                            child: Text(allSelected ? '取消全选' : '全选',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ),
                          const Spacer(),
                          Text(
                            '共 ${words.length} 词，已选 ${_selectedIndices.length}',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // 词语列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: words.length,
                        itemBuilder: (ctx, index) {
                          final selected = _selectedIndices.contains(index);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (_) => _toggleSelect(index),
                            title: Text(
                              words[index],
                              style: TextStyle(
                                fontSize: 16,
                                decoration: selected
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: selected ? Colors.grey : null,
                              ),
                            ),
                            secondary: Text(
                              '${index + 1}',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 13),
                            ),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                  ],
                ),
      // 底部删除按钮
      bottomNavigationBar: _selectedIndices.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete),
                  label: Text('删除选中（${_selectedIndices.length}）'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
