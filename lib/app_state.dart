import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/rust/api/git.dart' as git_api;
import 'src/rust/api/models.dart';
import 'src/rust/api/update.dart' as update_api;

enum WorkspaceMode { changes, history }

enum AppLanguage { system, korean, english }

class RepoTabState {
  const RepoTabState({
    required this.snapshot,
    this.commits = const [],
    this.nextOffset,
    this.mode = WorkspaceMode.changes,
    this.selectedFile,
    this.selectedFileStaged = false,
    this.diff,
    this.selectedCommit,
    this.commitDetail,
    this.busy = false,
    this.error,
  });

  final RepositorySnapshot snapshot;
  final List<CommitSummary> commits;
  final int? nextOffset;
  final WorkspaceMode mode;
  final FileChange? selectedFile;
  final bool selectedFileStaged;
  final DiffDocument? diff;
  final CommitSummary? selectedCommit;
  final CommitDetail? commitDetail;
  final bool busy;
  final String? error;

  RepoTabState copyWith({
    RepositorySnapshot? snapshot,
    List<CommitSummary>? commits,
    int? nextOffset,
    bool clearNextOffset = false,
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
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return RepoTabState(
      snapshot: snapshot ?? this.snapshot,
      commits: commits ?? this.commits,
      nextOffset: clearNextOffset ? null : nextOffset ?? this.nextOffset,
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

final gitFrontProvider = NotifierProvider<GitFrontController, GitFrontState>(
  GitFrontController.new,
);

class GitFrontController extends Notifier<GitFrontState> {
  static const _openRepositoriesKey = 'openRepositories';
  static const _activeRepositoryKey = 'activeRepository';
  static const _languageKey = 'language';
  static const _darkModeKey = 'darkMode';
  static const _recentRepositoriesKey = 'recentRepositories';
  static const _leftPanelWidthKey = 'leftPanelWidth';
  static const _detailPanelWidthKey = 'detailPanelWidth';
  static const _detailPanelVisibleKey = 'detailPanelVisible';
  static const _externalEditorKey = 'externalEditor';
  static const _customEditorExecutableKey = 'customEditorExecutable';
  static const _lastUpdateCheckKey = 'lastUpdateCheck';
  final Map<String, StreamSubscription<dynamic>> _watchers = {};
  final Map<String, int> _requestVersions = {};

  @override
  GitFrontState build() {
    ref.onDispose(() {
      for (final watcher in _watchers.values) {
        unawaited(watcher.cancel());
      }
    });
    return const GitFrontState();
  }

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final languageName = preferences.getString(_languageKey);
    final language = AppLanguage.values.where(
      (item) => item.name == languageName,
    );
    final editorName = preferences.getString(_externalEditorKey);
    final editors = ExternalEditor.values.where(
      (editor) => editor.name == editorName,
    );
    state = state.copyWith(
      language: language.isEmpty ? AppLanguage.system : language.first,
      darkMode: preferences.containsKey(_darkModeKey)
          ? preferences.getBool(_darkModeKey)
          : null,
      recentRepositories:
          preferences.getStringList(_recentRepositoriesKey) ?? const [],
      leftPanelWidth: preferences.getDouble(_leftPanelWidthKey) ?? 250,
      detailPanelWidth: preferences.getDouble(_detailPanelWidthKey) ?? 560,
      detailPanelVisible: preferences.getBool(_detailPanelVisibleKey) ?? true,
      externalEditor: editors.isEmpty ? ExternalEditor.vsCode : editors.first,
      customEditorExecutable:
          preferences.getString(_customEditorExecutableKey) ?? '',
    );

    final paths = preferences.getStringList(_openRepositoriesKey) ?? const [];
    final activePath = preferences.getString(_activeRepositoryKey);
    for (final path in paths) {
      await openPath(path, select: path == activePath, persist: false);
    }
    state = state.copyWith(initializing: false);
    unawaited(_checkUpdateSilently(preferences));
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
      final snapshot = await git_api.openRepository(path: path);
      final page = await git_api.listCommits(
        path: snapshot.workdir,
        offset: 0,
        limit: 200,
      );
      final tabs = [
        ...state.tabs,
        RepoTabState(
          snapshot: snapshot,
          commits: page.commits,
          nextOffset: page.nextOffset,
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
      _appendLog('Opened ${snapshot.workdir}');
      if (persist) await _persistTabs();
    } catch (error) {
      _appendLog('Open failed: $error');
      rethrow;
    }
  }

  Future<void> clone(String url, String target) async {
    _appendLog('Cloning $url');
    final result = await git_api.cloneRepository(url: url, target: target);
    _recordResult('Clone', result);
    if (!result.success) throw Exception(result.summary);
    await openPath(target);
  }

  void activateTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(activeIndex: index);
    unawaited(_persistTabs());
    unawaited(refresh());
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
      final snapshot = await git_api.refreshRepository(path: path);
      CommitPage? page;
      if (reloadHistory) {
        page = await git_api.listCommits(
          path: snapshot.workdir,
          offset: 0,
          limit: 200,
        );
      }
      final index = _indexForPath(path);
      if (index < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[index];
      final selected = current.selectedFile == null
          ? null
          : snapshot.files
                .where((file) => file.path == current.selectedFile!.path)
                .firstOrNull;
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
      _updateTab(
        latestIndex,
        latest.copyWith(
          snapshot: snapshot,
          commits: page?.commits,
          nextOffset: page?.nextOffset,
          selectedFile: selected,
          clearSelectedFile: selected == null,
          diff: diff,
          clearDiff: selected == null,
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

  Future<void> loadMoreCommits() async {
    final tab = state.activeTab;
    if (tab == null || tab.nextOffset == null || tab.busy) return;
    final path = tab.snapshot.workdir;
    final requestVersion = _startRequest(path);
    final index = _indexForPath(path);
    _updateTab(index, tab.copyWith(busy: true));
    try {
      final page = await git_api.listCommits(
        path: path,
        offset: tab.nextOffset!,
        limit: 200,
      );
      final latestIndex = _indexForPath(path);
      if (latestIndex < 0 || !_isLatestRequest(path, requestVersion)) return;
      final current = state.tabs[latestIndex];
      _updateTab(
        latestIndex,
        current.copyWith(
          commits: [...current.commits, ...page.commits],
          nextOffset: page.nextOffset,
          clearNextOffset: page.nextOffset == null,
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
      if (!result.success) throw Exception(result.summary);
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

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.name);
  }

  Future<void> setDarkMode(bool? value) async {
    state = state.copyWith(darkMode: value, clearDarkMode: value == null);
    final preferences = await SharedPreferences.getInstance();
    if (value == null) {
      await preferences.remove(_darkModeKey);
    } else {
      await preferences.setBool(_darkModeKey, value);
    }
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_leftPanelWidthKey, state.leftPanelWidth);
    await preferences.setDouble(_detailPanelWidthKey, state.detailPanelWidth);
    await preferences.setBool(_detailPanelVisibleKey, state.detailPanelVisible);
  }

  Future<void> setExternalEditor(
    ExternalEditor editor, {
    String? customExecutable,
  }) async {
    state = state.copyWith(
      externalEditor: editor,
      customEditorExecutable: customExecutable,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_externalEditorKey, editor.name);
    await preferences.setString(
      _customEditorExecutableKey,
      state.customEditorExecutable,
    );
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _openRepositoriesKey,
      state.tabs.map((tab) => tab.snapshot.workdir).toList(),
    );
    await preferences.setStringList(
      _recentRepositoriesKey,
      state.recentRepositories,
    );
    final active = state.activeTab;
    if (active == null) {
      await preferences.remove(_activeRepositoryKey);
    } else {
      await preferences.setString(
        _activeRepositoryKey,
        active.snapshot.workdir,
      );
    }
  }

  Future<void> _checkUpdateSilently(SharedPreferences preferences) async {
    final last = preferences.getInt(_lastUpdateCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 24).inMilliseconds) return;
    await preferences.setInt(_lastUpdateCheckKey, now);
    try {
      final update = await update_api.checkForUpdate();
      if (update.state == UpdateState.available) {
        _appendLog(update.message);
      }
    } catch (error) {
      _appendLog('Update check failed: $error');
    }
  }

  void _startWatcher(String path) {
    final key = path.toLowerCase();
    if (_watchers.containsKey(key)) return;
    _watchers[key] = git_api.watchRepository(path: path).listen((_) {
      if (state.activeTab?.snapshot.workdir.toLowerCase() == key &&
          state.activeTab?.busy == false) {
        unawaited(refresh(repositoryPath: path));
      }
    }, onError: (Object error) => _appendLog('File watcher stopped: $error'));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
