# 数字护士开发交接

交接日期：2026-10-23。应用版本：0.17.0+23。

## 仓库与接手入口

- 仓库：<https://github.com/chenjialin9277-lgtm/digital-nurse>
- 可见性：私有；项目负责人需要在 GitHub Settings → Collaborators 中给接手同事授权。
- 接手分支：`main`；整理过程保留在 `refactor/developer-handoff-20261023`。
- 克隆必须启用 Git LFS，再执行 `git lfs pull`，确保三个 ONNX 模型及 GLB 资源是实际文件。
- 当前说明从根目录 README 开始；完整环境、架构、通道和数据规则见 `DEVELOPMENT.md`；实际检查结论及待办见 `AUDIT.md`。

## 已交接内容

完整 v0.17 源码及此前未提交的业务模型、仓储、三语 TTS/音频缓存、本地视频、智能翻译、原生数据库/媒体桥接、本地 PCM 插件、自动化测试、图片/三语模型/原始素材、平台工程及依赖锁文件。

本次统一格式和开发规范，整理历史文档，修复宣教重试、模型哈希、事件监听器回调问题，抽取可独立测试的 XLSX 编码模块，修正签名配置和 CI，增加资源校验。原 Git 提交历史保留，上游地址保留为 upstream；没有将上游后续通用客户端改动直接合入本产品。

## 首日接手步骤

```bash
git lfs install
git clone https://github.com/chenjialin9277-lgtm/digital-nurse.git
cd digital-nurse
git lfs pull
flutter --version   # 3.44.6，配套 Dart 3.12.2
flutter doctor -v
bash scripts/check.sh
flutter build apk --debug
(cd android && ./gradlew testDebugUnitTest)
```

按 README 安装 JDK 17 / Android SDK 36 / NDK 27.0.12077973。Debug 构建不需要正式签名；所有设备身份和小智 Token 由应用首次激活流程在本机建立。正式 APK 签名和已有平板上的配置不随 GitHub 仓库传递。

## 项目负责人需要私下移交

- 原 `digital-nurse-release.jks` 和对应密码/alias；在接手电脑上使用 `android/key.properties.example` 填写真实配置。
- 小智平台对应账号的访问安排、智能体/知识库归属，以及测试平板当前设备绑定情况；不通过提交 Token 交接。
- 当前实际使用的平板、已安装 APK 版本、需保留的科室宣教和使用记录备份。
- 医院/科室标识、护士形象及三语语音模型的授权资料。

请勿先卸载现有正式版来尝试调试包；调试签名无法覆盖正式签名。升级验证使用相同应用 ID 和原签名，并在测试设备上完成数据兼容验收。

## 不应破坏的兼容约定

- `com.digitalnurse.app`、原签名、数据库 `digital_nurse.db` 版本升级链、现有配置键及通道名称。
- 启动时先读本地配置/完成旧宣教迁移，再开放首页交互。
- 普通话/粤语/英语分别完整审核发布；自动生成译文始终为待复核草稿，缺失译文不自动回退。
- 本地宣教与在线语音切换必须停止/恢复音频占用，错误路径也需要恢复。
- 匿名事件不增加患者姓名、住院号、床号或诊断等身份字段。
- 不把上游历史文档或设计计划当成已实现能力；实际未完成的录音质量门禁见审查报告。

## 后续开发优先顺序

1. 在目标 Android 平板完成审查报告列出的实机验收，记录设备、版本与结果。
2. 独立推进录音质量结果接入和音频生命周期验证。
3. 评估缓存配额及大文件/Excel 后台化，再按需求继续扩展。

新功能从 main 新建分支；提交前运行统一检查。不要把签名、Token、构建缓存、安装包或含签名备份提交到 Git。
