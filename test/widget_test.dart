import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/app_state.dart';
import 'package:gitfront_preview/main.dart';
import 'package:gitfront_preview/src/rust/api/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends GitFrontController {
  _FakeController(this.initialState);

  final GitFrontState initialState;

  @override
  GitFrontState build() => initialState;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> selectCommit(CommitSummary commit) async {
    focusCommit(commit);
  }
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

void main() {
  testWidgets('shows the empty repository workspace', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: GitFrontApp()));
    await tester.pumpAndSettle();

    expect(find.text('GitFront Preview'), findsOneWidget);
    expect(find.textContaining('repository'), findsWidgets);
  });

  testWidgets('shows typed refs and opens commit actions on right click', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = _historyState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

  testWidgets('keeps very large repository lists virtualized', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = _largeRepositoryState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
