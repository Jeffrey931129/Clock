import 'package:clock_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Clock screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ClockApp());
    expect(find.byType(DigitTile), findsNWidgets(2));
    expect(find.byType(BatteryBadge), findsOneWidget);
    expect(find.byType(PageDots), findsOneWidget);
  });

  testWidgets('Swiping left opens the settings page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ClockApp());
    await tester.fling(find.byType(ClockScreen), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Time zone'), findsOneWidget);
  });
}
