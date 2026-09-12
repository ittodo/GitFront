import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/app_state.dart';
import 'package:gitfront_preview/main.dart';
import 'package:gitfront_preview/settings_store.dart';
import 'package:gitfront_preview/src/rust/api/models.dart';

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

class _FakeController extends GitFrontController {
  _FakeController(
    this.initialState, {
    this.cherryPickApplicability = CherryPickApplicability.applicable,
  });

  final GitFrontState initialState;
  final CherryPickApplicability cherryPickApplicability;

  @override
  GitFrontState build() {
    super.build();
    return initialState;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> selectCommit(CommitSummary commit) async {
    focusCommit(commit);
  }

  @override
  Future<CherryPickApplicability> assessCherryPick(
    CommitSummary commit, {
    int? mainlineParent,
  }) async => cherryPickApplicability;
}

const _oid = '1111111111111111111111111111111111111111';
const _headOid = '2222222222222222222222222222222222222222';

GitFrontState _historyState() {
  final snapshot = RepositorySnapshot(
    repositoryPath: r'D:\repos\demo',
    workdir: r'D:\repos\demo',
    name: 'demo',
    headName: 'main',
    headOid: _headOid,
    ahead: 0,
    behind: 0,
    state: RepositoryState.clean,
    generation: BigInt.one,
    files: const [],
    branches: const [],
    remotes: const [],
    stashes: const [],
  );
  final commit = CommitSummary(
    oid: _oid,
    shortOid: _oid.substring(0, 8),
    summary: 'feat: typed commit references',
    authorName: 'GitFront Test',
    authorEmail: 'gitfront@example.invalid',
    authoredAt: 1700000000,
    parentOids: const [],
    references: const [
      CommitReference(
        name: 'HEAD',
        fullName: 'HEAD',
        kind: CommitReferenceKind.head,
      ),
      CommitReference(
        name: 'main',
        fullName: 'refs/heads/main',
        kind: CommitReferenceKind.localBranch,
      ),
      CommitReference(
        name: 'origin/main',
        fullName: 'refs/remotes/origin/main',
        kind: CommitReferenceKind.remoteBranch,
      ),
      CommitReference(
        name: 'v1.0.0',
        fullName: 'refs/tags/v1.0.0',
        kind: CommitReferenceKind.tag,
      ),
    ],
    lane: GraphLane(column: 0, parentColumns: Uint32List(0)),
  );
  return GitFrontState(
    tabs: [
      RepoTabState(
        snapshot: snapshot,
        commits: [commit],
        mode: WorkspaceMode.history,
      ),
    ],
    activeIndex: 0,
    language: AppLanguage.english,
    initializing: false,
  );
}

GitFrontState _largeRepositoryState() {
  const itemCount = 5000;
  final files = List.generate(
    itemCount,
    (index) => FileChange(
      path: 'src/file_$index.txt',
      staged: ChangeKind.none,
      unstaged: ChangeKind.modified,
      conflicted: false,
      untracked: false,
    ),
    growable: false,
  );
  final branches = List.generate(
    itemCount,
    (index) => BranchInfo(
      name: 'branch/$index',
      fullName: 'refs/heads/branch/$index',
      isHead: index == 0,
      isRemote: false,
      ahead: 0,
      behind: 0,
    ),
    growable: false,
  );
  final commits = List.generate(itemCount, (index) {
    final oid = index.toRadixString(16).padLeft(40, '0');
    return CommitSummary(
      oid: oid,
      shortOid: oid.substring(0, 8),
      summary: 'commit $index',
      authorName: 'GitFront Test',
      authorEmail: 'gitfront@example.invalid',
      authoredAt: 1700000000 - index,
      parentOids: const [],
      references: const [],
      lane: GraphLane(column: 0, parentColumns: Uint32List(0)),
    );
  }, growable: false);
  final snapshot = RepositorySnapshot(
    repositoryPath: r'D:\repos\large',
    workdir: r'D:\repos\large',
    name: 'large',
    headName: 'branch/0',
    headOid: _headOid,
    ahead: 0,
    behind: 0,
    state: RepositoryState.clean,
    generation: BigInt.one,
    files: files,
    branches: branches,
    remotes: const [],
    stashes: const [],
  );
  return GitFrontState(
    tabs: [
      RepoTabState(
        snapshot: snapshot,
        commits: commits,
        mode: WorkspaceMode.history,
      ),
    ],
    activeIndex: 0,
    language: AppLanguage.english,
    initializing: false,
  );
}

GitFrontState _repositoryTabsState() {
  RepositorySnapshot repository(String name) => RepositorySnapshot(
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

  return GitFrontState(
    tabs: [
      RepoTabState(snapshot: repository('first')),
      RepoTabState(snapshot: repository('second')),
      RepoTabState(snapshot: repository('third')),
    ],
    activeIndex: 1,
    language: AppLanguage.english,
    initializing: false,
  );
}

void main() {
  testWidgets('shows the empty repository workspace', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GitFront Preview'), findsOneWidget);
    expect(find.textContaining('repository'), findsWidgets);
  });

  testWidgets('opens repository creation and practical clone options', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
          gitFrontProvider.overrideWith(
            () => _FakeController(
              const GitFrontState(
                language: AppLanguage.english,
                initializing: false,
              ),
            ),
          ),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New repository'));
    await tester.pumpAndSettle();
    expect(find.text('Initial branch'), findsOneWidget);
    expect(find.text('.gitignore template'), findsOneWidget);
    expect(find.text('origin URL (optional)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clone repository'));
    await tester.pumpAndSettle();
    expect(find.text('Advanced options'), findsOneWidget);
    await tester.tap(find.text('Advanced options'));
    await tester.pumpAndSettle();
    expect(find.text('Remote name'), findsOneWidget);
    expect(find.text('Download file contents on demand'), findsOneWidget);
  });

