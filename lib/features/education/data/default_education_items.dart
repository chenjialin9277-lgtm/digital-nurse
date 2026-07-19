import '../../../models/nurse_app_config.dart';
import '../../../models/offline_speech_language.dart';
import '../models/education_item.dart';
import '../models/education_language_content.dart';

List<EducationItem> buildDefaultEducationItems({DateTime? now}) {
  final timestamp = (now ?? DateTime.now()).toUtc();
  return List.generate(NurseAppConfig.defaultQuickAnswers.length, (index) {
    final answer = NurseAppConfig.defaultQuickAnswers[index];
    final questions = _defaultQuestions[index];
    return EducationItem(
      id: _defaultIds[index],
      category: _defaultCategories[index],
      contents: {
        for (final language in OfflineSpeechLanguage.values)
          language: _reviewedContent(
            answer: answer,
            language: language,
            question: questions[language]!,
          ),
      },
      estimatedManualMinutes: 3,
      sortOrder: index,
      favorite: index < 4,
      enabled: true,
      version: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  });
}

EducationLanguageContent _reviewedContent({
  required LocalQuickAnswer answer,
  required OfflineSpeechLanguage language,
  required _ReviewedQuestion question,
}) => EducationLanguageContent(
  title: answer.titleFor(language),
  body: answer.answerFor(language),
  summary: answer.titleFor(language),
  question: question.question,
  options: question.options,
  correctIndex: 0,
  explanation: question.explanation,
  published: true,
  needsReview: false,
);

const _defaultIds = [
  'admission',
  'examination',
  'inpatient_safety',
  'discharge',
  'medication',
  'diet',
  'visitors',
  'request_help',
];

const _defaultCategories = [
  '入院宣教',
  '检查宣教',
  '安全宣教',
  '出院宣教',
  '用药宣教',
  '饮食宣教',
  '陪护探视',
  '紧急求助',
];

class _ReviewedQuestion {
  const _ReviewedQuestion({
    required this.question,
    required this.options,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final String explanation;
}

const _defaultQuestions = <Map<OfflineSpeechLanguage, _ReviewedQuestion>>[
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '办理入院后，正确的做法是什么？',
      options: ['配合护士核对身份和评估', '不告知护士自行离开病区', '将贵重物品随意放置'],
      explanation: '应妥善保管物品，并配合护士完成身份核对和入院评估。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '办理入院之后，正确做法係乜野？',
      options: ['配合护士核对身份同评估', '唤通知护士自行离开病区', '随意摆放贵重物品'],
      explanation: '应该妥善保管物品，并配合护士完成身份核对同入院评估。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question: 'What should you do after admission?',
      options: [
        'Cooperate with identity checks and assessment',
        'Leave the ward without telling staff',
        'Leave valuables unattended',
      ],
      explanation:
          'Keep belongings safe and cooperate with identity checks and admission assessment.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '检查前对用药有疑问时应该怎么做？',
      options: ['联系医护人员确认', '自行停药', '按自己经验调整药量'],
      explanation: '检查前应按医护人员通知准备，不能自行停药或调药。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '检查前对用药有疑问应该点做？',
      options: ['联络医护人员确认', '自行停药', '照自己经验调整药量'],
      explanation: '应该按医护人员通知准备，唤好自行停药或者调药。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question:
          'What should you do if medication instructions before a test are unclear?',
      options: [
        'Confirm with the healthcare team',
        'Stop medication yourself',
        'Change the dose yourself',
      ],
      explanation:
          'Follow the healthcare team instructions and never stop or change medication yourself.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '感到头晕乏力时，下床前应怎么做？',
      options: ['使用呼叫铃请护士帮助', '立即独自下床', '自行调节输液速度'],
      explanation: '头晕、乏力或行动不便时不要独自下床，应呼叫护士协助。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '感到头晕乏力时，落床前应该点做？',
      options: ['按呼叫钟请护士帮手', '立即自己落床', '自行调校输液速度'],
      explanation: '头晕、乏力或行动唤方便时唤好独自落床，应该叫护士协助。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question:
          'What should you do if you feel dizzy or weak before getting out of bed?',
      options: [
        'Use the call bell for help',
        'Get up alone immediately',
        'Adjust the infusion yourself',
      ],
      explanation:
          'Do not get out of bed alone when dizzy or weak; use the call bell for help.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '离院前需要核对哪些内容？',
      options: ['出院用药、复诊时间和注意事项', '只需带走随身物品', '不需要告知护士'],
      explanation: '离院前应核对出院用药、复诊时间、注意事项和随身物品。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '离院前需要核对乜野内容？',
      options: ['出院用药、复诊时间同注意事项', '只需要带走随身物品', '唤需要通知护士'],
      explanation: '离院前应该核对出院用药、复诊时间、注意事项同随身物品。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question: 'What should be checked before leaving hospital?',
      options: [
        'Medicines, follow-up time, and instructions',
        'Only personal belongings',
        'Nothing needs checking',
      ],
      explanation:
          'Check discharge medicines, follow-up time, instructions, and personal belongings before leaving.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '正确的住院用药方式是什么？',
      options: ['严格按医嘱用药', '自行增减药量', '未告知医护人员服用自带药'],
      explanation: '用药应严格遵循医嘱，有疑问或不适应立即告知医护人员。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '正确住院用药方式係乜野？',
      options: ['严格按照医嘱用药', '自行加减药量', '未通知医护人员食自备药'],
      explanation: '用药应该严格按医嘱，有疑问或者唤舒服要立即通知医护人员。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question: 'What is the correct way to take medication in hospital?',
      options: [
        'Follow the prescription exactly',
        'Change the dose yourself',
        'Take home medication without telling staff',
      ],
      explanation:
          'Follow the prescription exactly and report allergies, discomfort, or questions immediately.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '处于禁食禁饮期间时应怎么做？',
      options: ['按要求暂停吃喝', '少量进食没有关系', '自行结束禁食'],
      explanation: '禁食禁饮期间不应自行吃喝，特殊饮食需求应提前告知护士。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '处于禁食禁饮期间应该点做？',
      options: ['按要求暂停饮食', '少量饮食都无问题', '自行结束禁食'],
      explanation: '禁食禁饮期间唤应该自行饮食，特别饮食需要应该预先通知护士。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question: 'What should you do while fasting is required?',
      options: [
        'Do not eat or drink as instructed',
        'A small meal is always acceptable',
        'End the fasting period yourself',
      ],
      explanation:
          'Do not eat or drink while fasting is required and tell your nurse about special dietary needs.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '陪护人员在病房内应怎么做？',
      options: ['遵守探视和感染防控规定', '擅自移动医疗设备', '协助患者做不安全的活动'],
      explanation: '陪护人员应遵守病区规定，保持安静整洁，不得擅自移动设备。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '陪护人员喺病房内应该点做？',
      options: ['遵守探访同感染控制规定', '擅自移动医疗设备', '帮病人做唤安全活动'],
      explanation: '陪护人员应该遵守病区规定，保持安静整洁，唤好擅自移动设备。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question: 'What should caregivers do in the ward?',
      options: [
        'Follow visiting and infection-control rules',
        'Move medical equipment themselves',
        'Help with unsafe activities',
      ],
      explanation:
          'Caregivers should follow ward rules, keep the room tidy, and never move medical equipment.',
    ),
  },
  {
    OfflineSpeechLanguage.mandarin: _ReviewedQuestion(
      question: '突发胸痛或呼吸困难时应该怎么做？',
      options: ['立即按呼叫铃联系护士', '等待症状自行缓解', '自行离开病区'],
      explanation: '出现胸痛、呼吸困难或其他紧急情况时，应立即使用呼叫铃联系护士。',
    ),
    OfflineSpeechLanguage.cantonese: _ReviewedQuestion(
      question: '突然胸痛或者呼吸困难时应该点做？',
      options: ['立即按呼叫钟联络护士', '等症状自己好转', '自行离开病区'],
      explanation: '出现胸痛、呼吸困难或者其他紧急情况时，应该立即按呼叫钟联络护士。',
    ),
    OfflineSpeechLanguage.english: _ReviewedQuestion(
      question:
          'What should you do if chest pain or breathing difficulty occurs?',
      options: [
        'Press the call bell immediately',
        'Wait without telling anyone',
        'Leave the ward yourself',
      ],
      explanation:
          'Use the call bell immediately for chest pain, breathing difficulty, or another emergency.',
    ),
  },
];
