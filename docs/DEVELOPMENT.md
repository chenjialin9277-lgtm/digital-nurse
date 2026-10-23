# 开发与架构说明

## 开发环境

| 工具 | 交接基线 |
| --- | --- |
| Flutter / Dart | 3.44.6 / 3.12.2；`.flutter-version` 记录 Flutter 版本 |
| JDK | 17 |
| Android SDK / NDK | API 36 / 27.0.12077973 |
| Gradle / Android Gradle Plugin / Kotlin | 8.10.2 / 8.7.0 / 1.8.22 |
| 最低设备系统 | Android 7.0 / API 24 |
| 包名 / 版本 | `com.digitalnurse.app` / `0.17.0+23` |

安装 Android Studio 或 Android 命令行 SDK，安装 platform-tools、platforms;android-36、build-tools;36.0.0、ndk;27.0.12077973 并接受 SDK 许可。设置 `JAVA_HOME`、`ANDROID_HOME`，将 Flutter/bin 加入 PATH，执行 `flutter doctor -v`。本次整理保留已使用的依赖版本，不进行整套框架升级。

首次执行 `flutter pub get` 后，Flutter 会生成本机 `android/local.properties`。其 `sdk.dir` 和 `flutter.sdk` 必须指向接手者自己的工具链，不复制开发者原电脑的路径。

## 检查、调试与打包

```bash
git lfs install
git lfs pull
flutter pub get
bash scripts/check.sh
flutter run -d <Android设备ID>
flutter build apk --debug
(cd android && ./gradlew testDebugUnitTest)
```

`check.sh` 依次执行依赖获取、87 个 Dart 文件格式检查、Dart 静态分析、全量 Flutter 测试及资源/仓库校验。若 Dart 文件数量后续变化，按实际文件数计算。图像基准由 macOS 环境生成，CI 使用 macOS；出现图像差异应检查渲染环境及真实布局变化，不直接覆盖基准图。

本机 Flutter 3.44.6 的 `flutter analyze` 在含中文的工作路径下出现 LSP 报文解析错误，因此统一使用同一 SDK 的 `dart analyze --fatal-infos`，可完整检查本工程。此问题属于本地工具链兼容现象，未通过关闭 lint 处理。

正式 APK 使用 `flutter build apk --release`。签名配置示例是 `android/key.properties.example`，真实配置及密钥需要项目负责人私下移交；缺少配置不能生成正式发布包。不要用调试签名替代原正式签名。升级 APK 应增加 `pubspec.yaml` 的版本及构建号，并先备份目标平板配置和宣教内容。

## 启动与依赖关系

1. `main.dart` 初始化 Flutter、横屏/沉浸模式和 Opus。
2. `NurseController.initializeLocalState()` 在首页可交互前读取配置、执行旧宣教迁移，避免默认值覆盖旧科室数据。
3. `DigitalNurseApp` 经 Provider 暴露控制器；首屏显示后异步启动小智绑定与连接。
4. 首页经 `NurseController` 协调在线服务、离线宣教、收藏、配置与网络状态。

| 模块 | 入口与职责 |
| --- | --- |
| 首页 | `lib/screens/nurse_screen.dart`：字幕、按住说话、品牌、常用宣教和工作台入口 |
| 连接 | `xiaozhi_provisioning_service.dart`：OTA/激活；`xiaozhi_websocket_manager.dart`：握手、音频包与退避重连；`xiaozhi_service.dart`：协议会话、语音及静默翻译请求 |
| 音频 | `AudioUtil`：16 kHz 单声道、60 ms Opus 帧；`OnlinePlaybackGate`：线上/本地音频切换；`PushToTalkAudioSession`：录音起停顺序 |
| 离线三语 | `OfflineMultilingualTts`：模型提取、工作 Isolate、分段合成和预缓冲；`OfflineSpeechCache`：内存与本地 PCM 缓存 |
| 宣教 | `lib/features/education/` 按 models/data/controllers/screens/widgets/services 分层；文本、视频使用同一项目模型的不同 kind |
| 配置及统计 | `NurseConfigRepository`：配置与加密凭据；`AppUsageRepository`：匿名普通使用事件；教育事件走 SQLite |
| Android | `MainActivity`：系统桥接及媒体导入/导出；`EducationDatabase*`：SQLite；`EducationVideoActivity`：视频；`UsageXlsxWriter`：纯 XLSX 编码 |
| PCM 插件 | `packages/flutter_pcm_player/`：本地维护的 Java AudioTrack 实现；勿重新替换为已过时的 pub 包 |

