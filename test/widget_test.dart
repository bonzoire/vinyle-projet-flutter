import 'package:flutter_test/flutter_test.dart';
import 'package:vinyle_flutter/main.dart';

void main() {
  testWidgets('VinylApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VinylApp());
    expect(find.text('Détecteur de Sillons Vinyle'), findsOneWidget);
  });
}
