# 数字护士 Android 平板客户端

面向 Android 横屏平板的数字护士：小智 AI 在线问答、普通话/粤语/英语离线床旁宣教、理解确认、本地视频宣教、科室配置和匿名使用统计。

- 当前应用版本：**0.17.0+23**；本仓库是 2026-10-23 整理的开发交接版本。
- 支持目标：Android 7.0（API 24）及以上；通用 APK 包含 ARM32、ARM64、x86_64。
- 仓库：<https://github.com/chenjialin9277-lgtm/digital-nurse>（私有，需要仓库访问权限）。
- 工具链：Flutter **3.44.6** / Dart **3.12.2**、JDK **17**、Android SDK **36**、NDK **27.0.12077973**。

## 同事从这里开始

1. 阅读 [开发交接](docs/HANDOFF.md)，了解当前状态和接手事项。
2. 按下列步骤下载完整源码及模型，运行检查。
3. 查看 [开发与架构说明](docs/DEVELOPMENT.md)、[审查报告](docs/AUDIT.md) 和 [文件清单](docs/SOURCE_INVENTORY.md)。

```bash
# 先安装 Git LFS；例如 macOS 使用 brew install git-lfs。
git lfs install
git clone https://github.com/chenjialin9277-lgtm/digital-nurse.git
cd digital-nurse
git lfs pull

# 将 Flutter 3.44.6/bin 加入 PATH，并配置 JDK 17、Android SDK。
flutter --version
flutter pub get
bash scripts/check.sh

# 连接已开启 USB 调试的 Android 平板。
flutter devices
flutter run
```

**模型使用 Git LFS 保存**，包括超过普通 Git 单文件限制的粤语模型。必须使用 Git + LFS 下载；GitHub 的“Download ZIP”不能作为已验证的完整开发副本。资源是否齐全可单独检查：

```bash
python3 scripts/verify_repository.py
```

## 构建 APK

```bash
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk
```

Debug 构建不需要正式签名。正式构建前，将 `android/key.properties.example` 复制为 `android/key.properties`，向项目负责人私下取得原签名文件及密码后填写，再执行：

```bash
flutter build apk --release
```

应用 ID `com.digitalnurse.app` 和原正式签名必须保持一致，才能覆盖升级现有设备并保留本机数据。缺少正式签名时 Release 构建会明确失败。Debug APK 使用调试签名，不能用于覆盖现有正式签名安装。

## 功能与运行方式

- **在线问答**：按住主按钮说话、松开发送；通过小智 WebSocket 与 Opus 16 kHz 单声道音频连接科室智能体。
- **首次绑定**：设置默认使用官方 OTA 激活流程；在 <https://xiaozhi.me> 添加设备并输入平板显示的激活码。自建服务器模式可手工配置连接地址和 Token。
- **文字宣教**：分类、搜索、收藏、三语内容及离线语音，播放后进入理解确认；旧科室内容在首次启动时迁移。
- **三语智能同步**：复用已绑定的小智账号生成粤语和英语草稿，必须逐语言复核发布；生成需要联网，已发布内容可离线播放。
- **视频宣教**：从系统选择器导入，复制到应用私有目录，在应用内横屏播放。
- **设置与品牌**：科室名称、Logo、护士形象、启动字幕、主题和管理员密码均可配置。首次接手应更改默认设置密码 `123456`。
- **匿名统计**：本机保存使用事件，按日期查询并导出五张工作表的 Excel 文件；不需要自建业务后端。

涉及病情变化、诊断、用药或紧急情况时应联系医护人员。当前语音模型及形象授权状态见 [发布检查清单](RELEASE_CHECKLIST.md)，交接上传不代表已完成正式商业发布。

## 工程目录

| 路径 | 用途 |
| --- | --- |
| `lib/controllers/`、`lib/screens/`、`lib/widgets/` | 首页状态、交互、设置及通用界面 |
| `lib/features/education/` | 宣教模型、仓储、会话、管理与播放页面 |
| `lib/services/`、`lib/repositories/` | 在线连接、离线语音、缓存、配置和统计 |
| `android/app/src/main/kotlin/com/digitalnurse/app/` | 数据库、系统选择器、视频播放、Excel 导出及网络事件 |
| `packages/flutter_pcm_player/` | 项目内维护的 Android PCM 插件 |
| `assets/images/`、`assets/tts/` | 当前应用图片与三语语音模型 |
| `assets/source/`、`assets/avatar3d/` | 原始品牌素材和历史 3D 实验资源，均保留供后续开发 |
| `test/` | 单元、界面、升级兼容和图像基准测试 |
| `scripts/`、`tool/` | 统一检查、仓库与资源校验、离线语音验证工具 |
| `docs/` | 当前开发交接资料及资源校验清单 |
| `docs/archive/` | 原始项目文档、旧版本说明和历史设计材料 |
| `ios/`、`macos/`、`linux/`、`windows/`、`web/` | 上游平台工程骨架，当前数字护士仅验收 Android |

## 自动检查与开发约定

每次提交前执行 `bash scripts/check.sh`。GitHub Actions 自动检查格式、静态分析、全部测试和资源完整性；手动运行工作流时可额外生成 Debug APK。工作流不自动发布应用或文档网站。

保留 `pubspec.lock`；以 `main` 为接手基线，在 `feature/*`、`fix/*` 或 `refactor/*` 分支开发。数据库版本、旧配置键、应用 ID、MethodChannel 名称和发布审核规则的兼容要求见开发说明。

签名密钥、密码、设备 Token、构建缓存、历史 APK 和含签名的备份留在受控的本地环境。所有当前源码、平台工程、测试、模型、运行素材及原始设计资源均随本仓库交接。

## 版权与历史

本工程改造自 [TOM88812/xiaozhi-android-client](https://github.com/TOM88812/xiaozhi-android-client)，保留原提交历史和 Apache-2.0 许可；详见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 和 [PCM 插件许可](packages/flutter_pcm_player/LICENSE)。

原多语言 README、文档网站源码、赞助页及旧说明移至 [上游资料归档](docs/archive/upstream/README.md)；整理前的数字护士版本记录见 [原 README](docs/archive/README-before-handoff.md)。历史材料中的命令和平台支持信息不作为当前开发入口。
