# 简易听写 APP

基于 Flutter 开发的本地听写应用，所有数据保存在手机本地，无需网络。

## 功能特性

### 一、词单管理
- **新建词单**：自定义名称，录入词语（一行一个，或空格/逗号/分号/顿号分隔）
- **加载词单**：下拉选择已保存词单，一键读取到编辑框
- **删除词单**：选中后删除（内置错题本不可删除，只能清空）
- **内置错题本**：听写时可一键加入，自动去重
- **错题本管理**：勾选框模式，支持全选/反选、批量删除单个或多个错题
- **清空错题本**：带确认弹窗，防止误操作

### 二、文件导入导出
- **导入 TXT**：从设备选择 txt 文件，自动解析词语
- **导出 TXT**：将当前词语列表保存为 txt 文件（UTF-8 BOM，兼容 Windows 记事本）

### 三、听写核心
- **两种模式**：自动定时（间隔秒数后自动下一个）/ 手动（点击下一个词）
- **朗读次数**：每个词读 1 遍或 2 遍
- **自定义间隔**：自由设置词语间等待秒数
- **随机打乱**：每次开始自动打乱词序
- **听写控制**：开始、暂停/继续、停止、重播当前词
- **加入错题本**：听写中一键添加当前词
- **实时日志**：黑色终端风格日志区，显示播报进度

### 四、底层特性
- **本地存储**：SharedPreferences + JSON，零网络请求
- **系统 TTS**：调用系统中文语音引擎
- **跨平台**：支持 Android、Windows、macOS

## 项目结构

```
simple_dictation/
├── pubspec.yaml              # 依赖配置
├── lib/
│   ├── main.dart             # 应用入口
│   ├── models/
│   │   └── word_list.dart    # 词单数据模型
│   ├── services/
│   │   ├── storage_service.dart  # 本地存储服务
│   │   ├── tts_service.dart      # TTS 语音服务
│   │   └── file_service.dart     # 文件导入导出服务
│   └── screens/
│       ├── home_screen.dart      # 主页（词单管理）
│       └── dictation_screen.dart # 听写页面
└── android/
    └── app/src/main/AndroidManifest.xml
```

## 依赖包

| 包名 | 版本 | 用途 |
|------|------|------|
| shared_preferences | ^2.2.2 | 本地键值存储 |
| flutter_tts | ^4.0.2 | 系统 TTS 语音播报 |
| file_picker | ^8.0.0+1 | 文件选择与保存 |
| path_provider | ^2.1.2 | 获取应用目录 |

## 运行方法

### 1. 环境准备
- 安装 Flutter SDK 3.0+
- 配置 Android SDK（用于 Android 构建）
- Android 设备需提前在系统设置中下载中文语音包（TTS）

### 2. 获取依赖
```bash
cd simple_dictation
flutter pub get
```

### 3. 运行
```bash
# 连接 Android 设备后
flutter run

# Windows 桌面
flutter run -d windows

# macOS 桌面
flutter run -d macos
```

### 4. 构建发布包
```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

## GitHub Actions 自动编译

项目已内置 `.github/workflows/build.yml`，推送到 GitHub 后自动编译 Android APK：

1. 将本项目推送到 GitHub 仓库（`main` 或 `master` 分支）
2. GitHub Actions 自动触发，执行：安装 Flutter → `flutter pub get` → 补全 Android 工程 → `flutter analyze` → `flutter build apk --release`
3. 编译完成后，在仓库的 **Actions** 页面找到对应运行记录，下载 **Artifacts** 中的 `simple-dictation-apk` 压缩包，解压即得 APK
4. 也可在仓库页面点击 **Actions** → 左侧 **Build Android APK** → **Run workflow** 手动触发

> 工作流会自动检测 `android/` 目录是否存在，缺失时自动执行 `flutter create .` 补全，因此只需上传 `lib/`、`pubspec.yaml`、`.github/` 等核心文件即可。

## Android 注意事项

1. **中文 TTS**：部分 Android 设备默认无中文语音，需在 `设置 → 语言和输入法 → 文字转语音输出` 中下载中文语音数据
2. **存储权限**：Android 13+ 应用通过系统文件选择器访问文件，无需额外授权；旧版本可能需要存储权限
3. **最小 SDK**：建议 `minSdkVersion 21`（Android 5.0）

## 使用流程

1. **创建词单**：输入词单名称 → 在词语框输入词语（每行一个）→ 点击「保存词单」
2. **开始听写**：点击「开始听写」→ 选择模式/朗读次数/间隔 → 点击「开始」
3. **听写中**：自动模式下等待倒计时；手动模式点击「下一个词」；不会的词点「加入错题本」
4. **复习错题**：返回主页 → 下拉选择「错题本」→ 开始听写复习

## 数据安全

- 所有词单和设置均保存在应用私有目录，不上传任何服务器
- 卸载应用会清除所有本地数据，建议定期「导出 TXT」备份
