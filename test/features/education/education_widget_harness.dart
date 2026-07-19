import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget educationTestApp(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
  home: Scaffold(body: child),
);

Future<void> fillKnowledgeQuestion(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('education-question-mandarin')),
    '术后活动时应该怎么做？',
  );
  await tester.enterText(
    find.byKey(const Key('education-option-mandarin-0')),
    '在护士指导下活动',
  );
  await tester.enterText(
    find.byKey(const Key('education-option-mandarin-1')),
    '自行进行高强度活动',
  );
  await tester.enterText(
    find.byKey(const Key('education-explanation-mandarin')),
    '应在护士评估和指导下逐步活动。',
  );
}
