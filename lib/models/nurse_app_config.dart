import '../theme/nurse_theme.dart';
import 'offline_speech_language.dart';

class LocalQuickAnswer {
  const LocalQuickAnswer({
    required this.title,
    required this.answer,
    required this.cantoneseTitle,
    required this.cantoneseAnswer,
    required this.englishTitle,
    required this.englishAnswer,
  });

  final String title;
  final String answer;
  final String cantoneseTitle;
  final String cantoneseAnswer;
  final String englishTitle;
  final String englishAnswer;

  String titleFor(OfflineSpeechLanguage language) => switch (language) {
    OfflineSpeechLanguage.mandarin => title,
    OfflineSpeechLanguage.cantonese => cantoneseTitle,
    OfflineSpeechLanguage.english => englishTitle,
  };

  String answerFor(OfflineSpeechLanguage language) => switch (language) {
    OfflineSpeechLanguage.mandarin => answer,
    OfflineSpeechLanguage.cantonese => cantoneseAnswer,
    OfflineSpeechLanguage.english => englishAnswer,
  };

  factory LocalQuickAnswer.fromJson(
    Map<String, dynamic> json, {
    required LocalQuickAnswer fallback,
  }) => LocalQuickAnswer(
    title: json['title'] as String? ?? fallback.title,
    answer: json['answer'] as String? ?? fallback.answer,
    cantoneseTitle:
        json['cantoneseTitle'] as String? ?? fallback.cantoneseTitle,
    cantoneseAnswer:
        json['cantoneseAnswer'] as String? ?? fallback.cantoneseAnswer,
    englishTitle: json['englishTitle'] as String? ?? fallback.englishTitle,
    englishAnswer: json['englishAnswer'] as String? ?? fallback.englishAnswer,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'answer': answer,
    'cantoneseTitle': cantoneseTitle,
    'cantoneseAnswer': cantoneseAnswer,
    'englishTitle': englishTitle,
    'englishAnswer': englishAnswer,
  };
}

class NurseAppConfig {
  const NurseAppConfig({
    required this.hospitalName,
    required this.wardName,
    required this.departmentLogoPath,
    required this.nurseAvatarPath,
    required this.departmentConfigured,
    required this.officialPlatform,
    required this.otaUrl,
    required this.websocketUrl,
    required this.deviceId,
    required this.clientId,
    required this.token,
    required this.protocolVersion,
    required this.visualStyle,
    required this.callNurseText,
    required this.startupSubtitle,
    required this.quickAnswers,
    required this.offlineSpeechLanguage,
    required this.settingsPassword,
  });

  static const officialOtaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const defaultHospitalName = '广州中医药大学第三附属医院';
  static const defaultWardName = '急诊病房';

  final String hospitalName;
  final String wardName;
  final String departmentLogoPath;
  final String nurseAvatarPath;
  final bool departmentConfigured;
  final bool officialPlatform;
  final String otaUrl;
  final String websocketUrl;
  final String deviceId;
  final String clientId;
  final String token;
  final int protocolVersion;
  final NurseVisualStyle visualStyle;
  final String callNurseText;
  final String startupSubtitle;
  final List<LocalQuickAnswer> quickAnswers;
  final OfflineSpeechLanguage offlineSpeechLanguage;
  final String settingsPassword;

