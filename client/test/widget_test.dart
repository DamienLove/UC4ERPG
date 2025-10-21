import 'package:flutter_test/flutter_test.dart';
import 'package:uc4erpg_client/main.dart';

void main() {
  testWidgets('renders UC4ERPG title', (tester) async {
    await tester.pumpWidget(const UC4ERPGApp());
    expect(find.text('UC4ERPG'), findsOneWidget);
  });
}