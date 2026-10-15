import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word_list.dart';

/// 本地存储服务 - 使用 SharedPreferences + JSON 保存全部词单
class StorageService {
  static const String _keyWordLists = 'word_lists';
  static const String _keySettings = 'dictation_settings';

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 首次启动确保错题本存在
    final lists = await loadWordLists();
    if (!lists.any((l) => l.id == WordList.mistakeBookId)) {
      lists.insert(0, WordList.mistakeBook());
      await saveWordLists(lists);
    }
  }

  SharedPreferences get _p {
    if (_prefs == null) {
      throw Exception('StorageService 未初始化，请先调用 init()');
    }
    return _prefs!;
  }

  /// 加载所有词单
  Future<List<WordList>> loadWordLists() async {
    final raw = _p.getString(_keyWordLists);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => WordList.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存所有词单
  Future<void> saveWordLists(List<WordList> lists) async {
    final encoded = jsonEncode(lists.map((e) => e.toJson()).toList());
    await _p.setString(_keyWordLists, encoded);
  }

  /// 新增或更新词单
  Future<void> upsertWordList(WordList list) async {
    final lists = await loadWordLists();
    final idx = lists.indexWhere((l) => l.id == list.id);
    if (idx >= 0) {
      lists[idx] = list;
    } else {
      lists.add(list);
    }
    await saveWordLists(lists);
  }

  /// 删除词单（内置错题本不可删除）
  Future<bool> deleteWordList(String id) async {
    if (id == WordList.mistakeBookId) return false;
    final lists = await loadWordLists();
    lists.removeWhere((l) => l.id == id);
    await saveWordLists(lists);
    return true;
  }

  /// 获取错题本
  Future<WordList?> getMistakeBook() async {
    final lists = await loadWordLists();
    for (final l in lists) {
      if (l.id == WordList.mistakeBookId) return l;
    }
    return null;
  }

  /// 向错题本添加词语（自动去重）
  Future<bool> addToMistakeBook(String word) async {
    final book = await getMistakeBook();
    if (book == null) return false;
    final before = book.wordCount;
    book.addWord(word);
    if (book.wordCount > before) {
      await upsertWordList(book);
      return true;
    }
    return false;
  }

  /// 清空错题本（保留词单本身）
  Future<void> clearMistakeBook() async {
    final book = await getMistakeBook();
    if (book != null) {
      book.clearWords();
      await upsertWordList(book);
    }
  }

  /// 保存听写设置
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _p.setString(_keySettings, jsonEncode(settings));
  }

  /// 加载听写设置
  Future<Map<String, dynamic>> loadSettings() async {
    final raw = _p.getString(_keySettings);
    if (raw == null || raw.isEmpty) {
      return {
        'mode': 'auto', // auto / manual
        'readCount': 1, // 1 / 2
        'interval': 5, // 词间基础间隔（秒）
        'repeatInterval': 1, // 朗读2遍时，两遍间隔（秒）
        'shuffle': true,
        'speed': 1.0, // 语速：0.75 / 1.0 / 1.25
        'beep': true, // 每词前提示音
      };
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {
        'mode': 'auto',
        'readCount': 1,
        'interval': 5,
        'repeatInterval': 1,
        'shuffle': true,
        'speed': 1.0,
        'beep': true,
      };
    }
  }
}
