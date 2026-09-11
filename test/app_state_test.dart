import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/app_state.dart';
import 'package:gitfront_preview/src/rust/api/models.dart';

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
}
