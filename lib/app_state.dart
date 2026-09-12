import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_store.dart';
import 'src/rust/api/git.dart' as git_api;
import 'src/rust/api/models.dart';
import 'src/rust/api/update.dart' as update_api;

enum WorkspaceMode { changes, history }

enum AppLanguage { system, korean, english }

class RepoTabState {
  const RepoTabState({
    required this.snapshot,
    this.changes = const [],
    this.nextChangeCursor,
    this.totalChanges = 0,
    this.stagedChangeCount = 0,
    this.branches = const [],
    this.nextBranchCursor,
    this.totalBranches = 0,
    this.commits = const [],
    this.nextCursor,
    this.totalCommits = 0,
    this.mode = WorkspaceMode.changes,
    this.selectedFile,
    this.selectedFileStaged = false,
    this.diff,
    this.selectedCommit,
    this.commitDetail,
    this.commitComparison,
    this.commitComparisonLabel,
    this.busy = false,
    this.error,
  });

  final RepositorySnapshot snapshot;
  final List<FileChange> changes;
  final String? nextChangeCursor;
  final int totalChanges;
  final int stagedChangeCount;
  final List<BranchInfo> branches;
  final String? nextBranchCursor;
  final int totalBranches;
  final List<CommitSummary> commits;
  final String? nextCursor;
  final int totalCommits;
  final WorkspaceMode mode;
  final FileChange? selectedFile;
  final bool selectedFileStaged;
  final DiffDocument? diff;
  final CommitSummary? selectedCommit;
  final CommitDetail? commitDetail;
  final DiffDocument? commitComparison;
  final String? commitComparisonLabel;
  final bool busy;
  final String? error;

  List<FileChange> get visibleChanges =>
      changes.isEmpty && snapshot.files.isNotEmpty ? snapshot.files : changes;

  int get visibleChangeCount => totalChanges == 0 && snapshot.files.isNotEmpty
      ? snapshot.files.length
      : totalChanges;

  int get visibleStagedChangeCount =>
      stagedChangeCount == 0 && snapshot.files.isNotEmpty
      ? snapshot.files.where((file) => file.staged != ChangeKind.none).length
      : stagedChangeCount;

  List<BranchInfo> get visibleBranches =>
      branches.isEmpty && snapshot.branches.isNotEmpty
      ? snapshot.branches
      : branches;

  int get visibleBranchCount =>
      totalBranches == 0 && snapshot.branches.isNotEmpty
      ? snapshot.branches.length
      : totalBranches;

