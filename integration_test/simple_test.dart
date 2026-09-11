import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/main.dart';
import 'package:gitfront_preview/src/rust/api/git.dart';
import 'package:gitfront_preview/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);

  testWidgets('starts the app and reaches the Rust Git core', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: GitFrontApp()));
    await tester.pumpAndSettle();

    expect(await gitVersion(), startsWith('git version'));
    expect(find.text('GitFront Preview'), findsOneWidget);
  });
}