  testWidgets('reorders repository tabs by dragging and keeps selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemorySettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          gitFrontProvider.overrideWith(
            () => _FakeController(_repositoryTabsState()),
          ),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    final first = find.text('first');
    final third = find.text('third');
    final gesture = await tester.startGesture(tester.getCenter(first));
    await gesture.moveTo(tester.getCenter(third));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GitFrontApp)),
    );
    final state = container.read(gitFrontProvider);
    expect(state.tabs.first.snapshot.name, isNot('first'));
    expect(state.activeTab?.snapshot.name, 'second');
    expect(
      store.settings.openRepositories,
      state.tabs.map((tab) => tab.snapshot.workdir).toList(),
    );
  });

  testWidgets('shows typed refs and opens commit actions on right click', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _historyState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
          gitFrontProvider.overrideWith(() => _FakeController(state)),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HEAD'), findsOneWidget);
    expect(find.text('main'), findsWidgets);
    expect(find.text('origin/main'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(
      find.byTooltip(
        'HEAD: HEAD\nLocal branch: main\nRemote branch: origin/main\nTag: v1.0.0',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.text('feat: typed commit references'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Copy full commit hash'), findsOneWidget);
    expect(find.text('Compare with HEAD'), findsOneWidget);
    expect(find.text('Create branch here…'), findsOneWidget);
    expect(find.text('Revert…'), findsOneWidget);
    expect(find.text('Reset current branch here'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('feat: typed commit references'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Copy full commit hash'), findsOneWidget);
  });

  testWidgets('disables cherry-pick when the simulated result has no changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
          gitFrontProvider.overrideWith(
            () => _FakeController(
              _historyState(),
              cherryPickApplicability: CherryPickApplicability.alreadyApplied,
            ),
          ),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('feat: typed commit references'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    final item = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, 'Cherry-pick · Already applied'),
    );
    expect(item.onPressed, isNull);
  });

  testWidgets('keeps very large repository lists virtualized', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _largeRepositoryState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
          gitFrontProvider.overrideWith(() => _FakeController(state)),
        ],
        child: const GitFrontApp(),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('virtualized-repository-sidebar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('virtualized-commit-list')),
      findsOneWidget,
    );
    expect(find.text('branch/4999'), findsNothing);
    expect(find.text('commit 4999'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));

    await tester.tap(find.text('Changes (5000)'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('virtualized-change-list')),
      findsOneWidget,
    );
    expect(find.text('src/file_4999.txt'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
  });
}