  RepoTabState copyWith({
    RepositorySnapshot? snapshot,
    List<FileChange>? changes,
    String? nextChangeCursor,
    bool clearNextChangeCursor = false,
    int? totalChanges,
    int? stagedChangeCount,
    List<BranchInfo>? branches,
    String? nextBranchCursor,
    bool clearNextBranchCursor = false,
    int? totalBranches,
    List<CommitSummary>? commits,
    String? nextCursor,
    bool clearNextCursor = false,
    int? totalCommits,
    WorkspaceMode? mode,
    FileChange? selectedFile,
    bool clearSelectedFile = false,
    bool? selectedFileStaged,
    DiffDocument? diff,
    bool clearDiff = false,
    CommitSummary? selectedCommit,
    bool clearSelectedCommit = false,
    CommitDetail? commitDetail,
    bool clearCommitDetail = false,
    DiffDocument? commitComparison,
    bool clearCommitComparison = false,
    String? commitComparisonLabel,
    bool clearCommitComparisonLabel = false,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return RepoTabState(
      snapshot: snapshot ?? this.snapshot,
      changes: changes ?? this.changes,
      nextChangeCursor: clearNextChangeCursor
          ? null
          : nextChangeCursor ?? this.nextChangeCursor,
      totalChanges: totalChanges ?? this.totalChanges,
      stagedChangeCount: stagedChangeCount ?? this.stagedChangeCount,
      branches: branches ?? this.branches,
      nextBranchCursor: clearNextBranchCursor
          ? null
          : nextBranchCursor ?? this.nextBranchCursor,
      totalBranches: totalBranches ?? this.totalBranches,
      commits: commits ?? this.commits,
      nextCursor: clearNextCursor ? null : nextCursor ?? this.nextCursor,
      totalCommits: totalCommits ?? this.totalCommits,
      mode: mode ?? this.mode,
      selectedFile: clearSelectedFile
          ? null
          : selectedFile ?? this.selectedFile,
      selectedFileStaged: selectedFileStaged ?? this.selectedFileStaged,
      diff: clearDiff ? null : diff ?? this.diff,
      selectedCommit: clearSelectedCommit
          ? null
          : selectedCommit ?? this.selectedCommit,
      commitDetail: clearCommitDetail
          ? null
          : commitDetail ?? this.commitDetail,
      commitComparison: clearCommitComparison
          ? null
          : commitComparison ?? this.commitComparison,
      commitComparisonLabel: clearCommitComparisonLabel
          ? null
          : commitComparisonLabel ?? this.commitComparisonLabel,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class GitFrontState {
  const GitFrontState({
    this.tabs = const [],
    this.activeIndex = -1,
    this.language = AppLanguage.system,
    this.darkMode,
    this.recentRepositories = const [],
    this.leftPanelWidth = 250,
    this.detailPanelWidth = 560,
    this.detailPanelVisible = true,
    this.externalEditor = ExternalEditor.vsCode,
    this.customEditorExecutable = '',
    this.operationLog = const [],
    this.initializing = true,
  });

  final List<RepoTabState> tabs;
  final int activeIndex;
  final AppLanguage language;
  final bool? darkMode;
  final List<String> recentRepositories;
  final double leftPanelWidth;
  final double detailPanelWidth;
  final bool detailPanelVisible;
  final ExternalEditor externalEditor;
  final String customEditorExecutable;
  final List<String> operationLog;
  final bool initializing;

  RepoTabState? get activeTab =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;

  GitFrontState copyWith({
    List<RepoTabState>? tabs,
    int? activeIndex,
    AppLanguage? language,
    bool? darkMode,
    bool clearDarkMode = false,
    List<String>? recentRepositories,
    double? leftPanelWidth,
    double? detailPanelWidth,
    bool? detailPanelVisible,
    ExternalEditor? externalEditor,
    String? customEditorExecutable,
    List<String>? operationLog,
    bool? initializing,
  }) {
    return GitFrontState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      language: language ?? this.language,
      darkMode: clearDarkMode ? null : darkMode ?? this.darkMode,
      recentRepositories: recentRepositories ?? this.recentRepositories,
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      detailPanelWidth: detailPanelWidth ?? this.detailPanelWidth,
      detailPanelVisible: detailPanelVisible ?? this.detailPanelVisible,
      externalEditor: externalEditor ?? this.externalEditor,
      customEditorExecutable:
          customEditorExecutable ?? this.customEditorExecutable,
      operationLog: operationLog ?? this.operationLog,
      initializing: initializing ?? this.initializing,
    );
  }
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => JsonSettingsStore.system(),
);

final gitFrontProvider = NotifierProvider<GitFrontController, GitFrontState>(
  GitFrontController.new,
);

class GitFrontController extends Notifier<GitFrontState> {
  final Map<String, StreamSubscription<dynamic>> _watchers = {};
  final Map<String, int> _requestVersions = {};
  late SettingsStore _settingsStore;
  AppSettings _settings = const AppSettings();

  @override
  GitFrontState build() {
    _settingsStore = ref.read(settingsStoreProvider);
    ref.onDispose(() {
      for (final watcher in _watchers.values) {
        unawaited(watcher.cancel());
      }
    });
    return const GitFrontState();
  }

  Future<void> initialize() async {
    final startup = Stopwatch()..start();
    _settings = await _settingsStore.load();
    final settingsLoadedAt = startup.elapsedMilliseconds;
    try {
      final capabilities = await git_api.gitCapabilities();
      _appendLog(capabilities.version);
      if (!capabilities.supportsRepositorySetup ||
          !capabilities.supportsFixedValueConfig ||
          !capabilities.supportsSparseCheckout) {
        _appendLog(
          'Git 2.31 or newer is recommended. Some repository setup features are unavailable.',
        );
      }
    } catch (error) {
      _appendLog('Git capability check failed: $error');
    }
    final languageName = _settings.language;
    final language = AppLanguage.values.where(
      (item) => item.name == languageName,
    );
    final editorName = _settings.externalEditor;
    final editors = ExternalEditor.values.where(
      (editor) => editor.name == editorName,
    );
    state = state.copyWith(
      language: language.isEmpty ? AppLanguage.system : language.first,
      darkMode: _settings.darkMode,
      recentRepositories: _settings.recentRepositories,
      leftPanelWidth: _settings.leftPanelWidth,
      detailPanelWidth: _settings.detailPanelWidth,
      detailPanelVisible: _settings.detailPanelVisible,
      externalEditor: editors.isEmpty ? ExternalEditor.vsCode : editors.first,
      customEditorExecutable: _settings.customEditorExecutable,
      initializing: false,
    );
    _appendLog(
      'Startup UI ready in ${startup.elapsedMilliseconds} ms '
      '(settings $settingsLoadedAt ms)',
    );

    final paths = _settings.openRepositories;
    final activePath = _settings.activeRepository;
    for (final path in paths) {
      try {
        await openPath(path, select: path == activePath, persist: false);
      } catch (error) {
        _appendLog('Could not restore $path\n$error');
      }
    }
    _appendLog(
      'Repository restore queued in ${startup.elapsedMilliseconds} ms '
      '(${state.tabs.length}/${paths.length} available)',
    );
    unawaited(_checkUpdateSilently());
  }

  Future<void> openPath(
    String path, {
    bool select = true,
    bool persist = true,
  }) async {
    final existing = state.tabs.indexWhere(
      (tab) => tab.snapshot.repositoryPath.toLowerCase() == path.toLowerCase(),
    );
    if (existing >= 0) {
      if (select) state = state.copyWith(activeIndex: existing);
      return;
    }
    try {
      final started = Stopwatch()..start();
      final opened = await git_api.openRepositoryPaged(
        path: path,
        changeLimit: 250,
      );
      final snapshot = opened.snapshot;
      final tabs = [
        ...state.tabs,
        RepoTabState(
          snapshot: snapshot,
          changes: opened.changes.files,
          nextChangeCursor: opened.changes.nextCursor,
          totalChanges: opened.changes.totalFiles,
          stagedChangeCount: opened.changes.stagedCount,
          branches: opened.branches.branches,
          nextBranchCursor: opened.branches.nextCursor,
          totalBranches: opened.branches.totalBranches,
          busy: true,
        ),
      ];
      state = state.copyWith(
        tabs: tabs,
        activeIndex: select ? tabs.length - 1 : state.activeIndex,
        recentRepositories: [
          snapshot.workdir,
          ...state.recentRepositories.where(
            (recent) => recent.toLowerCase() != snapshot.workdir.toLowerCase(),
          ),
        ].take(12).toList(),
      );
      _startWatcher(snapshot.workdir);
      _appendLog(
        'Opened ${snapshot.workdir} overview in ${started.elapsedMilliseconds} ms',
      );
      unawaited(_loadInitialHistory(snapshot.workdir));
      if (persist) await _persistTabs();
    } catch (error) {
      _appendLog('Open failed: $error');
      rethrow;
    }
  }

  Future<void> _loadInitialHistory(String path) async {
    final started = Stopwatch()..start();
    try {
      final page = await git_api.listCommitsCursor(
        path: path,
        cursor: null,
        limit: 200,
      );
      final index = _indexForPath(path);
      if (index < 0) return;
      _updateTab(
        index,
        state.tabs[index].copyWith(
          commits: page.commits,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          totalCommits: page.totalCommits,
          busy: false,
        ),
      );
      _appendLog(
        'History ready for $path in ${started.elapsedMilliseconds} ms '
        '(${page.commits.length} shown)',
      );
    } catch (error) {
      final index = _indexForPath(path);
      if (index >= 0) _setError(index, error);
    }
  }

  Future<void> clone(String url, String target) async {
    _appendLog('Cloning $url');
    final result = await git_api.cloneRepository(url: url, target: target);
    _recordResult('Clone', result);
    if (!result.success) throw Exception(result.summary);
    await openPath(target);
  }

  Future<void> cloneAdvanced(CloneOptions options) async {
    _appendLog('Cloning ${options.url}');
    final result = await git_api.cloneRepositoryAdvanced(options: options);
    _recordResult('Clone', result.operation);
    for (final warning in result.warnings) {
      _appendLog('Clone warning: $warning');
    }
    if (!result.operation.success) throw Exception(result.operation.summary);
    await openPath(result.path);
  }

  Future<void> initializeRepository(RepositoryInitOptions options) async {
    _appendLog('Initializing ${options.targetPath}');
    final result = await git_api.initializeRepository(options: options);
    _recordResult('Initialize repository', result.operation);
    for (final warning in result.warnings) {
      _appendLog('Initialize warning: $warning');
    }
    if (!result.operation.success) throw Exception(result.operation.summary);
    await openPath(result.path);
  }

  void activateTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(activeIndex: index);
    unawaited(_persistTabs());
    unawaited(refresh());
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.tabs.length) return;
    if (newIndex < 0 || newIndex > state.tabs.length) return;
    final activePath = state.activeTab?.snapshot.workdir;
    final tabs = [...state.tabs];
    final moved = tabs.removeAt(oldIndex);
    final insertionIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    if (insertionIndex == oldIndex) return;
    tabs.insert(insertionIndex, moved);
    final activeIndex = activePath == null
        ? -1
        : tabs.indexWhere(
            (tab) =>
                tab.snapshot.workdir.toLowerCase() == activePath.toLowerCase(),
          );
    state = state.copyWith(tabs: tabs, activeIndex: activeIndex);
    unawaited(_persistTabs());
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final closedPath = state.tabs[index].snapshot.workdir;
    final tabs = [...state.tabs]..removeAt(index);
    final activeIndex = tabs.isEmpty
        ? -1
        : state.activeIndex > index
        ? state.activeIndex - 1
        : state.activeIndex.clamp(0, tabs.length - 1);
    state = state.copyWith(tabs: tabs, activeIndex: activeIndex);
    unawaited(_watchers.remove(closedPath.toLowerCase())?.cancel());
    unawaited(_persistTabs());
  }

  Future<void> refresh({
    bool reloadHistory = false,
    String? repositoryPath,
  }) async {
    final initialIndex = repositoryPath == null
        ? state.activeIndex
        : _indexForPath(repositoryPath);
    final tab = initialIndex >= 0 && initialIndex < state.tabs.length
        ? state.tabs[initialIndex]
        : null;
    if (tab == null) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    _updateTab(initialIndex, tab.copyWith(busy: true, clearError: true));
    try {
      final refreshed = await git_api.refreshRepositoryPaged(
        path: path,
        changeLimit: 250,
      );
      final snapshot = refreshed.snapshot;
      CommitCursorPage? page;
      if (reloadHistory) {
        page = await git_api.listCommitsCursor(
          path: snapshot.workdir,
          cursor: null,
          limit: 200,
        );
      }
      final index = _indexForPath(path);
      if (index < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[index];
      FileChange? selected;
      if (current.selectedFile != null) {
        selected = refreshed.changes.files
            .where((file) => file.path == current.selectedFile!.path)
            .firstOrNull;
        selected ??= await git_api.getCachedFileChange(
          path: path,
          filePath: current.selectedFile!.path,
        );
      }
      DiffDocument? diff;
      if (selected != null) {
        diff = await git_api.getWorktreeDiff(
          path: path,
          filePath: selected.path,
          staged: current.selectedFileStaged,
        );
      }
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final latest = state.tabs[latestIndex];
      final refreshedCommit = page == null || latest.selectedCommit == null
          ? latest.selectedCommit
          : page.commits
                .where((commit) => commit.oid == latest.selectedCommit!.oid)
                .firstOrNull;
      _updateTab(
        latestIndex,
        latest.copyWith(
          snapshot: snapshot,
          changes: refreshed.changes.files,
          nextChangeCursor: refreshed.changes.nextCursor,
          clearNextChangeCursor: refreshed.changes.nextCursor == null,
          totalChanges: refreshed.changes.totalFiles,
          stagedChangeCount: refreshed.changes.stagedCount,
          branches: refreshed.branches.branches,
          nextBranchCursor: refreshed.branches.nextCursor,
          clearNextBranchCursor: refreshed.branches.nextCursor == null,
          totalBranches: refreshed.branches.totalBranches,
          commits: page?.commits,
          nextCursor: page?.nextCursor,
          clearNextCursor: page != null && page.nextCursor == null,
          totalCommits: page?.totalCommits,
          selectedFile: selected,
          clearSelectedFile: selected == null,
          diff: diff,
          clearDiff: selected == null,
          selectedCommit: refreshedCommit,
          clearSelectedCommit:
              page != null &&
              latest.selectedCommit != null &&
              refreshedCommit == null,
          clearCommitDetail: page != null,
          clearCommitComparison: page != null,
          clearCommitComparisonLabel: page != null,
          busy: false,
        ),
      );
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final index = _indexForPath(path);
        if (index >= 0) _setError(index, error);
      }
    }
  }

  Future<void> refreshWorkingTree({required String repositoryPath}) async {
    final initialIndex = _indexForPath(repositoryPath);
    if (initialIndex < 0) return;
    final tab = state.tabs[initialIndex];
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    try {
      final refreshed = await git_api.refreshWorkingTreePaged(
        path: path,
        changeLimit: 250,
      );
      final workingTree = refreshed.snapshot;
      final index = _indexForPath(path);
      if (index < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[index];
      FileChange? selected;
      if (current.selectedFile != null) {
        selected = refreshed.changes.files
            .where((file) => file.path == current.selectedFile!.path)
            .firstOrNull;
        selected ??= await git_api.getCachedFileChange(
          path: path,
          filePath: current.selectedFile!.path,
        );
      }
      DiffDocument? diff;
      if (selected != null) {
        diff = await git_api.getWorktreeDiff(
          path: path,
          filePath: selected.path,
          staged: current.selectedFileStaged,
        );
      }
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final latest = state.tabs[latestIndex];
      final snapshot = latest.snapshot;
      _updateTab(
        latestIndex,
        latest.copyWith(
          snapshot: RepositorySnapshot(
            repositoryPath: snapshot.repositoryPath,
            workdir: snapshot.workdir,
            name: snapshot.name,
            headName: snapshot.headName,
            headOid: snapshot.headOid,
            upstream: snapshot.upstream,
            ahead: snapshot.ahead,
            behind: snapshot.behind,
            state: workingTree.state,
            generation: workingTree.generation,
            files: const [],
            branches: snapshot.branches,
            remotes: snapshot.remotes,
            stashes: snapshot.stashes,
          ),
          changes: refreshed.changes.files,
          nextChangeCursor: refreshed.changes.nextCursor,
          clearNextChangeCursor: refreshed.changes.nextCursor == null,
          totalChanges: refreshed.changes.totalFiles,
          stagedChangeCount: refreshed.changes.stagedCount,
          selectedFile: selected,
          clearSelectedFile: selected == null,
          diff: diff,
          clearDiff: selected == null,
          busy: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final index = _indexForPath(path);
        if (index >= 0) _setError(index, error);
      }
    }
  }

  void setMode(WorkspaceMode mode) {
    final index = state.activeIndex;
    final tab = state.activeTab;
    if (tab == null) return;
    _updateTab(
      index,
      tab.copyWith(
        mode: mode,
        clearSelectedFile: mode == WorkspaceMode.history,
        clearDiff: mode == WorkspaceMode.history,
        clearSelectedCommit: mode == WorkspaceMode.changes,
        clearCommitDetail: mode == WorkspaceMode.changes,
        clearCommitComparison: true,
        clearCommitComparisonLabel: true,
      ),
    );
  }

  Future<void> selectFile(FileChange file, {required bool staged}) async {
    final tab = state.activeTab;
    if (tab == null) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(
      index,
      tab.copyWith(
        selectedFile: file,
        selectedFileStaged: staged,
        busy: true,
        clearDiff: true,
        clearError: true,
      ),
    );
    try {
      final diff = await git_api.getWorktreeDiff(
        path: path,
        filePath: file.path,
        staged: staged,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex >= 0 && _isLatestRequest(path, requestVersion)) {
        _updateTab(
          latestIndex,
          state.tabs[latestIndex].copyWith(diff: diff, busy: false),
        );
      }
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  Future<void> selectCommit(CommitSummary commit) async {
    final tab = state.activeTab;
    if (tab == null) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(
      index,
      tab.copyWith(
        selectedCommit: commit,
        busy: true,
        clearCommitDetail: true,
        clearCommitComparison: true,
        clearCommitComparisonLabel: true,
        clearError: true,
      ),
    );
    try {
      final detail = await git_api.getCommitDetail(path: path, oid: commit.oid);
      final latestIndex = _indexForPath(path);
      if (latestIndex >= 0 && _isLatestRequest(path, requestVersion)) {
        _updateTab(
          latestIndex,
          state.tabs[latestIndex].copyWith(commitDetail: detail, busy: false),
        );
      }
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  void focusCommit(CommitSummary commit) {
    final tab = state.activeTab;
    if (tab == null || tab.selectedCommit?.oid == commit.oid) return;
    _updateTab(
      state.activeIndex,
      tab.copyWith(
        selectedCommit: commit,
        clearCommitDetail: true,
        clearCommitComparison: true,
        clearCommitComparisonLabel: true,
      ),
    );
  }

  Future<CherryPickApplicability> assessCherryPick(
    CommitSummary commit, {
    int? mainlineParent,
  }) async {
    final tab = state.activeTab;
    if (tab == null) throw StateError('No repository is open.');
    return git_api.assessCherryPick(
      path: tab.snapshot.workdir,
      oid: commit.oid,
      mainlineParent: mainlineParent,
    );
  }

  Future<void> compareCommitWithHead(CommitSummary commit) async {
    final tab = state.activeTab;
    final headOid = tab?.snapshot.headOid;
    if (tab == null || headOid == null || headOid == commit.oid) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(
      index,
      tab.copyWith(
        selectedCommit: commit,
        busy: true,
        clearCommitDetail: true,
        clearCommitComparison: true,
        clearCommitComparisonLabel: true,
        clearError: true,
      ),
    );
    try {
      final comparison = await git_api.compareCommits(
        path: path,
        fromOid: commit.oid,
        toOid: headOid,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex >= 0 && _isLatestRequest(path, requestVersion)) {
        _updateTab(
          latestIndex,
          state.tabs[latestIndex].copyWith(
            commitComparison: comparison,
            commitComparisonLabel: '${commit.shortOid} → HEAD',
            busy: false,
          ),
        );
      }
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  Future<void> loadMoreCommits() async {
    final tab = state.activeTab;
    if (tab == null || tab.nextCursor == null || tab.busy) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(index, tab.copyWith(busy: true));
    try {
      final page = await git_api.listCommitsCursor(
        path: path,
        cursor: tab.nextCursor,
        limit: 200,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[latestIndex];
      _updateTab(
        latestIndex,
        current.copyWith(
          commits: [...current.commits, ...page.commits],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          totalCommits: page.totalCommits,
          busy: false,
        ),
      );
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  Future<void> loadMoreChanges() async {
    final tab = state.activeTab;
    if (tab == null || tab.nextChangeCursor == null || tab.busy) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(index, tab.copyWith(busy: true));
    try {
      final page = await git_api.listChangesCursor(
        path: path,
        cursor: tab.nextChangeCursor!,
        limit: 250,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[latestIndex];
      _updateTab(
        latestIndex,
        current.copyWith(
          changes: [...current.changes, ...page.files],
          nextChangeCursor: page.nextCursor,
          clearNextChangeCursor: page.nextCursor == null,
          totalChanges: page.totalFiles,
          stagedChangeCount: page.stagedCount,
          busy: false,
        ),
      );
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  Future<void> loadMoreBranches() async {
    final tab = state.activeTab;
    if (tab == null || tab.nextBranchCursor == null || tab.busy) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(index, tab.copyWith(busy: true));
    try {
      final page = await git_api.listBranchesCursor(
        path: path,
        cursor: tab.nextBranchCursor!,
        limit: 250,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[latestIndex];
      _updateTab(
        latestIndex,
        current.copyWith(
          branches: [...current.branches, ...page.branches],
          nextBranchCursor: page.nextCursor,
          clearNextBranchCursor: page.nextCursor == null,
          totalBranches: page.totalBranches,
          busy: false,
        ),
      );
    } catch (error) {
      if (_isLatestRequest(path, requestVersion)) {
        final latestIndex = _indexForPath(path);
        if (latestIndex >= 0) _setError(latestIndex, error);
      }
    }
  }

  Future<OperationResult> runOperation(
    String label,
    Future<OperationResult> Function(String repositoryPath) operation, {
    bool reloadHistory = false,
  }) async {
    final tab = state.activeTab;
    if (tab == null) throw StateError('No repository is open.');
    final repositoryPath = tab.snapshot.workdir;
    final index = _indexForPath(repositoryPath);
    _updateTab(index, tab.copyWith(busy: true, clearError: true));
    _appendLog('$label started');
    try {
      final result = await operation(repositoryPath);
      _recordResult(label, result);
      if (!result.success) {
        await refresh(
          reloadHistory: reloadHistory,
          repositoryPath: repositoryPath,
        );
        throw Exception(result.summary);
      }
      await refresh(
        reloadHistory: reloadHistory,
        repositoryPath: repositoryPath,
      );
      return result;
    } catch (error) {
      final latestIndex = _indexForPath(repositoryPath);
      if (latestIndex >= 0) _setError(latestIndex, error);
      rethrow;
    }
  }

  Future<OperationResult> runStandaloneOperation(
    String label,
    Future<OperationResult> Function() operation,
  ) async {
    _appendLog('$label started');
    try {
      final result = await operation();
      _recordResult(label, result);
      if (!result.success && result.exitCode != 5) {
        throw Exception(result.summary);
      }
      return result;
    } catch (error) {
      _appendLog('$label failed: $error');
      rethrow;
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    _settings = _settings.copyWith(language: language.name);
    await _saveSettings();
  }

  Future<void> setDarkMode(bool? value) async {
    state = state.copyWith(darkMode: value, clearDarkMode: value == null);
    _settings = _settings.copyWith(darkMode: value);
    await _saveSettings();
  }

  Future<void> setPanelWidths({
    required double leftWidth,
    required double detailWidth,
  }) async {
    state = state.copyWith(
      leftPanelWidth: leftWidth.clamp(100, 1600),
      detailPanelWidth: detailWidth.clamp(160, 2400),
    );
    await persistLayout();
  }

  Future<void> toggleDetailPanel() async {
    state = state.copyWith(detailPanelVisible: !state.detailPanelVisible);
    await persistLayout();
  }

  Future<void> persistLayout() async {
    _settings = _settings.copyWith(
      leftPanelWidth: state.leftPanelWidth,
      detailPanelWidth: state.detailPanelWidth,
      detailPanelVisible: state.detailPanelVisible,
    );
    await _saveSettings();
  }

  Future<void> setExternalEditor(
    ExternalEditor editor, {
    String? customExecutable,
  }) async {
    state = state.copyWith(
      externalEditor: editor,
      customEditorExecutable: customExecutable,
    );
    _settings = _settings.copyWith(
      externalEditor: editor.name,
      customEditorExecutable: state.customEditorExecutable,
    );
    await _saveSettings();
  }

  String commitDraft(String repositoryPath) =>
      _settings.commitDrafts[repositoryPath.toLowerCase()] ?? '';

  Future<void> saveCommitDraft(String repositoryPath, String message) async {
    final drafts = Map<String, String>.from(_settings.commitDrafts);
    final key = repositoryPath.toLowerCase();
    if (message.isEmpty) {
      drafts.remove(key);
    } else {
      drafts[key] = message;
    }
    _settings = _settings.copyWith(commitDrafts: drafts);
    await _saveSettings();
  }

  void clearOperationLog() => state = state.copyWith(operationLog: const []);

  void _setError(int index, Object error) {
    if (index < 0 || index >= state.tabs.length) return;
    _updateTab(
      index,
      state.tabs[index].copyWith(busy: false, error: error.toString()),
    );
    _appendLog('Error: $error');
  }

  void _recordResult(String label, OperationResult result) {
    final detail = [
      result.summary,
      result.stdout,
      result.stderr,
    ].where((part) => part.trim().isNotEmpty).join('\n');
    _appendLog('$label ${result.success ? 'completed' : 'failed'}\n$detail');
  }

  void _appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final log = [...state.operationLog, '[$timestamp] $message'];
    state = state.copyWith(
      operationLog: log.length > 500 ? log.sublist(log.length - 500) : log,
    );
  }

  void _updateTab(int index, RepoTabState tab) {
    if (index < 0 || index >= state.tabs.length) return;
    final tabs = [...state.tabs];
    tabs[index] = tab;
    state = state.copyWith(tabs: tabs);
  }

  int _indexForPath(String path) => state.tabs.indexWhere(
    (tab) => tab.snapshot.workdir.toLowerCase() == path.toLowerCase(),
  );

  int _startRequest(String path) {
    final key = path.toLowerCase();
    final next = (_requestVersions[key] ?? 0) + 1;
    _requestVersions[key] = next;
    return next;
  }

  bool _isLatestRequest(String path, int requestVersion) =>
      _requestVersions[path.toLowerCase()] == requestVersion;

  Future<void> _persistTabs() async {
    final active = state.activeTab;
    _settings = _settings.copyWith(
      openRepositories: state.tabs
          .map((tab) => tab.snapshot.workdir)
          .toList(growable: false),
      recentRepositories: state.recentRepositories,
      activeRepository: active?.snapshot.workdir,
    );
    await _saveSettings();
  }

  Future<void> _checkUpdateSilently() async {
    final last = _settings.lastUpdateCheck;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 24).inMilliseconds) return;
    _settings = _settings.copyWith(lastUpdateCheck: now);
    await _saveSettings();
    try {
      final update = await update_api.checkForUpdate();
      if (update.state == UpdateState.available) {
        _appendLog(update.message);
      }
    } catch (error) {
      _appendLog('Update check failed: $error');
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsStore.save(_settings);
    } on Object catch (error) {
      _appendLog('Settings save failed: $error');
    }
  }

  void _startWatcher(String path) {
    final key = path.toLowerCase();
    if (_watchers.containsKey(key)) return;
    _watchers[key] = git_api.watchRepository(path: path).listen((event) {
      if (state.activeTab?.snapshot.workdir.toLowerCase() == key &&
          state.activeTab?.busy == false) {
        final fullRefresh =
            event.paths.isEmpty || event.paths.any(_isGitMetadataPath);
        final historyChanged = event.paths.any(_isGitHistoryPath);
        if (fullRefresh) {
          unawaited(
            refresh(
              repositoryPath: path,
              reloadHistory:
                  historyChanged &&
                  state.activeTab?.mode == WorkspaceMode.history,
            ),
          );
        } else {
          unawaited(refreshWorkingTree(repositoryPath: path));
        }
      }
    }, onError: (Object error) => _appendLog('File watcher stopped: $error'));
  }
}

bool _isGitMetadataPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized == '.git' || normalized.startsWith('.git/');
}

bool _isGitHistoryPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized == '.git/head' ||
      normalized == '.git/packed-refs' ||
      normalized.startsWith('.git/refs/') ||
      normalized.startsWith('.git/logs/');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
