import 'package:flutter/material.dart';

import '../models/education_language_content.dart';

class EducationFeedbackCard extends StatelessWidget {
  const EducationFeedbackCard({
    super.key,
    required this.title,
    required this.content,
    required this.isCorrect,
    required this.nurseHelpRequested,
    required this.onReplay,
    required this.onNurseHelp,
    required this.onFinish,
  });

  final String title;
  final EducationLanguageContent content;
  final bool isCorrect;
  final bool nurseHelpRequested;
  final VoidCallback onReplay;
  final VoidCallback onNurseHelp;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = nurseHelpRequested ? '请责任护士进一步解释' : title;
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              nurseHelpRequested
                  ? Icons.notifications_active_outlined
                  : isCorrect
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              effectiveTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Text(
              content.explanation,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, height: 1.55),
            ),
            if (!isCorrect && !nurseHelpRequested) ...[
              const SizedBox(height: 12),
              Text(
                '正确要点：${content.options[content.correctIndex]}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay),
                  label: const Text('重新听一遍'),
                ),
                if (!nurseHelpRequested)
                  OutlinedButton.icon(
                    onPressed: onNurseHelp,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('请护士进一步解释'),
                  ),
                FilledButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.done),
                  label: const Text('结束本次宣教'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
