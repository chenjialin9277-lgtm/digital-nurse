import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';

class DailyLanguageSelector extends StatelessWidget {
  const DailyLanguageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
  });

  final OfflineSpeechLanguage value;
  final ValueChanged<OfflineSpeechLanguage> onChanged;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '宣教语言',
      child: Wrap(
        spacing: compact ? 5 : 8,
        runSpacing: 5,
        children: [
          for (final language in OfflineSpeechLanguage.values)
            ChoiceChip(
              label: Text(language.label),
              selected: value == language,
              showCheckmark: false,
              onSelected:
                  enabled
                      ? (selected) {
                        if (selected && value != language) onChanged(language);
                      }
                      : null,
              labelStyle: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w700,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 11,
                vertical: compact ? 4 : 7,
              ),
              visualDensity: VisualDensity.standard,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
    );
  }
}
