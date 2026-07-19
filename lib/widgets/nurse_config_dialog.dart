import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/education/data/education_repository.dart';
import '../features/education/data/education_rollback_snapshot.dart';
import '../features/education/data/legacy_education_migrator.dart';
import '../features/education/data/native_education_repository.dart';
import '../features/education/models/education_item.dart';
import '../features/education/widgets/education_management_dialog.dart';
import '../models/nurse_app_config.dart';
import '../services/department_logo_service.dart';
import '../services/nurse_avatar_image_service.dart';
import '../theme/nurse_theme.dart';
import 'usage_records_dialog.dart';

class NurseConfigDialog extends StatefulWidget {
  const NurseConfigDialog({
    super.key,
    required this.initial,
    this.onResetBinding,
    this.logoService = const DepartmentLogoService(),
    this.avatarImageService = const NurseAvatarImageService(),
    this.educationRepository,
  });

  final NurseAppConfig initial;
  final Future<void> Function()? onResetBinding;
  final DepartmentLogoService logoService;
  final NurseAvatarImageService avatarImageService;
  final EducationRepository? educationRepository;

  @override
  State<NurseConfigDialog> createState() => _NurseConfigDialogState();
}

class _NurseConfigDialogState extends State<NurseConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hospital;
  late final TextEditingController _ward;
  late final TextEditingController _server;
  late final TextEditingController _device;
  late final TextEditingController _token;
  late final TextEditingController _callText;
  late final TextEditingController _password;
  late final EducationRepository _educationRepository;
  late List<LocalQuickAnswer> _quickAnswersSnapshot;
  late int _managedItemCount;
  late bool _official;
  late NurseVisualStyle _visualStyle;
  late String _departmentLogoPath;
  late String _nurseAvatarPath;
  bool _hideToken = true;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    final config = widget.initial;
    _hospital = TextEditingController(text: config.hospitalName);
    _ward = TextEditingController(text: config.wardName);
    _server = TextEditingController(text: config.websocketUrl);
    _device = TextEditingController(text: config.deviceId);
    _token = TextEditingController(text: config.token);
    _callText = TextEditingController(text: config.callNurseText);
    _password = TextEditingController(text: config.settingsPassword);
    _educationRepository =
        widget.educationRepository ?? NativeEducationRepository();
    _quickAnswersSnapshot = List.of(config.quickAnswers);
    _managedItemCount = config.quickAnswers.length;
    _official = config.officialPlatform;
    _visualStyle = config.visualStyle;
    _departmentLogoPath = config.departmentLogoPath;
    _nurseAvatarPath = config.nurseAvatarPath;
  }

  @override
  void dispose() {
    _hospital.dispose();
    _ward.dispose();
    _server.dispose();
    _device.dispose();
    _token.dispose();
    _callText.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseTheme = Theme.of(context);
    final inputTheme = baseTheme.inputDecorationTheme;
    final safeLabelTheme = inputTheme.copyWith(
      labelStyle: (inputTheme.labelStyle ?? const TextStyle()).copyWith(
        height: 1.35,
      ),
      floatingLabelStyle: (inputTheme.floatingLabelStyle ?? const TextStyle())
          .copyWith(height: 1.35),
    );
    return Theme(
      data: baseTheme.copyWith(inputDecorationTheme: safeLabelTheme),
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 10),
            Text(widget.initial.departmentConfigured ? '数字护士设置' : '首次使用配置'),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: _field(_hospital, '医院名称')),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_ward, '科室/病区名称')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _departmentLogoEditor(colors),
                  const SizedBox(height: 12),
                  _nurseAvatarEditor(colors),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '显示风格',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        NurseVisualStyle.values.map((style) {
                          final palette = NursePalette.forStyle(style);
                          return ChoiceChip(
                            selected: _visualStyle == style,
                            onSelected:
                                (_) => setState(() => _visualStyle = style),
                            avatar: CircleAvatar(
                              backgroundColor: palette.primary,
                            ),
                            label: Text(
                              style == NurseVisualStyle.techBlue
                                  ? '${style.label}（推荐）'
                                  : style.label,
                            ),
                          );
                        }).toList(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _visualStyle.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: colors.primary.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: colors.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                      value: _official,
                      onChanged: (value) => setState(() => _official = value),
                      title: const Text(
                        '使用小智 AI 官方平台',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _official
                            ? '推荐：APP 自动获取服务器配置和 Token'
                            : '高级选项：连接您自己部署的小智服务器',
                      ),
                    ),
                  ),
                  if (_official) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '保存后会自动生成激活码。您无需查找 WebSocket 或 Token，只需登录 xiaozhi.me 添加设备。',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                widget.initial.token.isNotEmpty
                                    ? Icons.verified_outlined
                                    : Icons.phonelink_lock_outlined,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.initial.token.isNotEmpty
                                    ? '当前设备已取得小智绑定凭据'
                                    : '当前设备等待小智账号绑定',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText('设备ID：${widget.initial.deviceId}'),
                          const SizedBox(height: 3),
                          SelectableText('客户端ID：${widget.initial.clientId}'),
                          if (widget.initial.departmentConfigured &&
                              widget.onResetBinding != null) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _confirmResetBinding,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('更换小智账号／重新绑定'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    _field(
                      _server,
                      '小智 WebSocket 地址',
                      hint: 'wss://您的服务器/xiaozhi/v1/',
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!text.startsWith('ws://') &&
                            !text.startsWith('wss://')) {
                          return '地址应以 ws:// 或 wss:// 开头';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _field(_device, '设备 ID / MAC 地址'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _token,
                      obscureText: _hideToken,
                      decoration: InputDecoration(
                        labelText: '访问 Token',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed:
                              () => setState(() => _hideToken = !_hideToken),
                          icon: Icon(
                            _hideToken
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator:
                          (value) =>
                              (value?.trim().isEmpty ?? true)
                                  ? '请输入服务器 Token'
                                  : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _field(_callText, '转人工提示语', maxLines: 2),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '设置安全',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 12,
                    decoration: InputDecoration(
                      labelText: '设置密码',
                      helperText: '进入设置时需要输入，请设置4～12位数字',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed:
                            () =>
                                setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (!RegExp(r'^\d{4,12}$').hasMatch(text)) {
                        return '请输入4～12位数字密码';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: const Text(
                        '使用记录',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('按日期查询APP使用次数和明细，并选择时间范围导出Excel'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openUsageRecords,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.local_library_outlined),
                      title: const Text(
                        '管理本科室宣教内容',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '当前约$_managedItemCount项。可新增、编辑、复制、排序、停用或删除；普通话、粤语和英语分别复核发布。',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openEducationManagement,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '连接凭据只保存在本机；Token 使用 Android 加密存储。',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_official ? '保存并获取激活码' : '保存并连接'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => (value?.trim().isEmpty ?? true) ? '此项不能为空' : null,
    );
  }

  Widget _departmentLogoEditor(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 86,
            height: 86,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: _departmentLogoPreview(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '科室Logo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _departmentLogoPath.isEmpty
                      ? '当前使用急诊病房默认Logo'
                      : '已选择本科室自定义Logo',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickDepartmentLogo,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('选择图片'),
                    ),
                    if (_departmentLogoPath.isNotEmpty)
                      TextButton.icon(
                        onPressed:
                            () => setState(() => _departmentLogoPath = ''),
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _departmentLogoPreview() {
    final fallback = Image.asset(
      'assets/images/emergency_ward_logo_v2.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (_departmentLogoPath.isEmpty) return fallback;
    return Image.file(
      File(_departmentLogoPath),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Future<void> _pickDepartmentLogo() async {
    try {
      final path = await widget.logoService.pickLogo();
      if (path == null || path.isEmpty || !mounted) return;
      setState(() => _departmentLogoPath = path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法读取科室Logo：${error.message ?? error.code}')),
      );
    }
  }

  Widget _nurseAvatarEditor(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 105,
            height: 140,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: _nurseAvatarPreview(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数字护士形象',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _nurseAvatarPath.isEmpty
                      ? '当前使用APP默认数字护士形象'
                      : '已选择本科室自定义数字护士形象',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '图片标准：竖版3:4，最低1080×1440像素；人物正面居中、建议半身照、头顶留白、浅色简洁背景。APP会校验并统一裁切为1080×1440。',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickNurseAvatar,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('选择标准形象'),
                    ),
                    if (_nurseAvatarPath.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _nurseAvatarPath = ''),
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认形象'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nurseAvatarPreview() {
    final fallback = Image.asset(
      'assets/images/digital_nurse_v2.png',
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
    );
    if (_nurseAvatarPath.isEmpty) return fallback;
    return Image.file(
      File(_nurseAvatarPath),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Future<void> _pickNurseAvatar() async {
    try {
      final path = await widget.avatarImageService.pickStandardAvatar();
      if (path == null || path.isEmpty || !mounted) return;
      setState(() => _nurseAvatarPath = path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('形象图片不符合要求：${error.message ?? error.code}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _confirmResetBinding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: const Icon(Icons.link_off_outlined),
            title: const Text('确认更换小智账号？'),
            content: const Text(
              '本机将清除现有小智连接凭据，生成新的设备身份和激活码。之后请使用新科室的小智账号重新添加设备；原账号里的旧设备需要在小智控制台自行删除。如刚修改科室资料，请先取消并保存设置。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认重新绑定'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onResetBinding?.call();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openEducationManagement() async {
    try {
      await LegacyEducationMigrator(
        repository: _educationRepository,
      ).migrateIfNeeded(widget.initial);
      if (!mounted) return;
      final items = await showDialog<List<EducationItem>>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => EducationManagementDialog(repository: _educationRepository),
      );
      if (items == null || !mounted) return;
      final snapshot = buildEducationRollbackSnapshot(items);
      setState(() {
        _managedItemCount = items.where((item) => item.enabled).length;
        if (snapshot.isNotEmpty) _quickAnswersSnapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开宣教管理：$error')));
    }
  }

  Future<void> _openUsageRecords() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UsageRecordsDialog(config: widget.initial),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      NurseAppConfig(
        hospitalName: _hospital.text.trim(),
        wardName: _ward.text.trim(),
        departmentLogoPath: _departmentLogoPath,
        nurseAvatarPath: _nurseAvatarPath,
        departmentConfigured: true,
        officialPlatform: _official,
        otaUrl:
            _official ? NurseAppConfig.officialOtaUrl : widget.initial.otaUrl,
        websocketUrl: _server.text.trim(),
        deviceId: _device.text.trim(),
        clientId: widget.initial.clientId,
        token: _token.text.trim(),
        protocolVersion: widget.initial.protocolVersion,
        visualStyle: _visualStyle,
        callNurseText: _callText.text.trim(),
        quickAnswers: _quickAnswersSnapshot,
        offlineSpeechLanguage: widget.initial.offlineSpeechLanguage,
        settingsPassword: _password.text.trim(),
      ),
    );
  }
}
