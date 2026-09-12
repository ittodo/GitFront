import 'package:flutter/widgets.dart';

import 'app_state.dart';

class GitFrontStrings {
  GitFrontStrings(this.locale);

  final Locale locale;

  bool get _ko => locale.languageCode == 'ko';

  String text(String korean, String english) => _ko ? korean : english;

  String get appName => 'GitFront Preview';
  String get openRepository => text('저장소 열기', 'Open repository');
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
  String get refresh => text('새로고침', 'Refresh');
  String get fetch => 'Fetch';
  String get pull => 'Pull';
  String get push => 'Push';
  String get commit => text('커밋', 'Commit');
  String get commitMessage => text('커밋 메시지', 'Commit message');
  String get staged => 'Staged';
  String get unstaged => 'Unstaged';
  String get conflicts => text('충돌', 'Conflicts');
  String get untracked => 'Untracked';
  String get diff => 'Diff';
  String get unified => 'Unified';
  String get sideBySide => 'Side by side';
  String get operationLog => text('작업 로그', 'Operation log');
  String get clear => text('지우기', 'Clear');
  String get cancel => text('취소', 'Cancel');
  String get confirm => text('확인', 'Confirm');
  String get close => text('닫기', 'Close');
  String get settings => text('설정', 'Settings');
  String get language => text('언어', 'Language');
  String get theme => text('테마', 'Theme');
  String get system => text('시스템', 'System');
  String get light => text('밝게', 'Light');
  String get dark => text('어둡게', 'Dark');
  String get createBranch => text('브랜치 만들기', 'Create branch');
  String get merge => 'Merge';
  String get rebase => 'Rebase';
  String get interactiveRebase => text('대화형 Rebase', 'Interactive rebase');
  String get stash => 'Stash';
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
  String get recentRepositories => text('최근 저장소', 'Recent repositories');
  String get browse => text('찾아보기', 'Browse');
  String get stage => 'Stage';
  String get unstage => 'Unstage';
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
}

Locale resolveLocale(BuildContext context, AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => const Locale('ko'),
    AppLanguage.english => const Locale('en'),
    AppLanguage.system => Localizations.localeOf(context),
  };
}