  static const defaultSettingsPassword = '123456';
  static String defaultStartupSubtitle(String hospitalName, String wardName) =>
      '您好，我是$hospitalName$wardName数字护士。您可以向我询问入院、检查和出院注意事项。';
  static const defaultQuickAnswers = <LocalQuickAnswer>[
    LocalQuickAnswer(
      title: '入院注意事项',
      answer:
          '办理入院后，请妥善保管个人物品，配合护士完成身份核对、入院评估和相关检查。请勿自行离开病区，如有不适或特殊需求，请及时告知责任护士。',
      cantoneseTitle: '入院须知',
      cantoneseAnswer:
          '办理入院之后，请妥善保管个人物品，并配合护士核对身份、完成入院评估同相关检查。请唔好自行离开病区；如果有任何唔舒服或者特别需要，请即时通知责任护士。',
      englishTitle: 'Admission Information',
      englishAnswer:
          'After admission, please keep your personal belongings safe and cooperate with the nurse for identity verification, admission assessment, and required examinations. Do not leave the ward without informing staff. If you feel unwell or need assistance, please tell your nurse promptly.',
    ),
    LocalQuickAnswer(
      title: '检查前准备',
      answer:
          '不同检查的准备要求不同。请按医护人员的通知进行禁食、禁饮或用药调整，不要自行停药。检查前请确认姓名和检查项目，如有疑问请联系责任护士。',
      cantoneseTitle: '检查前准备',
      cantoneseAnswer:
          '唔同检查有唔同嘅准备要求。请按照医护人员通知禁食、禁饮或者调整用药，唔好自行停药。检查前请核对姓名同检查项目，如有疑问请联络责任护士。',
      englishTitle: 'Before an Examination',
      englishAnswer:
          'Preparation requirements vary by examination. Follow the instructions from your healthcare team regarding fasting, fluids, and medication adjustments. Do not stop any medication on your own. Before the examination, confirm your name and the examination requested. Contact your nurse if anything is unclear.',
    ),
    LocalQuickAnswer(
      title: '住院安全事项',
      answer:
          '住院期间请穿防滑鞋，下床前先坐起观察，有头晕、乏力或行动不便时请勿独自下床。请勿擅自调节输液速度或移动医疗管路，需要帮助时请使用呼叫铃。',
      cantoneseTitle: '住院安全事项',
      cantoneseAnswer:
          '住院期间请穿防滑鞋，落床前先坐起身观察；如果有头晕、乏力或者行动不便，请唔好自己落床。唔好擅自调校输液速度或者移动医疗喉管，需要帮手时请按呼叫钟。',
      englishTitle: 'Safety During Your Stay',
      englishAnswer:
          'Wear non-slip footwear during your stay. Sit up and pause before standing. If you feel dizzy or weak, or have difficulty moving, do not get out of bed alone. Do not adjust an infusion or move any medical tubing. Use the call bell whenever you need help.',
    ),
    LocalQuickAnswer(
      title: '怎么办理出院？',
      answer:
          '医生开具出院医嘱后，请按病区通知办理费用结算和出院手续，领取出院资料及药物。离院前请核对出院用药、复诊时间和注意事项，确认随身物品齐全，并告知责任护士。',
      cantoneseTitle: '点样办理出院？',
      cantoneseAnswer:
          '医生开出院医嘱之后，请按照病区通知办理费用结算同出院手续，并领取出院资料同药物。离院前请核对出院用药、复诊时间同注意事项，确认随身物品齐全，并通知责任护士。',
      englishTitle: 'How Do I Leave Hospital?',
      englishAnswer:
          "After your doctor issues the discharge order, follow the ward's instructions to settle the bill and complete the discharge process. Collect your discharge documents and medicines. Before leaving, check your medicines, follow-up date, instructions, and personal belongings, and inform your nurse.",
    ),
    LocalQuickAnswer(
      title: '用药注意事项',
      answer: '请按医嘱用药，不要自行增减药量、停药或服用自带药物。如有药物过敏史、服药后不适或对药物用法存在疑问，请立即告知医护人员。',
      cantoneseTitle: '用药注意事项',
      cantoneseAnswer:
          '请按照医嘱用药，唔好自行加减药量、停药或者服用自备药物。如果有药物敏感史、食药后唔舒服，或者对用药方法有疑问，请立即通知医护人员。',
      englishTitle: 'Medication Safety',
      englishAnswer:
          'Take medicines exactly as prescribed. Do not change the dose, stop treatment, or take medicines brought from home without approval. Tell your healthcare team immediately about any drug allergy, discomfort after taking medicine, or questions about how to use it.',
    ),
    LocalQuickAnswer(
      title: '饮食注意事项',
      answer:
          '请按医生和护士告知的饮食要求进食。如处于禁食禁饮期间，请勿自行吃喝。如有糖尿病、吞咽困难、食物过敏或其他特殊饮食需求，请提前告知责任护士。',
      cantoneseTitle: '饮食注意事项',
      cantoneseAnswer:
          '请按照医生同护士讲解嘅饮食要求进食。如果正处于禁食禁饮期间，请唔好自行饮食。如果有糖尿病、吞咽困难、食物敏感或者其他特别饮食需要，请预先通知责任护士。',
      englishTitle: 'Dietary Instructions',
      englishAnswer:
          'Follow the dietary instructions provided by your doctor and nurse. Do not eat or drink while you are required to fast. Tell your nurse in advance if you have diabetes, difficulty swallowing, a food allergy, or any other special dietary need.',
    ),
    LocalQuickAnswer(
      title: '陪护与探视',
      answer: '请遵守医院和病区的陪护、探视及感染防控规定。陪护人员请保持病房安静和环境整洁，不要擅自移动设备或协助患者进行不安全的活动。',
      cantoneseTitle: '陪护同探访',
      cantoneseAnswer:
          '请遵守医院同病区嘅陪护、探访同感染控制规定。陪护人员请保持病房安静同环境整洁，唔好擅自移动设备，亦唔好协助病人进行唔安全嘅活动。',
      englishTitle: 'Visitors and Caregivers',
      englishAnswer:
          'Follow the hospital and ward rules for caregivers, visitors, and infection prevention. Caregivers should keep the room quiet and tidy, and must not move medical equipment or help the patient perform unsafe activities.',
    ),
    LocalQuickAnswer(
      title: '需要帮助怎么办？',
      answer:
          '如果您出现胸痛、呼吸困难、意识不清、突发剧烈不适或其他紧急情况，请立即按床头呼叫铃联系护士。其他事项也可通过呼叫铃或护士站联系责任护士。',
      cantoneseTitle: '需要帮手点算？',
      cantoneseAnswer:
          '如果出现胸痛、呼吸困难、神志不清、突然剧烈唔舒服或者其他紧急情况，请立即按床头呼叫钟联络护士。其他事情亦可以通过呼叫钟或者护士站联络责任护士。',
      englishTitle: 'How Can I Get Help?',
      englishAnswer:
          "If you develop chest pain, difficulty breathing, reduced consciousness, sudden severe discomfort, or any other emergency, press the bedside call bell immediately. For other needs, use the call bell or contact the nurses' station.",
    ),
  ];