## 平台通道

| 通道 | 方法/事件 |
| --- | --- |
| `digital_nurse/system` | `openUrl`、`speakText`、`stopLocalSpeech`、`pickDepartmentLogo`、`pickNurseAvatar`、`pickEducationVideo`、`playEducationVideo`、`deleteEducationVideo`、`saveUsageXlsx` |
| `digital_nurse/network_status` | Android 网络状态事件 |
| `digital_nurse/local_tts_status` | 历史系统 TTS 状态桥；当前主宣教使用内置模型 |
| `digital_nurse/education_database` | `loadActive`、`loadAll`、`replaceAll`、`replaceAllAndMarkLegacyMigrated`、`save`、`softDelete`、`reorder`、迁移标志及教育事件读写 |
| `flutter_pcm_player` | 初始化、播放、暂停、停止、释放及 PCM 数据投递 |

应用当前完整实现目标是 Android；其他平台目录是保留的上游骨架。Android 平台通道与本地 PCM 插件并没有全部实现跨平台替代，不能依据目录存在就宣布支持 iOS/桌面/Web。

## 本地数据与兼容约定

- SharedPreferences `digital_nurse_config_v1`：科室配置、三语选择、旧快捷回答；Token 不保存在明文配置中。
- FlutterSecureStorage：`digital_nurse_xiaozhi_token`、`digital_nurse_settings_password`。
- SharedPreferences `digital_nurse_usage_records_v1`：普通使用统计，最多保留 50,000 条；写操作串行化。
- SQLite `digital_nurse.db`，当前版本 **2**：`education_items`、`education_meta`、`education_events`。保持历史 onCreate/onUpgrade 逻辑兼容；后续结构升级应新增版本迁移。
- `legacy_migration_completed`：旧配置转为结构化宣教的完成标志；内容和标志必须通过原子接口一起写入。
- 应用私有目录 `education_videos`：视频副本；`nurse_avatars`：标准形象；离线模型及音频缓存使用 application support 下的 `offline_tts`。
- 宣教事件使用 UTC 保存与查询，展示/Excel 时转为本地时间；会话 ID 为随机匿名标识。

保留已安装设备的应用 ID、签名、配置键、通道名称、JSON 字段及数据库升级链。换包名或签名会影响覆盖升级；卸载通常会清空本机数据。

## 发布与内容规则

已发布且完整的语言才进入患者端；缺失译文不默认回退为普通话。智能同步生成的粤语/英语必须保持 `published=false`、`needsReview=true`，由科室复核后逐语言发布；理解题选项数和正确答案位置必须一致。不要在代码整理中更改临床宣教事实、药物数字或已发布文案。

发布前继续使用根目录 `RELEASE_CHECKLIST.md`。本次上传是开发交接，不是生产部署、商用授权或临床验证。

## 资源与归档

`docs/asset-manifest.json` 记录全部 405 项开发资源的 SHA-256 和大小，包括当前模型、图片、原始素材和历史 3D 资源。新增或修改资源时同步更新该清单，并执行校验。`.onnx` 与 `.glb` 由 Git LFS 管理；不得将指针文件误当成可用模型。

`docs/archive/upstream/website` 为原 VitePress 源码，未包含 node_modules 或缓存，不参与应用运行和当前自动发布。`docs/superpowers/` 保留历史设计/实施记录，其中计划项需对照实际代码确认，不等同于已经实现。

## 后续维护边界

- 录音质量统计 `MicrophoneCaptureTracker` 已存在，但 `hasValidSpeech` 尚未接入发送停止/中断决策，详见交接文档；不要把单元测试视为已完成端到端质量门禁。
- 离线 PCM 磁盘缓存目前没有总容量清理策略，大量长宣教应评估存储占用。
- MainActivity 的大图片转换及 Excel 生成仍可进一步移到后台任务；XLSX 编码已独立为可做 JVM 测试的模块。
- 本次未改用新数据库版本，也未更改患者端主要交互和宣教发布规则。
