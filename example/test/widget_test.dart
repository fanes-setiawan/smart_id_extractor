import 'package:flutter_test/flutter_test.dart';
import 'package:smart_id_extractor_example/main.dart';

void main() {
  testWidgets('Verify Document Extractor UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Document Extractor'), findsOneWidget);
    expect(find.text('KTP'), findsOneWidget);
    expect(find.text('KK'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
  });
}
