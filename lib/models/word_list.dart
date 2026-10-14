/// 词单数据模型
class WordList {
  /// 唯一标识
  final String id;

  /// 词单名称
  String name;

  /// 词语列表
  List<String> words;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  DateTime updatedAt;

  /// 是否为系统内置错题本（不可删除）
  final bool isBuiltIn;

  WordList({
    required this.id,
    required this.name,
    List<String>? words,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isBuiltIn = false,
  })  : words = words ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 错题本固定 ID
  static const String mistakeBookId = 'mistake_book';

  /// 创建错题本实例
  factory WordList.mistakeBook() {
    return WordList(
      id: mistakeBookId,
      name: '错题本',
      isBuiltIn: true,
    );
  }

  /// 从 JSON 反序列化
  factory WordList.fromJson(Map<String, dynamic> json) {
    return WordList(
      id: json['id'] as String,
      name: json['name'] as String,
      words: (json['words'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'words': words,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isBuiltIn': isBuiltIn,
    };
  }

  /// 添加词语（自动去重）
  void addWord(String word) {
    final trimmed = word.trim();
    if (trimmed.isNotEmpty && !words.contains(trimmed)) {
      words.add(trimmed);
      updatedAt = DateTime.now();
    }
  }

  /// 批量添加词语（自动去重）
  void addWords(List<String> newWords) {
    for (final w in newWords) {
      addWord(w);
    }
  }

  /// 清空词语
  void clearWords() {
    words.clear();
    updatedAt = DateTime.now();
  }

  /// 词语数量
  int get wordCount => words.length;

  /// 复制（用于编辑）
  WordList copyWith({
    String? name,
    List<String>? words,
  }) {
    return WordList(
      id: id,
      name: name ?? this.name,
      words: words ?? List.from(this.words),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isBuiltIn: isBuiltIn,
    );
  }
}
