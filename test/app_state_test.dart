import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitfront_preview/app_state.dart';
import 'package:gitfront_preview/settings_store.dart';
import 'package:gitfront_preview/src/rust/api/models.dart';

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore(this.settings);

  AppSettings settings;

  @override
  Future<String> get filePath async => 'memory://settings.json';

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}

RepositorySnapshot snapshot(String name) => RepositorySnapshot(
  repositoryPath: 'D:\\repos\\$name',
  workdir: 'D:\\repos\\$name',
  name: name,
  ahead: 0,
  behind: 0,
  state: RepositoryState.clean,
  generation: BigInt.one,
  files: const [],
  branches: const [],
  remotes: const [],
  stashes: const [],
);

void main() {
  test('repository tab state remains isolated', () {
    final first = RepoTabState(snapshot: snapshot('first'));
    final second = RepoTabState(snapshot: snapshot('second'));
    final state = GitFrontState(tabs: [first, second], activeIndex: 0);

    final changedFirst = state.tabs.first.copyWith(mode: WorkspaceMode.history);
    final updated = state.copyWith(tabs: [changedFirst, state.tabs.last]);

    expect(updated.tabs.first.mode, WorkspaceMode.history);
    expect(updated.tabs.last.mode, WorkspaceMode.changes);
    expect(updated.tabs.last.snapshot.name, 'second');
  });

  test('layout and external editor settings copy independently', () {
    const state = GitFrontState();
    final updated = state.copyWith(
      leftPanelWidth: 310,
      detailPanelWidth: 640,
      detailPanelVisible: false,
      externalEditor: ExternalEditor.gitMergeTool,
    );

    expect(updated.leftPanelWidth, 310);
    expect(updated.detailPanelWidth, 640);
    expect(updated.detailPanelVisible, isFalse);
    expect(updated.externalEditor, ExternalEditor.gitMergeTool);
    expect(state.detailPanelVisible, isTrue);
  });

  test('paged changes keep full counts without transferring every file', () {
    final file = FileChange(
      path: 'one.txt',
      staged: ChangeKind.modified,
      unstaged: ChangeKind.none,
      conflicted: false,
      untracked: false,
    );
    final tab = RepoTabState(
      snapshot: snapshot('paged'),
      changes: [file],
      nextChangeCursor: '7:1',
      totalChanges: 5000,
      stagedChangeCount: 2300,
    );

    expect(tab.visibleChanges, [file]);
    expect(tab.visibleChangeCount, 5000);
    expect(tab.visibleStagedChangeCount, 2300);
    expect(tab.nextChangeCursor, '7:1');
  });

  test('controller restores and persists injected settings', () async {
    final store = _MemorySettingsStore(
      AppSettings(
        language: 'korean',
        darkMode: true,
        recentRepositories: const [r'D:\repos\recent'],
        leftPanelWidth: 320,
        detailPanelWidth: 680,
        detailPanelVisible: false,
        externalEditor: 'custom',
        customEditorExecutable: r'C:\Tools\editor.exe',
        lastUpdateCheck: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(gitFrontProvider.notifier);

    await controller.initialize();

    final restored = container.read(gitFrontProvider);
    expect(restored.language, AppLanguage.korean);
    expect(restored.darkMode, isTrue);
    expect(restored.recentRepositories, [r'D:\repos\recent']);
    expect(restored.leftPanelWidth, 320);
    expect(restored.detailPanelWidth, 680);
    expect(restored.detailPanelVisible, isFalse);
    expect(restored.externalEditor, ExternalEditor.custom);
    expect(restored.customEditorExecutable, r'C:\Tools\editor.exe');

    await controller.setLanguage(AppLanguage.english);
    await controller.setDarkMode(null);
    await controller.setPanelWidths(leftWidth: 360, detailWidth: 720);
    await controller.setExternalEditor(
      ExternalEditor.systemDefault,
      customExecutable: '',
    );

    expect(store.settings.language, 'english');
    expect(store.settings.darkMode, isNull);
    expect(store.settings.leftPanelWidth, 360);
    expect(store.settings.detailPanelWidth, 720);
    expect(store.settings.externalEditor, 'systemDefault');
    expect(store.settings.customEditorExecutable, isEmpty);
  });

  test('an unavailable saved repository does not block app startup', () async {
    final store = _MemorySettingsStore(
      const AppSettings(openRepositories: [r'Z:\missing\repository']),
    );
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(gitFrontProvider.notifier).initialize();

    final state = container.read(gitFrontProvider);
    expect(state.initializing, isFalse);
    expect(
      state.operationLog.any((entry) => entry.contains('Could not restore')),
      isTrue,
    );
  });
}