  bool get canConnect =>
      websocketUrl.trim().isNotEmpty &&
      deviceId.trim().isNotEmpty &&
      clientId.trim().isNotEmpty &&
      token.trim().isNotEmpty;

  factory NurseAppConfig.defaults(String deviceId, String clientId) =>
      NurseAppConfig(
        hospitalName: defaultHospitalName,
        wardName: defaultWardName,
        departmentLogoPath: '',
        nurseAvatarPath: '',
        departmentConfigured: false,
        officialPlatform: true,
        otaUrl: officialOtaUrl,
        websocketUrl: '',
        deviceId: deviceId,
        clientId: clientId,
        token: '',
        protocolVersion: 1,
        visualStyle: NurseVisualStyle.techBlue,
        callNurseText: '如有紧急情况，请立即按床头呼叫铃联系责任护士。',
        startupSubtitle: defaultStartupSubtitle(
          defaultHospitalName,
          defaultWardName,
        ),
        quickAnswers: defaultQuickAnswers,
        offlineSpeechLanguage: OfflineSpeechLanguage.mandarin,
        settingsPassword: defaultSettingsPassword,
      );

  factory NurseAppConfig.fromJson(Map<String, dynamic> json) {
    final hospitalName = json['hospitalName'] as String? ?? defaultHospitalName;
    final wardName = json['wardName'] as String? ?? defaultWardName;
    return NurseAppConfig(
      hospitalName: hospitalName,
      wardName: wardName,
      departmentLogoPath: json['departmentLogoPath'] as String? ?? '',
      nurseAvatarPath: json['nurseAvatarPath'] as String? ?? '',
      // 旧版本没有该字段，视为已经完成科室配置，避免升级后打断现有设备。
      departmentConfigured: json['departmentConfigured'] as bool? ?? true,
      // 旧版本没有此字段。官方平台用户默认迁移到自动激活模式。
      officialPlatform: json['officialPlatform'] as bool? ?? true,
      otaUrl: json['otaUrl'] as String? ?? officialOtaUrl,
      websocketUrl: json['websocketUrl'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      token: json['token'] as String? ?? '',
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      visualStyle: NurseVisualStyle.fromStored(json['visualStyle']),
      callNurseText:
          json['callNurseText'] as String? ?? '如有紧急情况，请立即按床头呼叫铃联系责任护士。',
      startupSubtitle:
          (json['startupSubtitle'] as String?)?.trim().isNotEmpty == true
              ? (json['startupSubtitle'] as String).trim()
              : defaultStartupSubtitle(hospitalName, wardName),
      quickAnswers: _answersFromJson(json['quickAnswers']),
      offlineSpeechLanguage: OfflineSpeechLanguage.fromStored(
        json['offlineSpeechLanguage'],
      ),
      settingsPassword: defaultSettingsPassword,
    );
  }

  Map<String, dynamic> toJson() => {
    'hospitalName': hospitalName,
    'wardName': wardName,
    'departmentLogoPath': departmentLogoPath,
    'nurseAvatarPath': nurseAvatarPath,
    'departmentConfigured': departmentConfigured,
    'officialPlatform': officialPlatform,
    'otaUrl': otaUrl,
    'websocketUrl': websocketUrl,
    'deviceId': deviceId,
    'clientId': clientId,
    'token': token,
    'protocolVersion': protocolVersion,
    'visualStyle': visualStyle.name,
    'callNurseText': callNurseText,
    'startupSubtitle': startupSubtitle,
    'quickAnswers': quickAnswers.map((answer) => answer.toJson()).toList(),
    'offlineSpeechLanguage': offlineSpeechLanguage.storedValue,
  };

  NurseAppConfig copyWith({
    String? hospitalName,
    String? wardName,
    String? departmentLogoPath,
    String? nurseAvatarPath,
    bool? departmentConfigured,
    bool? officialPlatform,
    String? otaUrl,
    String? websocketUrl,
    String? deviceId,
    String? clientId,
    String? token,
    int? protocolVersion,
    NurseVisualStyle? visualStyle,
    String? callNurseText,
    String? startupSubtitle,
    List<LocalQuickAnswer>? quickAnswers,
    OfflineSpeechLanguage? offlineSpeechLanguage,
    String? settingsPassword,
  }) => NurseAppConfig(
    hospitalName: hospitalName ?? this.hospitalName,
    wardName: wardName ?? this.wardName,
    departmentLogoPath: departmentLogoPath ?? this.departmentLogoPath,
    nurseAvatarPath: nurseAvatarPath ?? this.nurseAvatarPath,
    departmentConfigured: departmentConfigured ?? this.departmentConfigured,
    officialPlatform: officialPlatform ?? this.officialPlatform,
    otaUrl: otaUrl ?? this.otaUrl,
    websocketUrl: websocketUrl ?? this.websocketUrl,
    deviceId: deviceId ?? this.deviceId,
    clientId: clientId ?? this.clientId,
    token: token ?? this.token,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    visualStyle: visualStyle ?? this.visualStyle,
    callNurseText: callNurseText ?? this.callNurseText,
    startupSubtitle: startupSubtitle ?? this.startupSubtitle,
    quickAnswers: quickAnswers ?? this.quickAnswers,
    offlineSpeechLanguage: offlineSpeechLanguage ?? this.offlineSpeechLanguage,
    settingsPassword: settingsPassword ?? this.settingsPassword,
  );

  static List<LocalQuickAnswer> _answersFromJson(dynamic raw) {
    if (raw is! List) return defaultQuickAnswers;
    final answers = <LocalQuickAnswer>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) continue;
      final normalized = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final fallback =
          index < defaultQuickAnswers.length
              ? defaultQuickAnswers[index]
              : LocalQuickAnswer(
                title: normalized['title']?.toString() ?? '新增宣教',
                answer: normalized['answer']?.toString() ?? '',
                cantoneseTitle: normalized['title']?.toString() ?? '新增宣教',
                cantoneseAnswer: normalized['answer']?.toString() ?? '',
                englishTitle: normalized['title']?.toString() ?? 'Education',
                englishAnswer: normalized['answer']?.toString() ?? '',
              );
      final answer = LocalQuickAnswer.fromJson(normalized, fallback: fallback);
      if (answer.title.isNotEmpty && answer.answer.isNotEmpty) {
        answers.add(answer);
      }
    }
    if (answers.isEmpty) return defaultQuickAnswers;
    return List.unmodifiable(answers);
  }
}
