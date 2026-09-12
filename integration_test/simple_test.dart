import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/app_state.dart';
import 'package:gitfront_preview/main.dart';
import 'package:gitfront_preview/settings_store.dart';
import 'package:gitfront_preview/src/rust/api/git.dart';
import 'package:gitfront_preview/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

class _MemorySettingsStore implements SettingsStore {
  AppSettings settings = const AppSettings();

  @override
  Future<String> get filePath async => 'memory://settings.json';

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);

  testWidgets('starts the app and reaches the Rust Git core', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(await gitVersion(), startsWith('git version'));
    expect(find.text('GitFront Preview'), findsOneWidget);
  });
}
