import 'package:flutter/material.dart';

import '../models/education_language_content.dart';

class ComprehensionCard extends StatelessWidget {
  const ComprehensionCard({
    super.key,
    required this.content,
    required this.onAnswer,
    required this.onReplay,
    required this.onNurseHelp,
  });

  final EducationLanguageContent content;
  final ValueChanged<int> onAnswer;
  final VoidCallback onReplay;
  final VoidCallback onNurseHelp;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.task_alt_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                const Text(
                  '请确认一下刚才的要点',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              content.question,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < content.options.length; index++) ...[
              OutlinedButton(
                onPressed: () => onAnswer(index),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                ),
                child: Text(
                  content.options[index],
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay),
                  label: const Text('重新听一遍'),
                ),
                TextButton.icon(
                  onPressed: onNurseHelp,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('请护士进一步解释'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
