import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the empty repository workspace', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: GitFrontApp()));
    await tester.pumpAndSettle();

    expect(find.text('GitFront Preview'), findsOneWidget);
    expect(find.textContaining('repository'), findsWidgets);
  });
}
