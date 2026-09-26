import 'package:flutter_test/flutter_test.dart';
import 'package:reading_journal/main.dart';

void main() {
  testWidgets('READBLOOM smoke test', (tester) async {
    await tester.pumpWidget(const ReadingJournalApp());
    expect(find.byType(ReadingJournalApp), findsOneWidget);
  });
}
