import 'package:flutter/widgets.dart';

import 'app_state.dart';

class GitFrontStrings {
  GitFrontStrings(this.locale);

  final Locale locale;

  bool get _ko => locale.languageCode == 'ko';

  String text(String korean, String english) => _ko ? korean : english;

  String get appName => 'GitFront Preview';
  String get openRepository => text('저장소 열기', 'Open repository');
  String get createRepository => text('새 저장소', 'New repository');
  String get cloneRepository => text('저장소 복제', 'Clone repository');
  String get noRepository =>
      text('저장소를 열어 시작하세요', 'Open a repository to get started');
  String get noRepositoryDescription => text(
    '로컬 Git 저장소를 열거나 원격 URL에서 복제할 수 있습니다.',
    'Open a local Git repository or clone one from a remote URL.',
  );
  String get changes => text('변경', 'Changes');
  String get history => text('로그', 'History');
  String get branches => text('브랜치', 'Branches');
  String get remotes => text('원격', 'Remotes');
  String get stashes => text('스태시', 'Stashes');
  String get submodules => text('서브모듈', 'Submodules');
  String get manageSubtrees => text('Subtree 관리', 'Manage subtrees');
  String get addSubmodule => text('서브모듈 추가', 'Add submodule');
  String get registerSubtree => text('Subtree 등록', 'Register subtree');
  String get registerExistingSubtree =>
      text('기존 Subtree 등록', 'Register existing subtree');
  String get forgetSubtree => text('Subtree 등록 해제', 'Forget subtree');
  String get subtreePush => text('Subtree Push', 'Subtree push');
  String get subtreeSplit => text('Subtree 분리', 'Subtree split');
  String get subtreePrefix => text('대상 폴더', 'Prefix');
  String get subtreeRef => text('브랜치 또는 Ref', 'Branch or ref');
  String get subtreeSquash => text('이력을 하나의 커밋으로 합치기', 'Squash history');
  String get subtreeSquashShort => text('이력 합침', 'squash');
  String get resultBranchOptional =>
      text('결과 브랜치 (선택)', 'Result branch (optional)');
  String get subtreeUnavailable => text(
    '내장 Subtree를 실행하는 데 필요한 Git for Windows 또는 Bash를 찾을 수 없습니다.',
    'Git for Windows or Bash required by the bundled subtree helper was not found.',
  );
  String get pullSubtree => text('변경 가져오기', 'Pull');
  String get pushSubtree => text('변경 보내기…', 'Push…');
  String get splitSubtree => text('이력 분리…', 'Split…');
  String get initialize => text('초기화', 'Initialize');
  String get updateRecorded =>
      text('기록된 커밋으로 업데이트', 'Update to recorded commits');
  String get updateRemote =>
      text('원격 최신 커밋으로 업데이트', 'Update from configured remotes');
  String get synchronize => text('URL 동기화', 'Synchronize URLs');
  String get openAsTab => text('새 탭으로 열기', 'Open as tab');
  String get removeSubmodule => text('서브모듈 제거', 'Remove submodule');
  String get submoduleUninitialized => text('초기화 안 됨', 'Uninitialized');
  String get submoduleClean => text('정상', 'Clean');
  String get submoduleDifferentCommit => text('다른 커밋', 'Different commit');
  String get submoduleModified => text('수정됨', 'Modified');
  String get submoduleUntracked => text('미추적 파일 있음', 'Untracked files');
  String get submoduleConflicted => text('충돌', 'Conflicted');
  String get submoduleMissing => text('폴더 없음', 'Missing');
  String get updateRemoteSubmodulesWarning => text(
    '선택한 서브모듈을 설정된 원격 브랜치의 최신 커밋으로 이동합니다.',
    'Move the selected submodules to the latest configured remote commits.',
  );
  String addSubmoduleOperation() => text('서브모듈 추가', 'Add submodule');
  String removeSubmoduleOperation(String path) =>
      text('서브모듈 제거: $path', 'Remove submodule: $path');
  String get initializeSubmodulesOperation =>
      text('서브모듈 초기화', 'Initialize submodules');
  String get updateSubmodulesOperation =>
      text('서브모듈 업데이트', 'Update submodules');
  String get updateRemoteSubmodulesOperation =>
      text('원격에서 서브모듈 업데이트', 'Update submodules from remotes');
  String get synchronizeSubmodulesOperation =>
      text('서브모듈 URL 동기화', 'Synchronize submodules');
  String get registerSubtreeOperation => text('Subtree 등록', 'Register subtree');
  String forgetSubtreeOperation(String prefix) =>
      text('Subtree 등록 해제: $prefix', 'Forget subtree: $prefix');
  String get refresh => text('새로고침', 'Refresh');
  String get fetch => text('Fetch', 'Fetch');
  String get pull => text('Pull', 'Pull');
  String get push => text('Push', 'Push');
  String get pullUsingConfig => text('Pull · Git 설정', 'Pull · Git config');
  String get pullMerge => text('Pull · 병합', 'Pull · Merge');
  String get pullRebase => text('받기 · Rebase', 'Pull · Rebase');
  String get pullFastForwardOnly =>
      text('Pull · Fast-forward만', 'Pull · Fast-forward only');
  String get forceWithLease => text('Force with lease', 'Force with lease');
  String get forceWithLeaseMenu =>
      text('Force with lease…', 'Force with lease…');
  String get commit => text('커밋', 'Commit');
  String get commitMessage => text('커밋 메시지', 'Commit message');
  String get staged => text('Staged', 'Staged');
  String get unstaged => text('Unstaged', 'Unstaged');
  String get conflicts => text('충돌', 'Conflicts');
  String get untracked => text('미추적', 'Untracked');
  String get diff => 'Diff';
  String get unified => text('통합 보기', 'Unified');
  String get sideBySide => text('나란히 보기', 'Side by side');
  String get noTextualDiff => text('표시할 텍스트 차이가 없습니다', 'No textual diff');
  String get noDifferences => text('차이가 없습니다', 'No differences');
  String get noCommits => text('커밋이 없습니다', 'No commits');
  String get binaryFile =>
      text('바이너리 또는 비 UTF-8 파일', 'Binary or non-UTF-8 file');
  String get fileLargerThan5Mb =>
      text('파일이 5MB보다 큽니다', 'File is larger than 5 MB');
  String get operationLog => text('작업 로그', 'Operation log');
  String get clear => text('지우기', 'Clear');
  String get cancel => text('취소', 'Cancel');
  String get confirm => text('확인', 'Confirm');
  String get close => text('닫기', 'Close');
  String get settings => text('설정', 'Settings');
  String get language => text('언어', 'Language');
  String get theme => text('테마', 'Theme');
  String get system => text('시스템', 'System');
  String get koreanLanguageName => text('한국어', '한국어');
  String get englishLanguageName => text('English', 'English');
  String get light => text('밝게', 'Light');
  String get dark => text('어둡게', 'Dark');
  String get createBranch => text('브랜치 만들기', 'Create branch');
  String get renameBranch => text('브랜치 이름 변경', 'Rename branch');
  String get deleteBranch => text('브랜치 삭제', 'Delete branch');
  String get rename => text('이름 변경', 'Rename');
  String get merge => text('병합', 'Merge');
  String get mergeIntoCurrent => text('현재 브랜치에 병합', 'Merge into current');
  String get rebase => 'Rebase';
  String get rebaseCurrentOntoThis =>
      text('현재 브랜치를 여기에 Rebase', 'Rebase current onto this');
  String get interactiveRebase => text('대화형 Rebase', 'Interactive rebase');
  String get stash => 'Stash';
  String get createStash => text('Stash 만들기', 'Create stash');
  String get message => text('메시지', 'Message');
  String get apply => text('적용', 'Apply');
  String get pop => text('적용 후 삭제', 'Pop');
  String get drop => text('삭제…', 'Drop…');
  String get dropStash => text('Stash 삭제', 'Drop stash');
  String get continueAction => text('계속', 'Continue');
  String get skip => text('건너뛰기', 'Skip');
  String get abort => text('중단하고 복원', 'Abort');
  String get resolve => text('충돌 해결', 'Resolve conflict');
  String get openInVscode => text('VS Code에서 열기', 'Open in VS Code');
  String get workingTreeClean => text('변경 사항이 없습니다', 'Working tree is clean');
  String get selectFile =>
      text('파일을 선택해 diff를 확인하세요', 'Select a file to inspect its diff');
  String get selectCommit =>
      text('커밋을 선택해 상세 내용을 확인하세요', 'Select a commit to inspect it');
  String get loadMore => text('이전 커밋 더 보기', 'Load older commits');
  String get repoUrl => text('원격 저장소 URL', 'Repository URL');
  String get destination => text('대상 폴더', 'Destination folder');
  String get initialBranch => text('초기 브랜치', 'Initial branch');
  String get createReadme => text('README 만들기', 'Create README');
  String get gitignoreTemplate => text('.gitignore 템플릿', '.gitignore template');
  String get originUrl => text('origin URL (선택)', 'origin URL (optional)');
  String get advancedOptions => text('고급 옵션', 'Advanced options');
  String get remoteName => text('원격 이름', 'Remote name');
  String get branchOrTag => text('브랜치 또는 태그', 'Branch or tag');
  String get cloneDepth => text('기록 깊이', 'History depth');
  String get singleBranch => text('한 브랜치만 복제', 'Clone a single branch');
  String get noTags => text('태그를 받지 않음', 'Do not fetch tags');
  String get recurseSubmodules =>
      text('Submodule 재귀 복제', 'Clone submodules recursively');
  String get shallowSubmodules =>
      text('Submodule 기록을 얕게 복제', 'Use shallow submodules');
  String get bloblessClone =>
      text('파일 본문은 필요할 때 받기', 'Download file contents on demand');
  String get sparseDirectories =>
      text('Sparse 디렉터리 (한 줄에 하나)', 'Sparse directories (one per line)');
  String get gitSettings => text('Git 설정', 'Git settings');
  String get repositoryScope => text('현재 저장소', 'This repository');
  String get globalScope => text('사용자 전역', 'Global');
  String get advancedConfig => text('고급 설정', 'Advanced config');
  String get manageRemotes => text('원격 관리', 'Manage remotes');
  String get sparseCheckout => 'Sparse checkout';
  String get add => text('추가', 'Add');
  String get edit => text('수정', 'Edit');
  String get inherited => text('상속', 'Inherited');
  String get disable => text('비활성화', 'Disable');
  String get save => text('저장', 'Save');
  String get recentRepositories => text('최근 저장소', 'Recent repositories');
  String get dragToReorderRepository =>
      text('드래그하여 저장소 순서 변경', 'Drag to reorder repositories');
  String get browse => text('찾아보기', 'Browse');
  String get stage => text('Stage', 'Stage');
  String get unstage => text('Unstage', 'Unstage');
  String get more => text('더 보기', 'More');
  String get resolveShort => text('해결', 'Resolve');
  String get discardMenu => text('변경 폐기…', 'Discard…');
  String get discardChangesQuestion => text('변경을 폐기할까요?', 'Discard changes?');
  String untrackedRecycleWarning(String path) => text(
    '$path\n\n이 파일은 Windows 휴지통으로 이동합니다.',
    '$path\n\nThe file will be moved to the Recycle Bin.',
  );
  String trackedDiscardWarning(String path) => text(
    '$path\n\n이 변경은 GitFront에서 복구할 수 없습니다.',
    '$path\n\nTracked changes cannot be recovered by GitFront.',
  );
  String get discard => text('변경 폐기', 'Discard changes');
  String get delete => text('삭제', 'Delete');
  String get showDetails => text('상세 패널 보기', 'Show detail panel');
  String get hideDetails => text('상세 패널 숨기기', 'Hide detail panel');
  String get externalEditor => text('외부 편집기', 'External editor');
  String get customExecutable => text('실행 파일 경로', 'Executable path');
  String get openExternal => text('외부 편집기로 열기', 'Open in external editor');
  String get copyCommitHash => text('전체 커밋 해시 복사', 'Copy full commit hash');
  String get commitActions => text('커밋 작업', 'Commit actions');
  String get compareWithHead => text('HEAD와 비교', 'Compare with HEAD');
  String get createBranchHere => text('여기서 브랜치 만들기…', 'Create branch here…');
  String get createTagHere => text('여기에 태그 만들기…', 'Create tag here…');
  String get checkoutDetached =>
      text('이 커밋으로 Checkout…', 'Checkout this commit…');
  String get cherryPick => 'Cherry-pick…';
  String get cherryPickChecking =>
      text('Cherry-pick · 확인 중…', 'Cherry-pick · Checking…');
  String get cherryPickAlreadyApplied =>
      text('Cherry-pick · 이미 반영됨', 'Cherry-pick · Already applied');
  String get cherryPickConflicts =>
      text('Cherry-pick · 충돌 가능', 'Cherry-pick · Conflicts likely');
  String get cherryPickNoChanges => text(
    '현재 HEAD에 적용할 변경이 없습니다.',
    'There are no changes to apply to the current HEAD.',
  );
  String get cherryPickConflictWarning => text(
    '현재 HEAD에 적용하면 충돌할 가능성이 있습니다.',
    'Applying this commit to the current HEAD is likely to conflict.',
  );
  String get revertCommit => 'Revert…';
  String get rebaseOntoCommit =>
      text('현재 브랜치를 이 커밋에 Rebase…', 'Rebase current branch onto this commit…');
  String get resetCurrentBranch =>
      text('현재 브랜치를 여기로 Reset', 'Reset current branch here');
  String get softReset => 'Soft';
  String get mixedReset => 'Mixed';
  String get hardReset => 'Hard…';
  String get tagName => text('태그 이름', 'Tag name');
  String get tagMessage => text('태그 메시지', 'Tag message');
  String get annotatedTag => text('Annotated 태그', 'Annotated tag');
  String get lightweightTag => text('Lightweight 태그', 'Lightweight tag');
  String get mainlineParent => text('기준 부모', 'Mainline parent');
  String get detachedHeadWarning => text(
    '브랜치가 아닌 커밋을 직접 checkout합니다. 새 커밋을 유지하려면 이후 브랜치를 만드세요.',
    'This checks out the commit without a branch. Create a branch later to keep new commits.',
  );
  String get resetPreview => text('Reset 영향 확인', 'Review reset impact');
  String get outgoingCommits =>
      text('현재 브랜치에서 벗어나는 커밋', 'Commits leaving the current branch');
  String get trackedChanges =>
      text('영향받는 tracked 변경', 'Affected tracked changes');
  String get recycleBinPaths =>
      text('휴지통으로 이동할 미추적 경로', 'Untracked paths moved to Recycle Bin');
  String get noItems => text('없음', 'None');
  String get typeBranchToConfirm => text(
    'Hard reset을 실행하려면 현재 브랜치 이름을 입력하세요.',
    'Type the current branch name to run the hard reset.',
  );
  String get hashCopied => text('커밋 해시를 복사했습니다.', 'Commit hash copied.');
  String get tag => text('태그', 'Tag');
  String get localBranch => text('로컬 브랜치', 'Local branch');
  String get remoteBranch => text('원격 브랜치', 'Remote branch');
  String selectedCount(int count) => text('$count개 선택', '$count selected');
  String get intentToAdd => text('추적 시작(내용 제외)', 'Intent to add');
  String get clearSelection => text('선택 해제', 'Clear selection');
  String get commitOptions => text('커밋 옵션', 'Commit options');
  String get amend => text('마지막 커밋 수정', 'Amend');
  String get signOff => 'Sign-off';
  String get allowEmpty => text('빈 커밋 허용', 'Allow empty');
  String get normalCommit => text('일반', 'Normal');
  String get fixupCommit => 'Fixup';
  String get squashCommit => 'Squash';
  String get targetCommit => text('대상 커밋', 'Target commit');
  String get signing => text('서명', 'Signing');
  String get useGitConfig => text('Git 설정 사용', 'Use Git config');
  String get signThisCommit => text('이 커밋 서명', 'Sign this commit');
  String get doNotSign => text('서명하지 않음', 'Do not sign');
  String get authorName => text('작성자 이름 (선택)', 'Author name (optional)');
  String get authorEmail => text('작성자 이메일 (선택)', 'Author email (optional)');
  String get authorDate =>
      text('작성 시각 (ISO 8601, 선택)', 'Author date (ISO 8601, optional)');
  String get stageSelected => text('선택 줄 Stage', 'Stage selected');
  String get unstageSelected => text('선택 줄 Unstage', 'Unstage selected');
  String get discardSelectedLines => text('선택 줄 폐기', 'Discard selected lines');
  String get discardSelectedLinesQuestion =>
      text('선택한 줄을 폐기할까요?', 'Discard selected lines?');
  String get stageHunk => text('Hunk 스테이지', 'Stage hunk');
  String get unstageHunk => text('Hunk 스테이지 해제', 'Unstage hunk');
  String get discardHunk => text('Hunk 폐기', 'Discard hunk');
  String get discardHunkQuestion =>
      text('이 Hunk를 폐기할까요?', 'Discard this hunk?');
  String get discardedChangesCannotRecover => text(
    '이 tracked 변경은 GitFront에서 복구할 수 없습니다.',
    'These tracked changes cannot be recovered by GitFront.',
  );
  String resolveConflictTitle(String path) =>
      text('충돌 해결 · $path', 'Resolve · $path');
  String get saveAndStage => text('저장하고 스테이지', 'Save and stage');
  String get both => text('둘 다', 'Both');
  String get result => text('결과', 'Result');
  String get binaryConflict =>
      text('바이너리 또는 비 UTF-8 충돌', 'Binary or non-UTF-8 conflict');
  String get conflictLargerThan5Mb =>
      text('충돌 파일이 5MB보다 큽니다', 'Conflict is larger than 5 MB');
  String useVersion(String label) => text('$label 사용', 'Use $label');
  String interactiveRebaseTitle(String upstream) =>
      text('대화형 Rebase · $upstream', 'Interactive rebase · $upstream');
  String get mergeCommitsFlattenWarning => text(
    '병합 커밋이 포함되어 있습니다. 현재 버전에서는 병합 구조가 평탄화됩니다.',
    'Merge commits are present. This v1 rebase will flatten them.',
  );
  String get newCommitMessage => text('새 커밋 메시지', 'New commit message');
  String get startRebase => text('Rebase 시작', 'Start rebase');
  String get systemDefaultApplication =>
      text('시스템 기본 앱', 'System default application');
  String get visualStudioCode =>
      text('Visual Studio Code', 'Visual Studio Code');
  String get gitMergeTool => text('Git mergetool', 'Git mergetool');
  String get customExecutableOption =>
      text('사용자 지정 실행 파일', 'Custom executable');
  String get configKey => text('키', 'Key');
  String get configValue => text('값', 'Value');
  String get fetchUrl => 'Fetch URL';
  String get pushUrlOptional => text('Push URL (선택)', 'Push URL (optional)');
  String get updates => text('업데이트', 'Updates');
  String get checkGithubReleases => text(
    'GitHub Releases에서 업데이트를 확인합니다',
    'Check GitHub Releases for updates',
  );
  String get download => text('다운로드', 'Download');
  String get restartAndUpdate => text('재시작 및 업데이트', 'Restart & update');
  String get check => text('확인', 'Check');
  String get noOperationsYet => text('아직 작업 기록이 없습니다.', 'No operations yet.');
  String get interactiveRebaseMenu =>
      text('대화형 Rebase…', 'Interactive rebase…');
  String get deleteMenu => text('삭제…', 'Delete…');
  String get typeValueToConfirm => text(
    '이 작업을 확인하려면 아래 값을 그대로 입력하세요.',
    'Type the value below to confirm this destructive action.',
  );
}

Locale resolveLocale(BuildContext context, AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => const Locale('ko'),
    AppLanguage.english => const Locale('en'),
    AppLanguage.system => Localizations.localeOf(context),
  };
}
