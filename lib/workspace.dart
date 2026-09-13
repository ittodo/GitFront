import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_state.dart';
import 'l10n.dart';
import 'src/rust/api/git.dart' as git_api;
import 'src/rust/api/models.dart';
import 'src/rust/api/update.dart' as update_api;

class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(gitFrontProvider.notifier).initialize());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gitFrontProvider);
    final strings = GitFrontStrings(resolveLocale(context, state.language));
    if (state.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TitleBar(
              strings: strings,
              state: state,
              onCreate: () => _showCreateRepositoryDialog(strings),
              onOpen: () => _openRepository(strings),
              onClone: () => _showCloneDialog(strings),
              onSettings: () => _showSettings(strings),
              onShowLog: () => _showOperationLog(strings),
            ),
            if (state.tabs.isNotEmpty)
              _RepositoryTabs(
                strings: strings,
                state: state,
                onSelect: ref.read(gitFrontProvider.notifier).activateTab,
                onClose: ref.read(gitFrontProvider.notifier).closeTab,
                onReorder: ref.read(gitFrontProvider.notifier).reorderTabs,
              ),
            const Divider(height: 1),
            Expanded(
              child: state.activeTab == null
                  ? _EmptyState(
                      strings: strings,
                      recentRepositories: state.recentRepositories,
                      onRecent: (path) async {
                        try {
                          await ref
                              .read(gitFrontProvider.notifier)
                              .openPath(path);
                        } catch (error) {
                          _showError(error);
                        }
                      },
                      onCreate: () => _showCreateRepositoryDialog(strings),
                      onOpen: () => _openRepository(strings),
                      onClone: () => _showCloneDialog(strings),
                    )
                  : _RepositoryWorkspace(
                      key: ValueKey(state.activeTab!.snapshot.repositoryPath),
                      strings: strings,
                      tab: state.activeTab!,
                      onError: _showError,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRepository(GitFrontStrings strings) async {
    final path = await getDirectoryPath(
      confirmButtonText: strings.openRepository,
    );
    if (path == null || !mounted) return;
    try {
      await ref.read(gitFrontProvider.notifier).openPath(path);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showCloneDialog(GitFrontStrings strings) async {
    final result = await showDialog<CloneOptions>(
      context: context,
      builder: (context) => _CloneDialog(strings: strings),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(gitFrontProvider.notifier).cloneAdvanced(result);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showCreateRepositoryDialog(GitFrontStrings strings) async {
    final result = await showDialog<RepositoryInitOptions>(
      context: context,
      builder: (context) => _CreateRepositoryDialog(strings: strings),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(gitFrontProvider.notifier).initializeRepository(result);
    } catch (error) {
      _showError(error);
    }
  }

  void _showSettings(GitFrontStrings strings) {
    showDialog<void>(
      context: context,
      builder: (context) => _SettingsDialog(strings: strings),
    );
  }

  void _showOperationLog(GitFrontStrings strings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 560),
      builder: (context) => _OperationLog(strings: strings),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.strings,
    required this.state,
    required this.onCreate,
    required this.onOpen,
    required this.onClone,
    required this.onSettings,
    required this.onShowLog,
  });

  final GitFrontStrings strings;
  final GitFrontState state;
  final VoidCallback onCreate;
  final VoidCallback onOpen;
  final VoidCallback onClone;
  final VoidCallback onSettings;
  final VoidCallback onShowLog;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.call_split_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              strings.appName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).width >= 900) ...[
              _ToolbarButton(
                icon: Icons.create_new_folder_outlined,
                label: strings.createRepository,
                onPressed: onCreate,
              ),
              const SizedBox(width: 6),
              _ToolbarButton(
                icon: Icons.folder_open_outlined,
                label: strings.openRepository,
                onPressed: onOpen,
              ),
              const SizedBox(width: 6),
              _ToolbarButton(
                icon: Icons.cloud_download_outlined,
                label: strings.cloneRepository,
                onPressed: onClone,
              ),
            ] else ...[
              IconButton(
                tooltip: strings.createRepository,
                onPressed: onCreate,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: strings.openRepository,
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: strings.cloneRepository,
                onPressed: onClone,
                icon: const Icon(Icons.cloud_download_outlined),
              ),
            ],
            IconButton(
              tooltip: strings.operationLog,
              onPressed: onShowLog,
              icon: Badge(
                isLabelVisible: state.operationLog.isNotEmpty,
                smallSize: 7,
                child: const Icon(Icons.terminal_rounded),
              ),
            ),
            IconButton(
              tooltip: strings.settings,
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepositoryTabs extends StatelessWidget {
  const _RepositoryTabs({
    required this.strings,
    required this.state,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
  });

  final GitFrontStrings strings;
  final GitFrontState state;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        buildDefaultDragHandles: false,
        onReorder: onReorder,
        itemCount: state.tabs.length,
        itemBuilder: (context, index) {
          final tab = state.tabs[index];
          final selected = state.activeIndex == index;
          final dirty = tab.visibleChangeCount > 0;
          return Padding(
            key: ValueKey('repository-tab:${tab.snapshot.workdir}'),
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: strings.dragToReorderRepository,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(7),
                        onTap: () => onSelect(index),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (dirty)
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 7),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Text(tab.snapshot.name),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: strings.close,
                    onPressed: () => onClose(index),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RepositoryWorkspace extends ConsumerWidget {
  const _RepositoryWorkspace({
    super.key,
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(gitFrontProvider.notifier);
    final appState = ref.watch(gitFrontProvider);
    final sidebar = _RepositorySidebar(
      strings: strings,
      tab: tab,
      onError: onError,
    );
    final center = tab.mode == WorkspaceMode.changes
        ? _ChangesPanel(strings: strings, tab: tab, onError: onError)
        : _HistoryPanel(strings: strings, tab: tab, onError: onError);
    final detail = tab.mode == WorkspaceMode.changes
        ? _DiffPane(strings: strings, tab: tab, onError: onError)
        : _CommitDetailPane(strings: strings, tab: tab);
    return Column(
      children: [
        _RepositoryToolbar(strings: strings, tab: tab, onError: onError),
        if (tab.snapshot.state != RepositoryState.clean)
          _RepositoryStateBanner(strings: strings, tab: tab, onError: onError),
        if (tab.error != null)
          MaterialBanner(
            content: Text(tab.error!),
            leading: const Icon(Icons.error_outline),
            actions: [
              TextButton(
                onPressed: () => unawaited(controller.refresh()),
                child: Text(strings.refresh),
              ),
            ],
          ),
        Expanded(
          child: _ResizableRepositoryPanels(
            initialLeftWidth: appState.leftPanelWidth,
            initialDetailWidth: appState.detailPanelWidth,
            detailVisible: appState.detailPanelVisible,
            hasDetail:
                tab.diff != null ||
                tab.commitDetail != null ||
                tab.commitComparison != null,
            sidebar: sidebar,
            center: center,
            detail: detail,
            onPersist: (leftWidth, detailWidth) => unawaited(
              controller.setPanelWidths(
                leftWidth: leftWidth,
                detailWidth: detailWidth,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

typedef _PanelWidthsChanged =
    void Function(double leftWidth, double detailWidth);

class _ResizableRepositoryPanels extends StatefulWidget {
  const _ResizableRepositoryPanels({
    required this.initialLeftWidth,
    required this.initialDetailWidth,
    required this.detailVisible,
    required this.hasDetail,
    required this.sidebar,
    required this.center,
    required this.detail,
    required this.onPersist,
  });

  final double initialLeftWidth;
  final double initialDetailWidth;
  final bool detailVisible;
  final bool hasDetail;
  final Widget sidebar;
  final Widget center;
  final Widget detail;
  final _PanelWidthsChanged onPersist;

  @override
  State<_ResizableRepositoryPanels> createState() =>
      _ResizableRepositoryPanelsState();
}

class _ResizableRepositoryPanelsState
    extends State<_ResizableRepositoryPanels> {
  late double leftWidth;
  late double detailWidth;
  bool dragging = false;

  @override
  void initState() {
    super.initState();
    leftWidth = widget.initialLeftWidth;
    detailWidth = widget.initialDetailWidth;
  }

  @override
  void didUpdateWidget(covariant _ResizableRepositoryPanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dragging && oldWidget.initialLeftWidth != widget.initialLeftWidth) {
      leftWidth = widget.initialLeftWidth;
    }
    if (!dragging &&
        oldWidget.initialDetailWidth != widget.initialDetailWidth) {
      detailWidth = widget.initialDetailWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const handleWidth = 7.0;
        final compact = constraints.maxWidth < 980;
        final showDetail =
            widget.detailVisible && (!compact || widget.hasDetail);
        final leftMinimum = compact ? 120.0 : 160.0;
        final centerMinimum = compact ? 140.0 : 220.0;
        final detailMinimum = compact ? 180.0 : 260.0;
        final handleSpace = showDetail ? handleWidth * 2 : handleWidth;
        final leftMaximumCandidate =
            constraints.maxWidth -
            centerMinimum -
            handleSpace -
            (showDetail ? detailMinimum : 0);
        final leftMaximum = leftMaximumCandidate < leftMinimum
            ? leftMinimum
            : leftMaximumCandidate;
        final effectiveLeft = _clampPanelWidth(
          leftWidth,
          leftMinimum,
          leftMaximum,
        );
        final detailMaximumCandidate =
            constraints.maxWidth - effectiveLeft - centerMinimum - handleSpace;
        final detailMaximum = detailMaximumCandidate < detailMinimum
            ? detailMinimum
            : detailMaximumCandidate;
        final effectiveDetail = _clampPanelWidth(
          detailWidth,
          detailMinimum,
          detailMaximum,
        );
        final leftDragMaximum =
            constraints.maxWidth -
            centerMinimum -
            handleSpace -
            (showDetail ? effectiveDetail : 0);

        return Row(
          children: [
            SizedBox(width: effectiveLeft, child: widget.sidebar),
            _PanelResizer(
              onStart: _startDrag,
              onDrag: (delta) {
                setState(() {
                  final currentLeft = _clampPanelWidth(
                    leftWidth,
                    leftMinimum,
                    leftMaximum,
                  );
                  leftWidth = _clampPanelWidth(
                    currentLeft + delta,
                    leftMinimum,
                    leftDragMaximum < leftMinimum
                        ? leftMinimum
                        : leftDragMaximum,
                  );
                  detailWidth = effectiveDetail;
                });
              },
              onEnd: _finishDrag,
            ),
            Expanded(child: widget.center),
            if (showDetail) ...[
              _PanelResizer(
                onStart: _startDrag,
                onDrag: (delta) {
                  setState(() {
                    leftWidth = effectiveLeft;
                    final currentDetail = _clampPanelWidth(
                      detailWidth,
                      detailMinimum,
                      detailMaximum,
                    );
                    detailWidth = _clampPanelWidth(
                      currentDetail - delta,
                      detailMinimum,
                      detailMaximum,
                    );
                  });
                },
                onEnd: _finishDrag,
              ),
              SizedBox(width: effectiveDetail, child: widget.detail),
            ],
          ],
        );
      },
    );
  }

  void _startDrag() => dragging = true;

  void _finishDrag() {
    dragging = false;
    widget.onPersist(leftWidth, detailWidth);
  }
}

double _clampPanelWidth(double value, double minimum, double maximum) =>
    value.clamp(minimum, maximum).toDouble();

class _RepositoryToolbar extends ConsumerWidget {
  const _RepositoryToolbar({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(gitFrontProvider.notifier);
    Future<void> run(
      Future<OperationResult> Function(String) action,
      String label,
    ) async {
      try {
        await controller.runOperation(label, action, reloadHistory: true);
      } catch (error) {
        onError(error);
      }
    }

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SegmentedButton<WorkspaceMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: WorkspaceMode.changes,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text('${strings.changes} (${tab.visibleChangeCount})'),
                ),
                ButtonSegment(
                  value: WorkspaceMode.history,
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(strings.history),
                ),
              ],
              selected: {tab.mode},
              onSelectionChanged: (value) => controller.setMode(value.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tab.snapshot.workdir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (tab.snapshot.ahead > 0 || tab.snapshot.behind > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('↑${tab.snapshot.ahead}  ↓${tab.snapshot.behind}'),
              ),
            IconButton(
              tooltip: strings.refresh,
              onPressed: tab.busy
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: ref.watch(gitFrontProvider).detailPanelVisible
                  ? strings.hideDetails
                  : strings.showDetails,
              onPressed: () => unawaited(controller.toggleDetailPanel()),
              icon: Icon(
                ref.watch(gitFrontProvider).detailPanelVisible
                    ? Icons.vertical_split
                    : Icons.vertical_split_outlined,
              ),
            ),
            _ToolbarButton(
              icon: Icons.sync,
              label: strings.fetch,
              onPressed: tab.busy
                  ? null
                  : () => unawaited(
                      run((path) => git_api.fetchAll(path: path), 'Fetch'),
                    ),
            ),
            PopupMenuButton<PullMode>(
              enabled: !tab.busy,
              tooltip: strings.pull,
              initialValue: PullMode.configured,
              onSelected: (mode) => unawaited(
                run((path) => git_api.pull(path: path, mode: mode), 'Pull'),
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: PullMode.configured,
                  child: Text('Pull · Git config'),
                ),
                PopupMenuItem(
                  value: PullMode.merge,
                  child: Text('Pull · Merge'),
                ),
                PopupMenuItem(
                  value: PullMode.rebase,
                  child: Text('Pull · Rebase'),
                ),
                PopupMenuItem(
                  value: PullMode.fastForwardOnly,
                  child: Text('Pull · Fast-forward only'),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward, size: 18),
                    SizedBox(width: 5),
                    Text('Pull'),
                  ],
                ),
              ),
            ),
            PopupMenuButton<bool>(
              enabled: !tab.busy,
              tooltip: strings.push,
              onSelected: (force) async {
                if (force &&
                    !await _confirmTyped(
                      context,
                      title: 'Force with lease',
                      value: tab.snapshot.headName ?? '',
                    )) {
                  return;
                }
                if (!context.mounted) return;
                if (tab.snapshot.upstream == null) {
                  final target = await _showPushTargetDialog(
                    context,
                    strings,
                    tab.snapshot.remotes,
                    tab.snapshot.headName,
                  );
                  if (target == null) return;
                  unawaited(
                    run(
                      (path) => git_api.pushCurrentTo(
                        path: path,
                        remote: target.remote,
                        remoteBranch: target.branch,
                        forceWithLease: force,
                      ),
                      force ? 'Force push with lease' : 'Push & set upstream',
                    ),
                  );
                  return;
                }
                unawaited(
                  run(
                    (path) => git_api.pushCurrent(
                      path: path,
                      forceWithLease: force,
                      setUpstream: tab.snapshot.upstream == null,
                    ),
                    force ? 'Force push with lease' : 'Push',
                  ),
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: false, child: Text('Push')),
                PopupMenuItem(value: true, child: Text('Force with lease…')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 18),
                    SizedBox(width: 5),
                    Text('Push'),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: strings.manageSubtrees,
              onPressed: tab.busy
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => _SubtreeManagerDialog(
                        strings: strings,
                        repositoryPath: tab.snapshot.workdir,
                      ),
                    ),
              icon: const Icon(Icons.account_tree_outlined),
            ),
            if (tab.busy)
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _PushTarget = ({String remote, String branch});

Future<_PushTarget?> _showPushTargetDialog(
  BuildContext context,
  GitFrontStrings strings,
  List<RemoteInfo> remotes,
  String? currentBranch,
) async {
  if (remotes.isEmpty || currentBranch == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.text(
            '먼저 원격 저장소를 추가하고 로컬 브랜치를 checkout하세요.',
            'Add a remote and check out a local branch first.',
          ),
        ),
      ),
    );
    return null;
  }
  var selected = remotes.any((remote) => remote.name == 'origin')
      ? 'origin'
      : remotes.first.name;
  final branch = TextEditingController(text: currentBranch);
  final result = await showDialog<_PushTarget>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(strings.text('Upstream 설정', 'Set upstream')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: strings.remoteName),
                items: remotes
                    .map(
                      (remote) => DropdownMenuItem(
                        value: remote.name,
                        child: Text(remote.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selected = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: branch,
                decoration: InputDecoration(labelText: strings.remoteBranch),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (branch.text.trim().isEmpty) return;
              Navigator.pop(context, (
                remote: selected,
                branch: branch.text.trim(),
              ));
            },
            child: Text(strings.push),
          ),
        ],
      ),
    ),
  );
  branch.dispose();
  return result;
}

class _RepositoryStateBanner extends ConsumerWidget {
  const _RepositoryStateBanner({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(gitFrontProvider.notifier);
    final isRebase = {
      RepositoryState.rebase,
      RepositoryState.rebaseInteractive,
      RepositoryState.rebaseMerge,
    }.contains(tab.snapshot.state);
    final canSkip =
        isRebase ||
        tab.snapshot.state == RepositoryState.cherryPick ||
        tab.snapshot.state == RepositoryState.revert;
    final canControl =
        isRebase ||
        tab.snapshot.state == RepositoryState.merge ||
        tab.snapshot.state == RepositoryState.cherryPick ||
        tab.snapshot.state == RepositoryState.revert;
    final stateLabel = switch (tab.snapshot.state) {
      RepositoryState.merge => strings.text('Merge 진행 중', 'Merge in progress'),
      RepositoryState.rebase ||
      RepositoryState.rebaseInteractive ||
      RepositoryState.rebaseMerge => strings.text(
        'Rebase 진행 중',
        'Rebase in progress',
      ),
      RepositoryState.cherryPick => strings.text(
        'Cherry-pick 진행 중',
        'Cherry-pick in progress',
      ),
      RepositoryState.revert => strings.text(
        'Revert 진행 중',
        'Revert in progress',
      ),
      _ => tab.snapshot.state.name,
    };
    Future<void> run(
      String label,
      Future<OperationResult> Function(String) action,
    ) async {
      try {
        await controller.runOperation(label, action, reloadHistory: true);
      } catch (error) {
        onError(error);
      }
    }

    Future<OperationResult> control(String path, SequenceControl action) {
      if (isRebase) {
        final rebaseAction = switch (action) {
          SequenceControl.continue_ => RebaseControl.continue_,
          SequenceControl.skip => RebaseControl.skip,
          SequenceControl.abort => RebaseControl.abort,
        };
        return git_api.controlRebase(path: path, action: rebaseAction);
      }
      return switch (tab.snapshot.state) {
        RepositoryState.cherryPick => git_api.controlCherryPick(
          path: path,
          action: action,
        ),
        RepositoryState.revert => git_api.controlRevert(
          path: path,
          action: action,
        ),
        _ => git_api.controlMerge(
          path: path,
          action: action == SequenceControl.continue_
              ? MergeControl.continue_
              : MergeControl.abort,
        ),
      };
    }

    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(stateLabel)),
            if (canControl)
              TextButton(
                onPressed: tab.busy
                    ? null
                    : () => unawaited(
                        run(
                          'Continue',
                          (path) => control(path, SequenceControl.continue_),
                        ),
                      ),
                child: Text(strings.continueAction),
              ),
            if (canSkip)
              TextButton(
                onPressed: tab.busy
                    ? null
                    : () => unawaited(
                        run(
                          'Skip commit',
                          (path) => control(path, SequenceControl.skip),
                        ),
                      ),
                child: Text(strings.skip),
              ),
            if (canControl)
              TextButton(
                onPressed: tab.busy
                    ? null
                    : () => unawaited(
                        run(
                          'Abort',
                          (path) => control(path, SequenceControl.abort),
                        ),
                      ),
                child: Text(strings.abort),
              ),
          ],
        ),
      ),
    );
  }
}

class _RepositorySidebar extends ConsumerWidget {
  const _RepositorySidebar({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SubmodulePanel(strings: strings, tab: tab, onError: onError),
        const Divider(height: 1),
        Expanded(
          child: _VirtualSidebarList(
            strings: strings,
            tab: tab,
            onCreateBranch: () => _createBranch(context, ref),
            onSaveStash: () => _saveStash(context, ref),
            onSwitchBranch: (branch) => _switchBranch(ref, branch),
            onTrackRemote: (branch) => _trackRemote(context, ref, branch),
            onManageRemotes: () => showDialog<void>(
              context: context,
              builder: (context) => _RemoteSettingsDialog(
                strings: strings,
                repositoryPath: tab.snapshot.workdir,
              ),
            ),
            onBranchAction: (branch, action) =>
                _branchAction(context, ref, branch, action),
            onShowStash: (stash) => _showStash(context, stash),
            onStashAction: (stash, action) =>
                _stashAction(context, ref, stash, action),
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    WidgetRef ref,
    String label,
    Future<OperationResult> Function(String) action,
  ) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(label, action, reloadHistory: true);
    } catch (error) {
      onError(error);
    }
  }

  Future<void> _createBranch(BuildContext context, WidgetRef ref) async {
    final name = await _textPrompt(
      context,
      title: strings.createBranch,
      label: strings.branches,
    );
    if (name == null) return;
    await _run(
      ref,
      'Create branch',
      (path) => git_api.createBranch(path: path, name: name, checkout: true),
    );
  }

  Future<void> _switchBranch(WidgetRef ref, BranchInfo branch) => _run(
    ref,
    'Switch branch',
    (path) => git_api.switchBranch(path: path, name: branch.name),
  );

  Future<void> _trackRemote(
    BuildContext context,
    WidgetRef ref,
    BranchInfo branch,
  ) async {
    final suggested = branch.name.contains('/')
        ? branch.name.substring(branch.name.indexOf('/') + 1)
        : branch.name;
    final localName = await _textPrompt(
      context,
      title: strings.text('Tracking 브랜치 만들기', 'Create tracking branch'),
      label: strings.localBranch,
      initialValue: suggested,
    );
    if (localName == null || localName.trim().isEmpty) return;
    await _run(
      ref,
      'Track ${branch.name}',
      (path) => git_api.createTrackingBranch(
        path: path,
        remoteBranch: branch.name,
        localBranch: localName.trim(),
      ),
    );
  }

  Future<void> _branchAction(
    BuildContext context,
    WidgetRef ref,
    BranchInfo branch,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        final name = await _textPrompt(
          context,
          title: 'Rename branch',
          label: branch.name,
        );
        if (name != null) {
          await _run(
            ref,
            'Rename branch',
            (path) => git_api.renameBranch(
              path: path,
              oldName: branch.name,
              newName: name,
            ),
          );
        }
      case 'delete':
        if (await _confirmTyped(
          context,
          title: 'Delete branch',
          value: branch.name,
        )) {
          await _run(
            ref,
            'Delete branch',
            (path) => git_api.deleteLocalBranch(
              path: path,
              name: branch.name,
              force: true,
            ),
          );
        }
      case 'merge':
        await _run(
          ref,
          'Merge',
          (path) => git_api.mergeBranch(path: path, target: branch.name),
        );
      case 'rebase':
        await _run(
          ref,
          'Rebase',
          (path) => git_api.rebaseBranch(path: path, upstream: branch.name),
        );
      case 'interactive':
        try {
          final plan = await git_api.prepareInteractiveRebase(
            path: tab.snapshot.workdir,
            upstream: branch.name,
          );
          if (!context.mounted) return;
          final edited = await showDialog<RebasePlan>(
            context: context,
            builder: (_) => _InteractiveRebaseDialog(plan: plan),
          );
          if (edited != null) {
            await _run(
              ref,
              'Interactive rebase',
              (path) =>
                  git_api.startInteractiveRebase(path: path, plan: edited),
            );
          }
        } catch (error) {
          onError(error);
        }
    }
  }

  Future<void> _saveStash(BuildContext context, WidgetRef ref) async {
    final message = await _textPrompt(
      context,
      title: 'Create stash',
      label: 'Message',
      allowEmpty: true,
    );
    if (message == null) return;
    await _run(
      ref,
      'Create stash',
      (path) => git_api.stashSave(
        path: path,
        message: message,
        includeUntracked: true,
      ),
    );
  }

  Future<void> _showStash(BuildContext context, StashEntry stash) async {
    try {
      final diff = await git_api.getStashDiff(
        path: tab.snapshot.workdir,
        index: stash.index,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(stash.message),
          content: SizedBox(
            width: 900,
            height: 560,
            child: _VirtualTextView(
              key: const ValueKey('virtualized-stash-diff'),
              content: diff,
              padding: const EdgeInsets.all(10),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.close),
            ),
          ],
        ),
      );
    } catch (error) {
      onError(error);
    }
  }

  Future<void> _stashAction(
    BuildContext context,
    WidgetRef ref,
    StashEntry stash,
    String action,
  ) async {
    if (action == 'drop' &&
        !await _confirmTyped(
          context,
          title: 'Drop stash',
          value: 'stash@{${stash.index}}',
        )) {
      return;
    }
    await _run(
      ref,
      'Stash $action',
      (path) => action == 'drop'
          ? git_api.stashDrop(path: path, index: stash.index)
          : git_api.stashApply(
              path: path,
              index: stash.index,
              pop: action == 'pop',
            ),
    );
  }
}

enum _SidebarSection { branches, remotes, stashes }

sealed class _SidebarListItem {
  const _SidebarListItem();
}

class _SidebarSectionItem extends _SidebarListItem {
  const _SidebarSectionItem(this.title, this.section);
  final String title;
  final _SidebarSection section;
}

class _SidebarBranchItem extends _SidebarListItem {
  const _SidebarBranchItem(this.branch);
  final BranchInfo branch;
}

class _SidebarRemoteItem extends _SidebarListItem {
  const _SidebarRemoteItem(this.branch);
  final BranchInfo branch;
}

class _SidebarRemoteHeaderItem extends _SidebarListItem {
  const _SidebarRemoteHeaderItem(this.name);
  final String name;
}

class _SidebarStashItem extends _SidebarListItem {
  const _SidebarStashItem(this.stash);
  final StashEntry stash;
}

class _SidebarGapItem extends _SidebarListItem {
  const _SidebarGapItem();
}

class _SidebarEmptyItem extends _SidebarListItem {
  const _SidebarEmptyItem();
}

typedef _BranchActionCallback = void Function(BranchInfo branch, String action);
typedef _StashActionCallback = void Function(StashEntry stash, String action);

class _SubmodulePanel extends ConsumerStatefulWidget {
  const _SubmodulePanel({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  ConsumerState<_SubmodulePanel> createState() => _SubmodulePanelState();
}

class _SubmodulePanelState extends ConsumerState<_SubmodulePanel> {
  bool expanded = false;
  bool loading = false;
  List<SubmoduleInfo> modules = const [];
  String? nextCursor;
  int total = 0;
  final selected = <String>{};

  @override
  void didUpdateWidget(covariant _SubmodulePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (expanded &&
        oldWidget.tab.snapshot.generation != widget.tab.snapshot.generation &&
        !loading) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool more = false}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final page = more && nextCursor != null
          ? await git_api.listSubmodulesCursor(
              path: widget.tab.snapshot.workdir,
              cursor: nextCursor!,
              limit: 100,
            )
          : await git_api.listSubmodules(
              path: widget.tab.snapshot.workdir,
              recursive: true,
              limit: 100,
            );
      if (!mounted) return;
      setState(() {
        modules = more ? [...modules, ...page.submodules] : page.submodules;
        selected.removeWhere(
          (path) => !modules.any((module) => module.path == path),
        );
        nextCursor = page.nextCursor;
        total = page.totalSubmodules;
        loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => loading = false);
      widget.onError(error);
    }
  }

  Future<void> _run(
    String label,
    Future<OperationResult> Function(String) action,
  ) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(label, action, reloadHistory: true);
      await _load();
    } catch (error) {
      widget.onError(error);
    }
  }

  List<String> get _paths => selected.toList(growable: false);

  Future<void> _add() async {
    final options = await showDialog<SubmoduleAddOptions>(
      context: context,
      builder: (_) => _AddSubmoduleDialog(strings: widget.strings),
    );
    if (options == null) return;
    await _run(
      'Add submodule',
      (path) => git_api.addSubmodule(path: path, options: options),
    );
  }

  Future<void> _remove(SubmoduleInfo module) async {
    try {
      final preview = await git_api.previewRemoveSubmodule(
        path: widget.tab.snapshot.workdir,
        submodulePath: module.path,
      );
      if (!mounted ||
          !await _confirmTyped(
            context,
            title: widget.strings.removeSubmodule,
            value: module.path,
          )) {
        return;
      }
      await _run(
        'Remove submodule ${module.path}',
        (path) => git_api.removeSubmodule(
          path: path,
          submodulePath: module.path,
          expectedFingerprint: preview.fingerprint,
          confirmation: module.path,
        ),
      );
    } catch (error) {
      widget.onError(error);
    }
  }

  Future<void> _open(SubmoduleInfo module) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .openPath(p.join(widget.tab.snapshot.workdir, module.path));
    } catch (error) {
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
          title: Text('${strings.submodules}${total > 0 ? ' ($total)' : ''}'),
          onTap: () {
            setState(() => expanded = !expanded);
            if (expanded && modules.isEmpty) unawaited(_load());
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: strings.add,
                onPressed: widget.tab.busy ? null : _add,
                icon: const Icon(Icons.add, size: 18),
              ),
              PopupMenuButton<String>(
                enabled: !widget.tab.busy,
                onSelected: (action) async {
                  switch (action) {
                    case 'init':
                      await _run(
                        'Initialize submodules',
                        (path) => git_api.initSubmodules(
                          path: path,
                          paths: _paths,
                          recursive: true,
                        ),
                      );
                    case 'update':
                      await _run(
                        'Update submodules',
                        (path) => git_api.updateSubmodules(
                          path: path,
                          paths: _paths,
                          recursive: true,
                          mode: SubmoduleUpdateMode.recorded,
                        ),
                      );
                    case 'remote':
                      if (!await _confirmAction(
                        context,
                        strings: strings,
                        title: strings.updateRemote,
                        message: strings.text(
                          '선택한 Submodule을 설정된 원격 브랜치의 최신 커밋으로 이동합니다.',
                          'Move the selected submodules to the latest configured remote commits.',
                        ),
                      )) {
                        return;
                      }
                      await _run(
                        'Update submodules from remotes',
                        (path) => git_api.updateSubmodules(
                          path: path,
                          paths: _paths,
                          recursive: true,
                          mode: SubmoduleUpdateMode.remote,
                        ),
                      );
                    case 'sync':
                      await _run(
                        'Synchronize submodules',
                        (path) => git_api.syncSubmodules(
                          path: path,
                          paths: _paths,
                          recursive: true,
                        ),
                      );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'init', child: Text(strings.initialize)),
                  PopupMenuItem(
                    value: 'update',
                    child: Text(strings.updateRecorded),
                  ),
                  PopupMenuItem(
                    value: 'remote',
                    child: Text(strings.updateRemote),
                  ),
                  PopupMenuItem(
                    value: 'sync',
                    child: Text(strings.synchronize),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (expanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: loading && modules.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: modules.length + (nextCursor == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == modules.length) {
                        return TextButton(
                          onPressed: loading ? null : () => _load(more: true),
                          child: Text(strings.loadMore),
                        );
                      }
                      final module = modules[index];
                      final initialized =
                          module.state != SubmoduleState.uninitialized &&
                          module.state != SubmoduleState.missing;
                      final statusLabel = switch (module.state) {
                        SubmoduleState.uninitialized => strings.text(
                          '초기화 안 됨',
                          'Uninitialized',
                        ),
                        SubmoduleState.clean => strings.text('정상', 'Clean'),
                        SubmoduleState.checkedOutDifferent => strings.text(
                          '다른 커밋',
                          'Different commit',
                        ),
                        SubmoduleState.modified => strings.text(
                          '수정됨',
                          'Modified',
                        ),
                        SubmoduleState.untracked => strings.text(
                          '미추적 파일',
                          'Untracked files',
                        ),
                        SubmoduleState.conflicted => strings.text(
                          '충돌',
                          'Conflicted',
                        ),
                        SubmoduleState.missing => strings.text(
                          '경로 없음',
                          'Missing',
                        ),
                      };
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(
                          left: 8.0 + module.depth * 14,
                          right: 4,
                        ),
                        leading: Checkbox(
                          value: selected.contains(module.path),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(module.path)
                                : selected.remove(module.path);
                          }),
                        ),
                        title: Text(
                          module.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$statusLabel · ${(module.headOid ?? module.indexOid ?? '--------').substring(0, 8)}',
                          maxLines: 1,
                        ),
                        onTap: initialized ? () => _open(module) : null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              value == 'open' ? _open(module) : _remove(module),
                          itemBuilder: (_) => [
                            if (initialized)
                              PopupMenuItem(
                                value: 'open',
                                child: Text(strings.openAsTab),
                              ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(strings.removeSubmodule),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

class _AddSubmoduleDialog extends StatefulWidget {
  const _AddSubmoduleDialog({required this.strings});
  final GitFrontStrings strings;

  @override
  State<_AddSubmoduleDialog> createState() => _AddSubmoduleDialogState();
}

class _AddSubmoduleDialogState extends State<_AddSubmoduleDialog> {
  final url = TextEditingController();
  final path = TextEditingController();
  final branch = TextEditingController();
  final depth = TextEditingController();

  @override
  void dispose() {
    url.dispose();
    path.dispose();
    branch.dispose();
    depth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.strings.text('Submodule 추가', 'Add submodule')),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: url,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.strings.repoUrl),
          ),
          TextField(
            controller: path,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.strings.destination),
          ),
          TextField(
            controller: branch,
            decoration: InputDecoration(labelText: widget.strings.branchOrTag),
          ),
          TextField(
            controller: depth,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: widget.strings.cloneDepth),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        onPressed: url.text.trim().isEmpty || path.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                SubmoduleAddOptions(
                  url: url.text.trim(),
                  path: path.text.trim(),
                  name: null,
                  branch: branch.text.trim().isEmpty
                      ? null
                      : branch.text.trim(),
                  depth: int.tryParse(depth.text.trim()),
                ),
              ),
        child: Text(widget.strings.add),
      ),
    ],
  );
}

class _VirtualSidebarList extends ConsumerStatefulWidget {
  const _VirtualSidebarList({
    required this.strings,
    required this.tab,
    required this.onCreateBranch,
    required this.onSaveStash,
    required this.onSwitchBranch,
    required this.onTrackRemote,
    required this.onManageRemotes,
    required this.onBranchAction,
    required this.onShowStash,
    required this.onStashAction,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final VoidCallback onCreateBranch;
  final VoidCallback onSaveStash;
  final ValueChanged<BranchInfo> onSwitchBranch;
  final ValueChanged<BranchInfo> onTrackRemote;
  final VoidCallback onManageRemotes;
  final _BranchActionCallback onBranchAction;
  final ValueChanged<StashEntry> onShowStash;
  final _StashActionCallback onStashAction;

  @override
  ConsumerState<_VirtualSidebarList> createState() =>
      _VirtualSidebarListState();
}

class _VirtualSidebarListState extends ConsumerState<_VirtualSidebarList> {
  late List<_SidebarListItem> _items;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _scrollController.addListener(_loadNearEnd);
  }

  void _loadNearEnd() {
    if (_scrollController.position.extentAfter < 500 &&
        widget.tab.nextBranchCursor != null &&
        !widget.tab.busy) {
      unawaited(ref.read(gitFrontProvider.notifier).loadMoreBranches());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VirtualSidebarList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab.visibleBranches, widget.tab.visibleBranches) ||
        !identical(
          oldWidget.tab.snapshot.stashes,
          widget.tab.snapshot.stashes,
        ) ||
        oldWidget.strings.locale.languageCode !=
            widget.strings.locale.languageCode) {
      _items = _buildItems();
    }
  }

  List<_SidebarListItem> _buildItems() {
    final locals = <BranchInfo>[];
    final remotes = <BranchInfo>[];
    for (final branch in widget.tab.visibleBranches) {
      (branch.isRemote ? remotes : locals).add(branch);
    }
    final remoteItems = <_SidebarListItem>[];
    final grouped = <String, List<BranchInfo>>{};
    for (final branch in remotes) {
      final separator = branch.name.indexOf('/');
      final remoteName = separator < 0
          ? widget.strings.remotes
          : branch.name.substring(0, separator);
      grouped.putIfAbsent(remoteName, () => []).add(branch);
    }
    for (final entry in grouped.entries) {
      remoteItems.add(_SidebarRemoteHeaderItem(entry.key));
      remoteItems.addAll(entry.value.map(_SidebarRemoteItem.new));
    }
    return [
      _SidebarSectionItem(widget.strings.branches, _SidebarSection.branches),
      ...locals.map(_SidebarBranchItem.new),
      const _SidebarGapItem(),
      _SidebarSectionItem(widget.strings.remotes, _SidebarSection.remotes),
      ...remoteItems,
      const _SidebarGapItem(),
      _SidebarSectionItem(widget.strings.stashes, _SidebarSection.stashes),
      if (widget.tab.snapshot.stashes.isEmpty)
        const _SidebarEmptyItem()
      else
        ...widget.tab.snapshot.stashes.map(_SidebarStashItem.new),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return ListView.builder(
      key: const ValueKey('virtualized-repository-sidebar'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      cacheExtent: 180,
      itemCount: _items.length,
      itemExtentBuilder: (index, _) => switch (_items[index]) {
        _SidebarSectionItem() => 34,
        _SidebarBranchItem(:final branch) =>
          branch.ahead == 0 && branch.behind == 0 ? 48 : 60,
        _SidebarRemoteItem() => 48,
        _SidebarRemoteHeaderItem() => 32,
        _SidebarStashItem() => 56,
        _SidebarGapItem() => 10,
        _SidebarEmptyItem() => 36,
      },
      itemBuilder: (context, index) => switch (_items[index]) {
        _SidebarSectionItem(:final title, :final section) => _SidebarHeader(
          title: title,
          action: switch (section) {
            _SidebarSection.branches => IconButton(
              tooltip: widget.strings.createBranch,
              icon: const Icon(Icons.add, size: 18),
              onPressed: tab.busy ? null : widget.onCreateBranch,
            ),
            _SidebarSection.stashes => IconButton(
              tooltip: widget.strings.stash,
              icon: const Icon(Icons.add, size: 18),
              onPressed: tab.busy ? null : widget.onSaveStash,
            ),
            _SidebarSection.remotes => IconButton(
              tooltip: widget.strings.manageRemotes,
              icon: const Icon(Icons.settings_outlined, size: 18),
              onPressed: tab.busy ? null : widget.onManageRemotes,
            ),
          },
        ),
        _SidebarBranchItem(:final branch) => _BranchTile(
          branch: branch,
          tab: tab,
          onTap: branch.isHead || tab.busy
              ? null
              : () => widget.onSwitchBranch(branch),
          onAction: (action) => widget.onBranchAction(branch, action),
        ),
        _SidebarRemoteItem(:final branch) => Tooltip(
          message: branch.name,
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 24, right: 4),
            leading: const Icon(Icons.call_split, size: 16),
            title: Text(
              branch.name.contains('/')
                  ? branch.name.substring(branch.name.indexOf('/') + 1)
                  : branch.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: tab.busy ? null : () => widget.onTrackRemote(branch),
          ),
        ),
        _SidebarRemoteHeaderItem(:final name) => Padding(
          padding: const EdgeInsets.only(left: 10, top: 6),
          child: Row(
            children: [
              const Icon(Icons.cloud_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
        _SidebarStashItem(:final stash) => ListTile(
          dense: true,
          leading: CircleAvatar(radius: 11, child: Text('${stash.index}')),
          title: Text(
            stash.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onShowStash(stash),
          trailing: PopupMenuButton<String>(
            onSelected: (action) => widget.onStashAction(stash, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'apply', child: Text('Apply')),
              PopupMenuItem(value: 'pop', child: Text('Pop')),
              PopupMenuItem(value: 'drop', child: Text('Drop…')),
            ],
          ),
        ),
        _SidebarGapItem() => const SizedBox.shrink(),
        _SidebarEmptyItem() => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text('—'),
        ),
      },
    );
  }
}

class _ChangesPanel extends ConsumerWidget {
  const _ChangesPanel({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab.visibleChanges.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 44),
            const SizedBox(height: 12),
            Text(strings.workingTreeClean),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: _VirtualChangeList(
            strings: strings,
            tab: tab,
            onError: onError,
          ),
        ),
        const Divider(height: 1),
        _CommitBox(strings: strings, tab: tab, onError: onError),
      ],
    );
  }
}

sealed class _ChangeListItem {
  const _ChangeListItem();
}

class _ChangeSectionItem extends _ChangeListItem {
  const _ChangeSectionItem(this.title, this.count);
  final String title;
  final int count;
}

class _ChangeFileItem extends _ChangeListItem {
  const _ChangeFileItem(this.file, this.staged);
  final FileChange file;
  final bool staged;
}

class _VirtualChangeList extends ConsumerStatefulWidget {
  const _VirtualChangeList({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  ConsumerState<_VirtualChangeList> createState() => _VirtualChangeListState();
}

class _VirtualChangeListState extends ConsumerState<_VirtualChangeList> {
  late List<_ChangeListItem> _items;
  final Set<String> _selected = {};
  final ScrollController _scrollController = ScrollController();

  String _selectionKey(FileChange file, bool staged) =>
      '${staged ? 'S' : 'U'}\u0000${file.path}';

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _scrollController.addListener(_loadNearEnd);
  }

  void _loadNearEnd() {
    if (_scrollController.position.extentAfter < 600 &&
        widget.tab.nextChangeCursor != null &&
        !widget.tab.busy) {
      unawaited(ref.read(gitFrontProvider.notifier).loadMoreChanges());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VirtualChangeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab.visibleChanges, widget.tab.visibleChanges) ||
        oldWidget.strings.locale.languageCode !=
            widget.strings.locale.languageCode) {
      _items = _buildItems();
      final available = _items
          .whereType<_ChangeFileItem>()
          .map((item) => _selectionKey(item.file, item.staged))
          .toSet();
      _selected.removeWhere((key) => !available.contains(key));
    }
  }

  List<_ChangeListItem> _buildItems() {
    final conflicts = <FileChange>[];
    final staged = <FileChange>[];
    final unstaged = <FileChange>[];
    for (final file in widget.tab.visibleChanges) {
      if (file.conflicted) {
        conflicts.add(file);
      } else {
        if (file.staged != ChangeKind.none) staged.add(file);
        if (file.unstaged != ChangeKind.none) unstaged.add(file);
      }
    }
    final items = <_ChangeListItem>[];
    void addGroup(String title, List<FileChange> files, bool isStaged) {
      if (files.isEmpty) return;
      items.add(_ChangeSectionItem(title, files.length));
      items.addAll(files.map((file) => _ChangeFileItem(file, isStaged)));
    }

    addGroup(widget.strings.conflicts, conflicts, false);
    addGroup(widget.strings.staged, staged, true);
    addGroup(widget.strings.unstaged, unstaged, false);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final selectedItems = _items
        .whereType<_ChangeFileItem>()
        .where(
          (item) => _selected.contains(_selectionKey(item.file, item.staged)),
        )
        .toList();
    final stagedPaths = selectedItems
        .where((item) => item.staged)
        .map((item) => item.file.path)
        .toSet()
        .toList();
    final unstagedPaths = selectedItems
        .where((item) => !item.staged)
        .map((item) => item.file.path)
        .toSet()
        .toList();
    final untrackedPaths = selectedItems
        .where((item) => !item.staged && item.file.untracked)
        .map((item) => item.file.path)
        .toSet()
        .toList();
    return Column(
      children: [
        if (_selected.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text(widget.strings.selectedCount(_selected.length)),
                  const Spacer(),
                  if (unstagedPaths.isNotEmpty)
                    TextButton.icon(
                      onPressed: widget.tab.busy
                          ? null
                          : () => _runBulk(
                              'Stage files',
                              (path) => git_api.stagePaths(
                                path: path,
                                paths: unstagedPaths,
                              ),
                            ),
                      icon: const Icon(Icons.add, size: 17),
                      label: Text(widget.strings.stage),
                    ),
                  if (stagedPaths.isNotEmpty)
                    TextButton.icon(
                      onPressed: widget.tab.busy
                          ? null
                          : () => _runBulk(
                              'Unstage files',
                              (path) => git_api.unstagePaths(
                                path: path,
                                paths: stagedPaths,
                              ),
                            ),
                      icon: const Icon(Icons.remove, size: 17),
                      label: Text(widget.strings.unstage),
                    ),
                  if (untrackedPaths.isNotEmpty)
                    IconButton(
                      tooltip: widget.strings.intentToAdd,
                      onPressed: widget.tab.busy
                          ? null
                          : () => _runBulk(
                              'Intent to add',
                              (path) => git_api.intentToAdd(
                                path: path,
                                paths: untrackedPaths,
                              ),
                            ),
                      icon: const Icon(Icons.pending_outlined, size: 19),
                    ),
                  IconButton(
                    tooltip: widget.strings.clearSelection,
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('virtualized-change-list'),
            controller: _scrollController,
            cacheExtent: 180,
            itemCount: _items.length,
            itemExtentBuilder: (index, _) => switch (_items[index]) {
              _ChangeSectionItem() => 42,
              _ChangeFileItem(:final file) => file.oldPath == null ? 52 : 60,
            },
            itemBuilder: (context, index) => switch (_items[index]) {
              _ChangeSectionItem(:final title, :final count) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Text(
                  '$title · $count',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              _ChangeFileItem(:final file, :final staged) => _ChangeTile(
                key: ValueKey('${staged ? 'staged' : 'unstaged'}:${file.path}'),
                file: file,
                staged: staged,
                tab: widget.tab,
                checked: _selected.contains(_selectionKey(file, staged)),
                onChecked: (checked) => setState(() {
                  final key = _selectionKey(file, staged);
                  checked ? _selected.add(key) : _selected.remove(key);
                }),
                onError: widget.onError,
              ),
            },
          ),
        ),
      ],
    );
  }

  Future<void> _runBulk(
    String label,
    Future<OperationResult> Function(String path) action,
  ) async {
    try {
      await ref.read(gitFrontProvider.notifier).runOperation(label, action);
      if (mounted) setState(_selected.clear);
    } catch (error) {
      widget.onError(error);
    }
  }
}

class _ChangeTile extends ConsumerWidget {
  const _ChangeTile({
    super.key,
    required this.file,
    required this.staged,
    required this.tab,
    required this.checked,
    required this.onChecked,
    required this.onError,
  });

  final FileChange file;
  final bool staged;
  final RepoTabState tab;
  final bool checked;
  final ValueChanged<bool> onChecked;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        tab.selectedFile?.path == file.path && tab.selectedFileStaged == staged;
    final kind = file.conflicted
        ? ChangeKind.conflicted
        : staged
        ? file.staged
        : file.unstaged;
    return ListTile(
      selected: selected,
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: checked,
            onChanged: tab.busy ? null : (value) => onChecked(value ?? false),
            visualDensity: VisualDensity.compact,
          ),
          _StatusBadge(kind: kind),
        ],
      ),
      title: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: file.oldPath == null ? null : Text('← ${file.oldPath}'),
      onTap: () => unawaited(
        ref.read(gitFrontProvider.notifier).selectFile(file, staged: staged),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (file.conflicted)
            IconButton(
              tooltip: 'Resolve',
              icon: const Icon(Icons.build_outlined, size: 18),
              onPressed: () => _showConflictEditor(context, ref),
            )
          else
            IconButton(
              tooltip: staged ? 'Unstage' : 'Stage',
              icon: Icon(staged ? Icons.remove : Icons.add, size: 18),
              onPressed: tab.busy ? null : () => _toggleStage(ref),
            ),
          if (!staged)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'discard') _discard(context, ref);
                if (value == 'external') _openExternal(ref);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'external',
                  child: Text(
                    GitFrontStrings(
                      resolveLocale(
                        context,
                        ref.read(gitFrontProvider).language,
                      ),
                    ).openExternal,
                  ),
                ),
                const PopupMenuItem(value: 'discard', child: Text('Discard…')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _run(
    WidgetRef ref,
    String label,
    Future<OperationResult> Function(String) action,
  ) async {
    try {
      await ref.read(gitFrontProvider.notifier).runOperation(label, action);
    } catch (error) {
      onError(error);
    }
  }

  Future<void> _toggleStage(WidgetRef ref) => _run(
    ref,
    staged ? 'Unstage file' : 'Stage file',
    (path) => staged
        ? git_api.unstagePaths(path: path, paths: [file.path])
        : git_api.stagePaths(path: path, paths: [file.path]),
  );

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: Text(
              file.untracked
                  ? '${file.path}\n\nThe file will be moved to the Recycle Bin.'
                  : '${file.path}\n\nTracked changes cannot be recovered by GitFront.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _run(
      ref,
      'Discard file',
      (path) => git_api.discardFile(
        path: path,
        filePath: file.path,
        untracked: file.untracked,
      ),
    );
  }

  Future<void> _openExternal(WidgetRef ref) {
    final settings = ref.read(gitFrontProvider);
    return _run(
      ref,
      'Open external editor',
      (path) => git_api.openExternalFile(
        path: path,
        filePath: file.path,
        editor: settings.externalEditor,
        customExecutable: settings.customEditorExecutable.isEmpty
            ? null
            : settings.customEditorExecutable,
      ),
    );
  }

  Future<void> _showConflictEditor(BuildContext context, WidgetRef ref) async {
    try {
      final conflict = await git_api.loadConflict(
        path: tab.snapshot.workdir,
        filePath: file.path,
      );
      if (!context.mounted) return;
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ConflictEditor(conflict: conflict),
      );
      if (result != null) {
        await _run(
          ref,
          'Resolve conflict',
          (path) => git_api.saveConflictResolution(
            path: path,
            filePath: file.path,
            content: result,
          ),
        );
      }
    } catch (error) {
      onError(error);
    }
  }
}

class _CommitBox extends ConsumerStatefulWidget {
  const _CommitBox({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  ConsumerState<_CommitBox> createState() => _CommitBoxState();
}

class _CommitBoxState extends ConsumerState<_CommitBox> {
  final _message = TextEditingController();
  final _authorName = TextEditingController();
  final _authorEmail = TextEditingController();
  final _authorDate = TextEditingController();
  bool _advanced = false;
  bool _amend = false;
  bool _signoff = false;
  bool _allowEmpty = false;
  CommitSigningMode _signing = CommitSigningMode.useConfig;
  String _commitKind = 'normal';
  String? _targetCommit;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    unawaited(_loadDefaults());
  }

  void _restoreDraft() {
    final draft = ref
        .read(gitFrontProvider.notifier)
        .commitDraft(widget.tab.snapshot.workdir);
    if (draft.isNotEmpty) _message.text = draft;
  }

  @override
  void didUpdateWidget(covariant _CommitBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.snapshot.workdir != widget.tab.snapshot.workdir) {
      _message.clear();
      _authorName.clear();
      _authorEmail.clear();
      _authorDate.clear();
      _amend = false;
      _signoff = false;
      _allowEmpty = false;
      _signing = CommitSigningMode.useConfig;
      _commitKind = 'normal';
      _targetCommit = null;
      _restoreDraft();
      unawaited(_loadDefaults());
    }
  }

  Future<void> _loadDefaults() async {
    final repository = widget.tab.snapshot.workdir;
    try {
      final defaults = await git_api.loadCommitDefaults(path: repository);
      if (!mounted || widget.tab.snapshot.workdir != repository) return;
      if (_message.text.isEmpty && defaults.template.isNotEmpty) {
        _message.text = defaults.template;
      }
    } catch (_) {
      // A missing or unreadable template must not block normal commits.
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _message.dispose();
    _authorName.dispose();
    _authorEmail.dispose();
    _authorDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stagedCount = widget.tab.visibleStagedChangeCount;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          TextField(
            controller: _message,
            enabled: _commitKind == 'normal',
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: widget.strings.commitMessage,
              isDense: true,
            ),
            onChanged: _scheduleDraftSave,
            onSubmitted: (_) => _commit(stagedCount),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _advanced = !_advanced),
              icon: Icon(
                _advanced ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(widget.strings.commitOptions),
            ),
          ),
          if (_advanced) ...[
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                FilterChip(
                  label: Text(widget.strings.amend),
                  selected: _amend,
                  onSelected: (value) => setState(() {
                    _amend = value;
                    if (value) {
                      _commitKind = 'normal';
                      _targetCommit = null;
                    }
                  }),
                ),
                FilterChip(
                  label: Text(widget.strings.signOff),
                  selected: _signoff,
                  onSelected: (value) => setState(() => _signoff = value),
                ),
                FilterChip(
                  label: Text(widget.strings.allowEmpty),
                  selected: _allowEmpty,
                  onSelected: (value) => setState(() => _allowEmpty = value),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'normal',
                  label: Text(widget.strings.normalCommit),
                ),
                ButtonSegment(
                  value: 'fixup',
                  label: Text(widget.strings.fixupCommit),
                ),
                ButtonSegment(
                  value: 'squash',
                  label: Text(widget.strings.squashCommit),
                ),
              ],
              selected: {_commitKind},
              onSelectionChanged: (value) => setState(() {
                _commitKind = value.first;
                if (_commitKind != 'normal') _amend = false;
                _targetCommit ??= widget.tab.commits.firstOrNull?.oid;
              }),
            ),
            if (_commitKind != 'normal') ...[
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _targetCommit,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: widget.strings.targetCommit,
                ),
                items: widget.tab.commits
                    .take(200)
                    .map(
                      (commit) => DropdownMenuItem(
                        value: commit.oid,
                        child: Text(
                          '${commit.shortOid}  ${commit.summary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _targetCommit = value),
              ),
            ],
            const SizedBox(height: 6),
            DropdownButtonFormField<CommitSigningMode>(
              initialValue: _signing,
              isDense: true,
              decoration: InputDecoration(labelText: widget.strings.signing),
              items: [
                DropdownMenuItem(
                  value: CommitSigningMode.useConfig,
                  child: Text(widget.strings.useGitConfig),
                ),
                DropdownMenuItem(
                  value: CommitSigningMode.sign,
                  child: Text(widget.strings.signThisCommit),
                ),
                DropdownMenuItem(
                  value: CommitSigningMode.doNotSign,
                  child: Text(widget.strings.doNotSign),
                ),
              ],
              onChanged: (value) => setState(
                () => _signing = value ?? CommitSigningMode.useConfig,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _authorName,
                    decoration: InputDecoration(
                      labelText: widget.strings.authorName,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _authorEmail,
                    decoration: InputDecoration(
                      labelText: widget.strings.authorEmail,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _authorDate,
              decoration: InputDecoration(
                labelText: widget.strings.authorDate,
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  ((!_allowEmpty && !_amend && stagedCount == 0) ||
                      (_commitKind != 'normal' && _targetCommit == null) ||
                      widget.tab.busy)
                  ? null
                  : () => _commit(stagedCount),
              icon: const Icon(Icons.commit, size: 18),
              label: Text('${widget.strings.commit} · $stagedCount'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commit(int stagedCount) async {
    if ((!_allowEmpty && !_amend && stagedCount == 0) ||
        (_commitKind == 'normal' && _message.text.trim().isEmpty) ||
        (_commitKind != 'normal' && _targetCommit == null)) {
      return;
    }
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Commit',
            (path) => git_api.createCommitWithOptions(
              path: path,
              options: CommitOptions(
                message: _commitKind == 'normal' ? _message.text.trim() : null,
                amend: _amend,
                signoff: _signoff,
                signing: _signing,
                authorName: _authorName.text.trim().isEmpty
                    ? null
                    : _authorName.text.trim(),
                authorEmail: _authorEmail.text.trim().isEmpty
                    ? null
                    : _authorEmail.text.trim(),
                authoredAt: _authorDate.text.trim().isEmpty
                    ? null
                    : _authorDate.text.trim(),
                allowEmpty: _allowEmpty,
                fixupTarget: _commitKind == 'fixup' ? _targetCommit : null,
                squashTarget: _commitKind == 'squash' ? _targetCommit : null,
              ),
            ),
            reloadHistory: true,
          );
      _draftTimer?.cancel();
      _message.clear();
      await ref
          .read(gitFrontProvider.notifier)
          .saveCommitDraft(widget.tab.snapshot.workdir, '');
      setState(() {
        _amend = false;
        _allowEmpty = false;
        _commitKind = 'normal';
        _targetCommit = null;
      });
    } catch (error) {
      widget.onError(error);
    }
  }

  void _scheduleDraftSave(String message) {
    _draftTimer?.cancel();
    final repository = widget.tab.snapshot.workdir;
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        ref
            .read(gitFrontProvider.notifier)
            .saveCommitDraft(repository, message),
      );
    });
  }
}

class _HistoryPanel extends ConsumerWidget {
  const _HistoryPanel({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab.commits.isEmpty) {
      if (tab.busy) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('No commits'));
    }
    return ListView.builder(
      key: const ValueKey('virtualized-commit-list'),
      cacheExtent: 192,
      itemExtent: 64,
      itemCount: tab.commits.length + (tab.nextCursor == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == tab.commits.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: tab.busy
                  ? null
                  : () => unawaited(
                      ref.read(gitFrontProvider.notifier).loadMoreCommits(),
                    ),
              child: Text(strings.loadMore),
            ),
          );
        }
        final commit = tab.commits[index];
        return _CommitTile(
          key: ValueKey('commit:${commit.oid}'),
          strings: strings,
          tab: tab,
          commit: commit,
          onError: onError,
        );
      },
    );
  }
}

class _CommitTile extends ConsumerStatefulWidget {
  const _CommitTile({
    super.key,
    required this.strings,
    required this.tab,
    required this.commit,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final CommitSummary commit;
  final ValueChanged<Object> onError;

  @override
  ConsumerState<_CommitTile> createState() => _CommitTileState();
}

class _CommitTileState extends ConsumerState<_CommitTile> {
  final _menuController = MenuController();
  final _focusNode = FocusNode();
  CherryPickApplicability? _cherryPickApplicability;
  String? _assessedHeadOid;
  bool _checkingCherryPick = false;

  bool get _canMutate =>
      !widget.tab.busy && widget.tab.snapshot.state == RepositoryState.clean;

  bool get _canMoveBranch =>
      _canMutate &&
      widget.tab.snapshot.headName != null &&
      widget.tab.snapshot.headOid != widget.commit.oid;

  bool get _canCherryPick =>
      _canMutate &&
      !_checkingCherryPick &&
      _cherryPickApplicability != CherryPickApplicability.alreadyApplied;

  String get _cherryPickLabel {
    if (_checkingCherryPick) return widget.strings.cherryPickChecking;
    return switch (_cherryPickApplicability) {
      CherryPickApplicability.alreadyApplied =>
        widget.strings.cherryPickAlreadyApplied,
      CherryPickApplicability.conflicts => widget.strings.cherryPickConflicts,
      _ => widget.strings.cherryPick,
    };
  }

  @override
  void didUpdateWidget(covariant _CommitTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.snapshot.headOid != widget.tab.snapshot.headOid ||
        oldWidget.commit.oid != widget.commit.oid) {
      _cherryPickApplicability = null;
      _assessedHeadOid = null;
      _checkingCherryPick = false;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commit = widget.commit;
    final strings = widget.strings;
    final selected = widget.tab.selectedCommit?.oid == commit.oid;
    final canCompare =
        !widget.tab.busy &&
        widget.tab.snapshot.headOid != null &&
        widget.tab.snapshot.headOid != commit.oid;
    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        MenuItemButton(
          onPressed: _copyHash,
          child: Text(strings.copyCommitHash),
        ),
        MenuItemButton(
          onPressed: canCompare ? _compareWithHead : null,
          child: Text(strings.compareWithHead),
        ),
        const Divider(height: 1),
        MenuItemButton(
          onPressed: _canMutate ? _createBranch : null,
          child: Text(strings.createBranchHere),
        ),
        MenuItemButton(
          onPressed: _canMutate ? _createTag : null,
          child: Text(strings.createTagHere),
        ),
        MenuItemButton(
          onPressed: _canMutate ? _checkoutDetached : null,
          child: Text(strings.checkoutDetached),
        ),
        const Divider(height: 1),
        MenuItemButton(
          onPressed: _canCherryPick ? () => _runSequence(false) : null,
          child: Text(_cherryPickLabel),
        ),
        MenuItemButton(
          onPressed: _canMutate ? () => _runSequence(true) : null,
          child: Text(strings.revertCommit),
        ),
        MenuItemButton(
          onPressed: _canMoveBranch ? _rebaseOntoCommit : null,
          child: Text(strings.rebaseOntoCommit),
        ),
        SubmenuButton(
          menuChildren: _canMoveBranch
              ? [
                  MenuItemButton(
                    onPressed: () => _resetToCommit(ResetMode.soft),
                    child: Text(strings.softReset),
                  ),
                  MenuItemButton(
                    onPressed: () => _resetToCommit(ResetMode.mixed),
                    child: Text(strings.mixedReset),
                  ),
                  MenuItemButton(
                    onPressed: () => _resetToCommit(ResetMode.hard),
                    child: Text(strings.hardReset),
                  ),
                ]
              : const [],
          child: Text(strings.resetCurrentBranch),
        ),
      ],
      builder: (context, controller, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): () {
            _openMenu(controller);
          },
        },
        child: Focus(
          focusNode: _focusNode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              _openMenu(controller, position: details.localPosition);
            },
            child: ListTile(
              selected: selected,
              dense: true,
              leading: _GraphDot(lane: commit.lane),
              title: Row(
                children: [
                  if (commit.references.isNotEmpty) ...[
                    Flexible(
                      flex: 2,
                      child: _CommitReferenceStrip(
                        references: commit.references,
                        strings: strings,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    flex: 3,
                    child: Text(
                      commit.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${commit.authorName}  ·  ${_formatTimestamp(commit.authoredAt.toInt())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: SizedBox(
                width: 128,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      commit.shortOid,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        tooltip: strings.commitActions,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () => _openMenu(controller),
                      ),
                    ),
                  ],
                ),
              ),
              onTap: () {
                _focusNode.requestFocus();
                unawaited(
                  ref.read(gitFrontProvider.notifier).selectCommit(commit),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _focusCommit() {
    _focusNode.requestFocus();
    ref.read(gitFrontProvider.notifier).focusCommit(widget.commit);
  }

  void _openMenu(MenuController controller, {Offset? position}) {
    _focusCommit();
    unawaited(_primeCherryPickAssessment());
    controller.open(position: position);
  }

  Future<void> _primeCherryPickAssessment() async {
    final headOid = widget.tab.snapshot.headOid;
    if (!_canMutate ||
        headOid == null ||
        widget.commit.parentOids.length > 1 ||
        (_assessedHeadOid == headOid && _cherryPickApplicability != null) ||
        _checkingCherryPick) {
      return;
    }
    setState(() => _checkingCherryPick = true);
    try {
      final result = await ref
          .read(gitFrontProvider.notifier)
          .assessCherryPick(widget.commit);
      if (!mounted || widget.tab.snapshot.headOid != headOid) return;
      setState(() {
        _cherryPickApplicability = result;
        _assessedHeadOid = headOid;
        _checkingCherryPick = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingCherryPick = false);
    }
  }

  Future<void> _copyHash() async {
    await Clipboard.setData(ClipboardData(text: widget.commit.oid));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.strings.hashCopied)));
  }

  void _compareWithHead() {
    unawaited(
      ref.read(gitFrontProvider.notifier).compareCommitWithHead(widget.commit),
    );
  }

  Future<void> _run(
    String label,
    Future<OperationResult> Function(String) action,
  ) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(label, action, reloadHistory: true);
    } catch (error) {
      widget.onError(error);
    }
  }

  Future<void> _createBranch() async {
    final result = await _showBranchAtCommitDialog(context, widget.strings);
    if (result == null) return;
    await _run(
      'Create branch at ${widget.commit.shortOid}',
      (path) => git_api.createBranch(
        path: path,
        name: result.name,
        startPoint: widget.commit.oid,
        checkout: result.checkout,
      ),
    );
  }

  Future<void> _createTag() async {
    final result = await _showTagDialog(context, widget.strings);
    if (result == null) return;
    await _run(
      'Create tag ${result.name}',
      (path) => git_api.createTag(
        path: path,
        targetOid: widget.commit.oid,
        name: result.name,
        annotated: result.annotated,
        message: result.message,
      ),
    );
  }

  Future<void> _checkoutDetached() async {
    final confirmed = await _confirmAction(
      context,
      strings: widget.strings,
      title: widget.strings.checkoutDetached,
      message:
          '${widget.commit.shortOid} · ${widget.commit.summary}\n\n${widget.strings.detachedHeadWarning}',
    );
    if (!confirmed) return;
    await _run(
      'Checkout ${widget.commit.shortOid}',
      (path) => git_api.checkoutCommit(path: path, oid: widget.commit.oid),
    );
  }

  Future<void> _runSequence(bool revert) async {
    final parent = await _selectMainlineParent(
      context,
      widget.strings,
      widget.commit,
    );
    if (!mounted) return;
    if (widget.commit.parentOids.length > 1 && parent == null) return;
    CherryPickApplicability? applicability;
    if (!revert) {
      try {
        applicability =
            widget.commit.parentOids.length <= 1 &&
                _assessedHeadOid == widget.tab.snapshot.headOid
            ? _cherryPickApplicability
            : null;
        applicability ??= await ref
            .read(gitFrontProvider.notifier)
            .assessCherryPick(widget.commit, mainlineParent: parent);
      } catch (error) {
        widget.onError(error);
        return;
      }
      if (!mounted) return;
      if (applicability == CherryPickApplicability.alreadyApplied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.cherryPickNoChanges)),
        );
        return;
      }
    }
    final title = revert
        ? widget.strings.revertCommit
        : widget.strings.cherryPick;
    final confirmed = await _confirmAction(
      context,
      strings: widget.strings,
      title: title,
      message: [
        '${widget.commit.shortOid} · ${widget.commit.summary}',
        if (applicability == CherryPickApplicability.conflicts)
          widget.strings.cherryPickConflictWarning,
      ].join('\n\n'),
    );
    if (!confirmed) return;
    await _run(
      revert
          ? 'Revert ${widget.commit.shortOid}'
          : 'Cherry-pick ${widget.commit.shortOid}',
      (path) => revert
          ? git_api.revertCommit(
              path: path,
              oid: widget.commit.oid,
              mainlineParent: parent,
            )
          : git_api.cherryPickCommit(
              path: path,
              oid: widget.commit.oid,
              mainlineParent: parent,
            ),
    );
  }

  Future<void> _rebaseOntoCommit() async {
    final confirmed = await _confirmAction(
      context,
      strings: widget.strings,
      title: widget.strings.rebaseOntoCommit,
      message:
          '${widget.tab.snapshot.headName} → ${widget.commit.shortOid}\n${widget.commit.summary}',
    );
    if (!confirmed) return;
    await _run(
      'Rebase onto ${widget.commit.shortOid}',
      (path) => git_api.rebaseBranch(path: path, upstream: widget.commit.oid),
    );
  }

  Future<void> _resetToCommit(ResetMode mode) async {
    try {
      final preview = await git_api.previewReset(
        path: widget.tab.snapshot.workdir,
        targetOid: widget.commit.oid,
      );
      if (!mounted) return;
      final confirmation = await _showResetDialog(
        context,
        widget.strings,
        preview,
        mode,
      );
      if (confirmation == null) return;
      await _run(
        '${mode.name} reset to ${widget.commit.shortOid}',
        (path) => git_api.resetToCommit(
          path: path,
          targetOid: widget.commit.oid,
          mode: mode,
          expectedFingerprint: preview.fingerprint,
          branchConfirmation: confirmation.isEmpty ? null : confirmation,
        ),
      );
    } catch (error) {
      widget.onError(error);
    }
  }
}

class _CommitReferenceStrip extends StatelessWidget {
  const _CommitReferenceStrip({
    required this.references,
    required this.strings,
  });

  final List<CommitReference> references;
  final GitFrontStrings strings;

  @override
  Widget build(BuildContext context) {
    final description = references
        .map((reference) {
          final kind = switch (reference.kind) {
            CommitReferenceKind.head => 'HEAD',
            CommitReferenceKind.localBranch => strings.localBranch,
            CommitReferenceKind.remoteBranch => strings.remoteBranch,
            CommitReferenceKind.tag => strings.tag,
          };
          return '$kind: ${reference.name}';
        })
        .join('\n');
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximumVisible = constraints.maxWidth >= 280
            ? 3
            : constraints.maxWidth >= 170
            ? 2
            : 1;
        final visible = references.take(maximumVisible).toList();
        final hidden = references.length - visible.length;
        return Tooltip(
          message: description,
          child: Semantics(
            label: description.replaceAll('\n', ', '),
            child: ClipRect(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reference in visible) ...[
                    Flexible(
                      child: _CommitReferenceBadge(reference: reference),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (hidden > 0)
                    Text(
                      '+$hidden',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommitReferenceBadge extends StatelessWidget {
  const _CommitReferenceBadge({required this.reference});

  final CommitReference reference;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (reference.kind) {
      CommitReferenceKind.head => (Colors.orange, Icons.adjust),
      CommitReferenceKind.localBranch => (Colors.blue, Icons.call_split),
      CommitReferenceKind.remoteBranch => (Colors.purple, Icons.cloud_outlined),
      CommitReferenceKind.tag => (Colors.teal, Icons.sell_outlined),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              reference.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _BranchAtCommitResult = ({String name, bool checkout});

Future<_BranchAtCommitResult?> _showBranchAtCommitDialog(
  BuildContext context,
  GitFrontStrings strings,
) async {
  final name = TextEditingController();
  var checkout = false;
  final result = await showDialog<_BranchAtCommitResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(strings.createBranchHere),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: strings.branches),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: checkout,
                title: Text(
                  strings.text('만든 브랜치로 전환', 'Switch to the new branch'),
                ),
                onChanged: (value) => setState(() => checkout = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (
                    name: name.text.trim(),
                    checkout: checkout,
                  )),
            child: Text(strings.confirm),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  return result;
}

typedef _TagResult = ({String name, bool annotated, String? message});

Future<_TagResult?> _showTagDialog(
  BuildContext context,
  GitFrontStrings strings,
) async {
  final name = TextEditingController();
  final message = TextEditingController();
  var annotated = true;
  final result = await showDialog<_TagResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final valid =
            name.text.trim().isNotEmpty &&
            (!annotated || message.text.trim().isNotEmpty);
        return AlertDialog(
          title: Text(strings.createTagHere),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: strings.tagName),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(strings.annotatedTag),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(strings.lightweightTag),
                    ),
                  ],
                  selected: {annotated},
                  onSelectionChanged: (value) =>
                      setState(() => annotated = value.first),
                ),
                if (annotated) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: message,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: strings.tagMessage),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, (
                      name: name.text.trim(),
                      annotated: annotated,
                      message: annotated ? message.text.trim() : null,
                    ))
                  : null,
              child: Text(strings.confirm),
            ),
          ],
        );
      },
    ),
  );
  name.dispose();
  message.dispose();
  return result;
}

Future<int?> _selectMainlineParent(
  BuildContext context,
  GitFrontStrings strings,
  CommitSummary commit,
) {
  if (commit.parentOids.length <= 1) return Future.value();
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(strings.mainlineParent),
      children: [
        for (var index = 0; index < commit.parentOids.length; index++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, index + 1),
            child: Text(
              '${index + 1} · ${commit.parentOids[index].substring(0, 8)}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
      ],
    ),
  );
}

Future<bool> _confirmAction(
  BuildContext context, {
  required GitFrontStrings strings,
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> _showResetDialog(
  BuildContext context,
  GitFrontStrings strings,
  ResetPreview preview,
  ResetMode mode,
) async {
  final confirmation = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final isHard = mode == ResetMode.hard;
        final valid =
            !isHard || confirmation.text.trim() == preview.currentBranch;
        return AlertDialog(
          title: Text('${strings.resetPreview} · ${mode.name.toUpperCase()}'),
          content: SizedBox(
            width: 620,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      '${preview.currentBranch} → ${preview.targetOid.substring(0, 8)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ResetPreviewSection(
                      title: strings.outgoingCommits,
                      lines: preview.outgoingCommits
                          .map((item) => '${item.shortOid}  ${item.summary}')
                          .toList(),
                      emptyLabel: strings.noItems,
                    ),
                    const SizedBox(height: 14),
                    _ResetPreviewSection(
                      title: strings.trackedChanges,
                      lines: preview.trackedPaths,
                      emptyLabel: strings.noItems,
                    ),
                    if (isHard) ...[
                      const SizedBox(height: 14),
                      _ResetPreviewSection(
                        title: strings.recycleBinPaths,
                        lines: preview.untrackedCollisions,
                        emptyLabel: strings.noItems,
                      ),
                      const SizedBox(height: 16),
                      Text(strings.typeBranchToConfirm),
                      const SizedBox(height: 6),
                      SelectableText(
                        preview.currentBranch,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextField(
                        controller: confirmation,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(
                      context,
                      isHard ? confirmation.text.trim() : '',
                    )
                  : null,
              child: Text(strings.confirm),
            ),
          ],
        );
      },
    ),
  );
  confirmation.dispose();
  return result;
}

class _ResetPreviewSection extends StatelessWidget {
  const _ResetPreviewSection({
    required this.title,
    required this.lines,
    required this.emptyLabel,
  });

  final String title;
  final List<String> lines;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (lines.isEmpty)
          Text(emptyLabel)
        else
          for (final line in lines)
            SelectableText(
              '• $line',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
      ],
    );
  }
}

class _DiffPane extends StatelessWidget {
  const _DiffPane({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    if (tab.selectedFile == null) {
      return Center(child: Text(strings.selectFile));
    }
    if (tab.busy && tab.diff == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final diff = tab.diff;
    if (diff == null || diff.files.isEmpty) {
      return const Center(child: Text('No textual diff'));
    }
    return _DiffViewer(document: diff, tab: tab, onError: onError);
  }
}

class _CommitDetailPane extends StatelessWidget {
  const _CommitDetailPane({required this.strings, required this.tab});

  final GitFrontStrings strings;
  final RepoTabState tab;

  @override
  Widget build(BuildContext context) {
    final comparison = tab.commitComparison;
    if (comparison != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              tab.commitComparisonLabel ?? strings.compareWithHead,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _DiffViewer(document: comparison, tab: tab, readOnly: true),
          ),
        ],
      );
    }
    final detail = tab.commitDetail;
    if (detail == null) {
      return tab.busy
          ? const Center(child: CircularProgressIndicator())
          : Center(child: Text(strings.selectCommit));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                detail.message,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('${detail.authorName} <${detail.authorEmail}>'),
              SelectableText(
                detail.oid,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _DiffViewer(document: detail.diff, tab: tab, readOnly: true),
        ),
      ],
    );
  }
}

class _DiffViewer extends StatefulWidget {
  const _DiffViewer({
    required this.document,
    required this.tab,
    this.onError,
    this.readOnly = false,
  });

  final DiffDocument document;
  final RepoTabState tab;
  final ValueChanged<Object>? onError;
  final bool readOnly;

  @override
  State<_DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<_DiffViewer> {
  bool sideBySide = false;
  late List<_DiffListItem> items;
  final Set<String> _selectedLines = {};

  String _lineKey(DiffHunk hunk, int lineIndex) => '${hunk.index}:$lineIndex';

  @override
  void initState() {
    super.initState();
    items = _buildItems();
  }

  @override
  void didUpdateWidget(covariant _DiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _selectedLines.clear();
      items = _buildItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No differences'));
    }
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.document.files.first.newPath ??
                      widget.document.files.first.oldPath ??
                      'Diff',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Unified')),
                  ButtonSegment(value: true, label: Text('Side by side')),
                ],
                selected: {sideBySide},
                onSelectionChanged: (value) {
                  if (value.first == sideBySide) return;
                  setState(() {
                    sideBySide = value.first;
                    items = _buildItems();
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RepaintBoundary(
            child: SelectionArea(
              child: ListView.builder(
                key: const ValueKey('virtualized-diff-list'),
                cacheExtent: 320,
                itemCount: items.length,
                itemBuilder: _buildItem,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_DiffListItem> _buildItems() {
    final result = <_DiffListItem>[];
    for (final file in widget.document.files) {
      if (file.binary || file.tooLarge) {
        result.add(_DiffFileNotice(file));
        continue;
      }
      final language = _syntaxLanguage(file.newPath ?? file.oldPath ?? '');
      for (final hunk in file.hunks) {
        result.add(_DiffHunkHeader(hunk));
        for (var lineIndex = 0; lineIndex < hunk.lines.length; lineIndex++) {
          final line = hunk.lines[lineIndex];
          result.add(
            sideBySide
                ? _DiffSideLine(hunk, lineIndex, line, language)
                : _DiffUnifiedLine(hunk, lineIndex, line, language),
          );
        }
      }
    }
    return result;
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = items[index];
    final strings = GitFrontStrings(
      resolveLocale(
        context,
        ProviderScope.containerOf(context).read(gitFrontProvider).language,
      ),
    );
    return switch (item) {
      _DiffFileNotice(:final file) => ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(file.newPath ?? file.oldPath ?? 'File'),
        subtitle: Text(
          file.binary ? 'Binary or non-UTF-8 file' : 'File is larger than 5 MB',
        ),
      ),
      _DiffHunkHeader(:final hunk) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hunk.header,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              if (!widget.readOnly)
                TextButton(
                  onPressed: widget.tab.busy
                      ? null
                      : () => _applyHunk(hunk, false),
                  child: Text(
                    widget.document.staged ? 'Unstage hunk' : 'Stage hunk',
                  ),
                ),
              if (!widget.readOnly &&
                  _selectedLines.any((key) => key.startsWith('${hunk.index}:')))
                TextButton(
                  onPressed: widget.tab.busy
                      ? null
                      : () => _applySelectedLines(hunk, false),
                  child: Text(
                    widget.document.staged
                        ? strings.unstageSelected
                        : strings.stageSelected,
                  ),
                ),
              if (!widget.readOnly &&
                  !widget.document.staged &&
                  _selectedLines.any((key) => key.startsWith('${hunk.index}:')))
                IconButton(
                  tooltip: strings.discardSelectedLines,
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: widget.tab.busy
                      ? null
                      : () => _discardSelectedLines(hunk),
                ),
              if (!widget.readOnly && !widget.document.staged)
                IconButton(
                  tooltip: 'Discard hunk',
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: widget.tab.busy ? null : () => _discardHunk(hunk),
                ),
            ],
          ),
        ),
      ),
      _DiffUnifiedLine(
        :final hunk,
        :final lineIndex,
        :final line,
        :final language,
      ) =>
        _DiffLineRow(
          line: line,
          language: language,
          selected: _selectedLines.contains(_lineKey(hunk, lineIndex)),
          onSelected:
              !widget.readOnly &&
                  (line.kind == DiffLineKind.addition ||
                      line.kind == DiffLineKind.deletion)
              ? (selected) => setState(() {
                  final key = _lineKey(hunk, lineIndex);
                  selected
                      ? _selectedLines.add(key)
                      : _selectedLines.remove(key);
                })
              : null,
        ),
      _DiffSideLine(:final line, :final language) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: line.kind == DiffLineKind.addition
                ? const SizedBox(height: 20)
                : _DiffLineRow(
                    line: line,
                    language: language,
                    showNewNumber: false,
                  ),
          ),
          Container(
            width: 1,
            height: 20,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: line.kind == DiffLineKind.deletion
                ? const SizedBox(height: 20)
                : _DiffLineRow(
                    line: line,
                    language: language,
                    showOldNumber: false,
                  ),
          ),
        ],
      ),
    };
  }

  Future<void> _applyHunk(DiffHunk hunk, bool discard) async {
    final file = widget.tab.selectedFile;
    if (file == null) return;
    try {
      await ProviderScope.containerOf(context)
          .read(gitFrontProvider.notifier)
          .runOperation(
            discard
                ? 'Discard hunk'
                : widget.document.staged
                ? 'Unstage hunk'
                : 'Stage hunk',
            (path) => git_api.applyHunk(
              path: path,
              filePath: file.path,
              staged: widget.document.staged,
              hunkIndex: hunk.index,
              expectedFingerprint: widget.document.fingerprint,
              reverse: discard || widget.document.staged,
            ),
          );
    } catch (error) {
      widget.onError?.call(error);
    }
  }

  Future<void> _applySelectedLines(DiffHunk hunk, bool discard) async {
    final file = widget.tab.selectedFile;
    if (file == null) return;
    final prefix = '${hunk.index}:';
    final lineIndices =
        _selectedLines
            .where((key) => key.startsWith(prefix))
            .map((key) => int.parse(key.substring(prefix.length)))
            .toList()
          ..sort();
    if (lineIndices.isEmpty) return;
    try {
      await ProviderScope.containerOf(context)
          .read(gitFrontProvider.notifier)
          .runOperation(
            discard
                ? 'Discard selected lines'
                : widget.document.staged
                ? 'Unstage selected lines'
                : 'Stage selected lines',
            (path) => git_api.applyHunkLines(
              path: path,
              filePath: file.path,
              staged: widget.document.staged,
              hunkIndex: hunk.index,
              lineIndices: lineIndices,
              expectedFingerprint: widget.document.fingerprint,
              reverse: discard || widget.document.staged,
            ),
          );
    } catch (error) {
      widget.onError?.call(error);
    }
  }

  Future<void> _discardHunk(DiffHunk hunk) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this hunk?'),
            content: const Text(
              'These tracked changes cannot be recovered by GitFront.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _applyHunk(hunk, true);
  }

  Future<void> _discardSelectedLines(DiffHunk hunk) async {
    final strings = GitFrontStrings(
      resolveLocale(
        context,
        ProviderScope.containerOf(context).read(gitFrontProvider).language,
      ),
    );
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.discardSelectedLinesQuestion),
            content: Text(strings.discardedChangesCannotRecover),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.discard),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _applySelectedLines(hunk, true);
  }
}

sealed class _DiffListItem {
  const _DiffListItem();
}

class _DiffFileNotice extends _DiffListItem {
  const _DiffFileNotice(this.file);
  final DiffFile file;
}

class _DiffHunkHeader extends _DiffListItem {
  const _DiffHunkHeader(this.hunk);
  final DiffHunk hunk;
}

class _DiffUnifiedLine extends _DiffListItem {
  const _DiffUnifiedLine(this.hunk, this.lineIndex, this.line, this.language);
  final DiffHunk hunk;
  final int lineIndex;
  final DiffLine line;
  final String language;
}

class _DiffSideLine extends _DiffListItem {
  const _DiffSideLine(this.hunk, this.lineIndex, this.line, this.language);
  final DiffHunk hunk;
  final int lineIndex;
  final DiffLine line;
  final String language;
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    required this.line,
    required this.language,
    this.showOldNumber = true,
    this.showNewNumber = true,
    this.selected = false,
    this.onSelected,
  });
  final DiffLine line;
  final String language;
  final bool showOldNumber;
  final bool showNewNumber;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = switch (line.kind) {
      DiffLineKind.addition => Colors.green.withValues(alpha: 0.14),
      DiffLineKind.deletion => colors.error.withValues(alpha: 0.12),
      _ => Colors.transparent,
    };
    final marker = switch (line.kind) {
      DiffLineKind.addition => '+',
      DiffLineKind.deletion => '-',
      _ => ' ',
    };
    return Container(
      color: background,
      constraints: const BoxConstraints(minHeight: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onSelected != null)
            SizedBox(
              width: 28,
              height: 20,
              child: Checkbox(
                value: selected,
                onChanged: (value) => onSelected?.call(value ?? false),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (showOldNumber) _LineNumber(value: line.oldLine?.toString() ?? ''),
          if (showNewNumber) _LineNumber(value: line.newLine?.toString() ?? ''),
          SizedBox(
            width: 18,
            child: Text(
              marker,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text.rich(
              _highlightDiffLine(
                context,
                _displayDiffLine(line.content),
                language,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _maxRenderedDiffLineLength = 20000;
final _syntaxTokenPattern = RegExp(
  r'''("[^"]*"|'[^']*'|\b[A-Za-z_][A-Za-z0-9_]*\b)''',
);

String _displayDiffLine(String content) {
  var value = content;
  if (value.endsWith('\n')) value = value.substring(0, value.length - 1);
  if (value.endsWith('\r')) value = value.substring(0, value.length - 1);
  if (value.length <= _maxRenderedDiffLineLength) return value;
  return '${value.substring(0, _maxRenderedDiffLineLength)}… [line truncated]';
}

String _syntaxLanguage(String path) {
  final extension = path.toLowerCase().split('.').last;
  return switch (extension) {
    'dart' => 'dart',
    'rs' => 'rust',
    'js' || 'jsx' || 'ts' || 'tsx' => 'javascript',
    'py' => 'python',
    'json' || 'yaml' || 'yml' || 'toml' => 'data',
    _ => 'plain',
  };
}

TextSpan _highlightDiffLine(
  BuildContext context,
  String content,
  String language,
) {
  final base = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12.5,
    height: 1.45,
    color: Theme.of(context).colorScheme.onSurface,
  );
  if (language == 'plain') return TextSpan(text: content, style: base);
  final trimmed = content.trimLeft();
  if (trimmed.startsWith('//') ||
      (language == 'python' && trimmed.startsWith('#'))) {
    return TextSpan(
      text: content,
      style: base.copyWith(color: Colors.blueGrey),
    );
  }
  final keywords = switch (language) {
    'dart' => const {
      'class',
      'const',
      'final',
      'var',
      'void',
      'async',
      'await',
      'return',
      'if',
      'else',
      'for',
      'while',
      'switch',
      'case',
      'import',
      'extends',
      'implements',
      'required',
      'this',
      'new',
      'true',
      'false',
      'null',
    },
    'rust' => const {
      'fn',
      'let',
      'mut',
      'pub',
      'struct',
      'enum',
      'impl',
      'trait',
      'use',
      'mod',
      'match',
      'if',
      'else',
      'for',
      'while',
      'loop',
      'return',
      'async',
      'await',
      'move',
      'self',
      'Self',
      'true',
      'false',
      'where',
      'crate',
    },
    'javascript' => const {
      'const',
      'let',
      'var',
      'function',
      'class',
      'return',
      'async',
      'await',
      'if',
      'else',
      'for',
      'while',
      'switch',
      'case',
      'import',
      'export',
      'extends',
      'new',
      'true',
      'false',
      'null',
      'undefined',
      'interface',
      'type',
    },
    'python' => const {
      'def',
      'class',
      'return',
      'async',
      'await',
      'if',
      'elif',
      'else',
      'for',
      'while',
      'match',
      'case',
      'import',
      'from',
      'as',
      'with',
      'try',
      'except',
      'finally',
      'True',
      'False',
      'None',
      'lambda',
      'yield',
    },
    _ => const <String>{},
  };
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final token in _syntaxTokenPattern.allMatches(content)) {
    if (token.start > offset) {
      spans.add(TextSpan(text: content.substring(offset, token.start)));
    }
    final value = token.group(0)!;
    final color = value.startsWith('"') || value.startsWith("'")
        ? Colors.deepOrange
        : keywords.contains(value)
        ? Theme.of(context).colorScheme.primary
        : null;
    spans.add(
      TextSpan(
        text: value,
        style: color == null
            ? null
            : TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
    offset = token.end;
  }
  if (offset < content.length) {
    spans.add(TextSpan(text: content.substring(offset)));
  }
  return TextSpan(style: base, children: spans);
}

class _VirtualTextView extends StatefulWidget {
  const _VirtualTextView({
    super.key,
    required this.content,
    this.padding = EdgeInsets.zero,
  });

  final String content;
  final EdgeInsetsGeometry padding;

  @override
  State<_VirtualTextView> createState() => _VirtualTextViewState();
}

class _VirtualTextViewState extends State<_VirtualTextView> {
  late List<int> lineStarts;

  @override
  void initState() {
    super.initState();
    lineStarts = _indexLines(widget.content);
  }

  @override
  void didUpdateWidget(covariant _VirtualTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      lineStarts = _indexLines(widget.content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SelectionArea(
        child: ListView.builder(
          padding: widget.padding,
          cacheExtent: 320,
          itemCount: lineStarts.length,
          itemBuilder: (context, index) => Text(
            _lineAt(index),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  List<int> _indexLines(String content) {
    final starts = <int>[0];
    for (var index = 0; index < content.length - 1; index++) {
      if (content.codeUnitAt(index) == 10) starts.add(index + 1);
    }
    return starts;
  }

  String _lineAt(int index) {
    final start = lineStarts[index];
    final end = index + 1 < lineStarts.length
        ? lineStarts[index + 1]
        : widget.content.length;
    return _displayDiffLine(widget.content.substring(start, end));
  }
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      padding: const EdgeInsets.only(right: 7),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ConflictEditor extends StatefulWidget {
  const _ConflictEditor({required this.conflict});
  final ConflictFile conflict;

  @override
  State<_ConflictEditor> createState() => _ConflictEditorState();
}

class _ConflictEditorState extends State<_ConflictEditor> {
  late final TextEditingController result = TextEditingController(
    text: widget.conflict.current,
  );
  final Set<int> resolvedRegions = {};

  @override
  void dispose() {
    result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conflict = widget.conflict;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Resolve · ${conflict.path}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, result.text),
              icon: const Icon(Icons.check),
              label: const Text('Save and stage'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: conflict.binary || conflict.tooLarge
            ? _BinaryConflict(conflict: conflict, result: result)
            : Column(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Expanded(
                          child: _ConflictPane(
                            title: conflict.baseLabel,
                            content: conflict.base,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _ConflictPane(
                            title: conflict.oursLabel,
                            content: conflict.ours,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _ConflictPane(
                            title: conflict.theirsLabel,
                            content: conflict.theirs,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (conflict.regions.isNotEmpty)
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: conflict.regions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final region = conflict.regions[index];
                          return SegmentedButton<String>(
                            showSelectedIcon: false,
                            emptySelectionAllowed: true,
                            segments: [
                              ButtonSegment(
                                value: 'ours',
                                label: Text(
                                  '#${index + 1} ${conflict.oursLabel}',
                                ),
                              ),
                              const ButtonSegment(
                                value: 'both',
                                label: Text('Both'),
                              ),
                              ButtonSegment(
                                value: 'theirs',
                                label: Text(conflict.theirsLabel),
                              ),
                            ],
                            selected: const {},
                            onSelectionChanged: (choice) =>
                                _resolveRegion(region, choice.first),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: result,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Result',
                        alignLabelWithHint: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _resolveRegion(ConflictRegion region, String choice) {
    if (resolvedRegions.contains(region.index)) return;
    final matches = RegExp(
      r'^<<<<<<<[^\n]*\n[\s\S]*?^>>>>>>>[^\n]*(?:\n|$)',
      multiLine: true,
    ).allMatches(result.text).toList();
    final currentIndex = widget.conflict.regions
        .where(
          (candidate) =>
              candidate.index < region.index &&
              !resolvedRegions.contains(candidate.index),
        )
        .length;
    if (currentIndex >= matches.length) return;
    final match = matches[currentIndex];
    final replacement = switch (choice) {
      'ours' => region.ours,
      'theirs' => region.theirs,
      _ => '${region.ours}${region.theirs}',
    };
    result.text = result.text.replaceRange(match.start, match.end, replacement);
    resolvedRegions.add(region.index);
  }
}

class _ConflictPane extends StatelessWidget {
  const _ConflictPane({required this.title, required this.content});
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        Expanded(
          child: _VirtualTextView(
            key: ValueKey('virtualized-conflict-$title'),
            content: content,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ],
    );
  }
}

class _BinaryConflict extends StatelessWidget {
  const _BinaryConflict({required this.conflict, required this.result});
  final ConflictFile conflict;
  final TextEditingController result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 52),
          const SizedBox(height: 12),
          Text(
            conflict.binary
                ? 'Binary or non-UTF-8 conflict'
                : 'Conflict is larger than 5 MB',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => result.text = conflict.ours,
                child: Text('Use ${conflict.oursLabel}'),
              ),
              OutlinedButton(
                onPressed: () => result.text = conflict.theirs,
                child: Text('Use ${conflict.theirsLabel}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InteractiveRebaseDialog extends StatefulWidget {
  const _InteractiveRebaseDialog({required this.plan});
  final RebasePlan plan;

  @override
  State<_InteractiveRebaseDialog> createState() =>
      _InteractiveRebaseDialogState();
}

class _InteractiveRebaseDialogState extends State<_InteractiveRebaseDialog> {
  late final List<RebasePlanItem> items = [...widget.plan.items];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Interactive rebase · ${widget.plan.upstream}'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          children: [
            if (widget.plan.containsMergeCommits)
              const MaterialBanner(
                content: Text(
                  'Merge commits are present. This v1 rebase will flatten them.',
                ),
                actions: [SizedBox.shrink()],
              ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = items.removeAt(oldIndex);
                    items.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    key: ValueKey(item.oid),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(item.summary),
                    subtitle: Text(
                      item.oid.substring(0, 8),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    trailing: DropdownButton<RebaseAction>(
                      value: item.action,
                      items: RebaseAction.values
                          .map(
                            (action) => DropdownMenuItem(
                              value: action,
                              child: Text(action.name),
                            ),
                          )
                          .toList(),
                      onChanged: (action) async {
                        if (action == null) return;
                        String? message = item.newMessage;
                        if (action == RebaseAction.reword ||
                            action == RebaseAction.squash) {
                          message = await _textPrompt(
                            context,
                            title: action.name,
                            label: 'New commit message',
                            initialValue: item.summary,
                          );
                          if (message == null) return;
                        }
                        setState(() {
                          items[index] = RebasePlanItem(
                            action: action,
                            oid: item.oid,
                            summary: item.summary,
                            newMessage: message,
                          );
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RebasePlan(
              upstream: widget.plan.upstream,
              onto: widget.plan.onto,
              items: items,
              containsMergeCommits: widget.plan.containsMergeCommits,
            ),
          ),
          child: const Text('Start rebase'),
        ),
      ],
    );
  }
}

class _CreateRepositoryDialog extends StatefulWidget {
  const _CreateRepositoryDialog({required this.strings});
  final GitFrontStrings strings;

  @override
  State<_CreateRepositoryDialog> createState() =>
      _CreateRepositoryDialogState();
}

class _CreateRepositoryDialogState extends State<_CreateRepositoryDialog> {
  final target = TextEditingController();
  final branch = TextEditingController(text: 'main');
  final origin = TextEditingController();
  bool createReadme = true;
  GitignoreTemplate template = GitignoreTemplate.none;
  GitCapabilities? capabilities;
  bool readmeExists = false;
  bool gitignoreExists = false;
  Timer? pathCheck;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaultBranch());
    unawaited(_loadCapabilities());
  }

  Future<void> _loadCapabilities() async {
    try {
      final value = await git_api.gitCapabilities();
      if (mounted) setState(() => capabilities = value);
    } catch (_) {
      // Submitting the operation will surface the original Git error.
    }
  }

  void _scheduleFileCheck(String value) {
    pathCheck?.cancel();
    pathCheck = Timer(const Duration(milliseconds: 180), () async {
      final directory = value.trim();
      if (directory.isEmpty) return;
      final separator = Platform.pathSeparator;
      final results = await Future.wait([
        File([directory, 'README.md'].join(separator)).exists(),
        File([directory, '.gitignore'].join(separator)).exists(),
      ]);
      if (!mounted) return;
      setState(() {
        readmeExists = results[0];
        gitignoreExists = results[1];
        if (readmeExists) createReadme = false;
        if (gitignoreExists) template = GitignoreTemplate.none;
      });
    });
  }

  Future<void> _loadDefaultBranch() async {
    try {
      final config = await git_api.readGitConfig();
      final values = config.entries.where(
        (entry) => entry.key.toLowerCase() == 'init.defaultbranch',
      );
      if (values.isNotEmpty && mounted) branch.text = values.last.value;
    } catch (_) {
      // The safe fallback is main when global config cannot be read.
    }
  }

  @override
  void dispose() {
    target.dispose();
    branch.dispose();
    origin.dispose();
    pathCheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.createRepository),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: target,
                      autofocus: true,
                      onChanged: _scheduleFileCheck,
                      decoration: InputDecoration(
                        labelText: widget.strings.destination,
                        helperText: widget.strings.text(
                          '기존 폴더 또는 새 폴더 경로',
                          'An existing folder or a new folder path',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final path = await getDirectoryPath(
                        confirmButtonText: widget.strings.confirm,
                      );
                      if (path != null) {
                        target.text = path;
                        _scheduleFileCheck(path);
                      }
                    },
                    child: Text(widget.strings.browse),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: branch,
                decoration: InputDecoration(
                  labelText: widget.strings.initialBranch,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: createReadme,
                title: Text(widget.strings.createReadme),
                subtitle: readmeExists
                    ? Text(
                        widget.strings.text(
                          '기존 README.md를 덮어쓰지 않습니다.',
                          'The existing README.md will not be overwritten.',
                        ),
                      )
                    : null,
                onChanged: readmeExists
                    ? null
                    : (value) => setState(() => createReadme = value ?? false),
              ),
              DropdownButtonFormField<GitignoreTemplate>(
                initialValue: template,
                decoration: InputDecoration(
                  labelText: widget.strings.gitignoreTemplate,
                ),
                items: GitignoreTemplate.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(switch (value) {
                          GitignoreTemplate.none => widget.strings.noItems,
                          GitignoreTemplate.flutter => 'Flutter / Dart',
                          GitignoreTemplate.rust => 'Rust',
                          GitignoreTemplate.node => 'Node',
                          GitignoreTemplate.python => 'Python',
                          GitignoreTemplate.visualStudio => 'Visual Studio',
                        }),
                      ),
                    )
                    .toList(),
                onChanged: gitignoreExists
                    ? null
                    : (value) => setState(
                        () => template = value ?? GitignoreTemplate.none,
                      ),
              ),
              if (gitignoreExists)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.strings.text(
                      '기존 .gitignore를 덮어쓰지 않습니다.',
                      'The existing .gitignore will not be overwritten.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: origin,
                decoration: InputDecoration(
                  labelText: widget.strings.originUrl,
                ),
              ),
              if (capabilities?.supportsRepositorySetup == false)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    widget.strings.text(
                      '새 저장소 생성에는 Git 2.28 이상이 필요합니다.',
                      'Creating repositories requires Git 2.28 or newer.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: capabilities?.supportsRepositorySetup == false
              ? null
              : () {
                  if (target.text.trim().isEmpty ||
                      branch.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    RepositoryInitOptions(
                      targetPath: target.text.trim(),
                      initialBranch: branch.text.trim(),
                      createReadme: createReadme,
                      gitignoreTemplate: template,
                      originUrl: origin.text.trim().isEmpty
                          ? null
                          : origin.text.trim(),
                    ),
                  );
                },
          child: Text(widget.strings.createRepository),
        ),
      ],
    );
  }
}

class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.strings});
  final GitFrontStrings strings;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  final url = TextEditingController();
  final destination = TextEditingController();
  final remoteName = TextEditingController(text: 'origin');
  final branch = TextEditingController();
  final depth = TextEditingController();
  final sparseDirectories = TextEditingController();
  bool singleBranch = false;
  bool noTags = false;
  bool recurseSubmodules = false;
  bool shallowSubmodules = false;
  bool blobless = false;
  GitCapabilities? capabilities;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCapabilities());
  }

  Future<void> _loadCapabilities() async {
    try {
      final value = await git_api.gitCapabilities();
      if (mounted) setState(() => capabilities = value);
    } catch (_) {
      // Clone will surface the original Git error.
    }
  }

  @override
  void dispose() {
    url.dispose();
    destination.dispose();
    remoteName.dispose();
    branch.dispose();
    depth.dispose();
    sparseDirectories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.cloneRepository),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autofocus: true,
                decoration: InputDecoration(labelText: widget.strings.repoUrl),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: destination,
                      decoration: InputDecoration(
                        labelText: widget.strings.destination,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final path = await getDirectoryPath(
                        confirmButtonText: widget.strings.confirm,
                      );
                      if (path != null) destination.text = path;
                    },
                    child: Text(widget.strings.browse),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(widget.strings.advancedOptions),
                children: [
                  TextField(
                    controller: remoteName,
                    decoration: InputDecoration(
                      labelText: widget.strings.remoteName,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: branch,
                          decoration: InputDecoration(
                            labelText: widget.strings.branchOrTag,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: depth,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: widget.strings.cloneDepth,
                          ),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: singleBranch,
                    title: Text(widget.strings.singleBranch),
                    onChanged: (value) =>
                        setState(() => singleBranch = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: noTags,
                    title: Text(widget.strings.noTags),
                    onChanged: (value) =>
                        setState(() => noTags = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: recurseSubmodules,
                    title: Text(widget.strings.recurseSubmodules),
                    onChanged: (value) => setState(() {
                      recurseSubmodules = value ?? false;
                      if (!recurseSubmodules) shallowSubmodules = false;
                    }),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: shallowSubmodules,
                    title: Text(widget.strings.shallowSubmodules),
                    onChanged: recurseSubmodules
                        ? (value) =>
                              setState(() => shallowSubmodules = value ?? false)
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: blobless,
                    title: Text(widget.strings.bloblessClone),
                    onChanged: (value) =>
                        setState(() => blobless = value ?? false),
                  ),
                  TextField(
                    controller: sparseDirectories,
                    enabled: capabilities?.supportsSparseCheckout != false,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: widget.strings.sparseDirectories,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (url.text.trim().isEmpty || destination.text.trim().isEmpty) {
              return;
            }
            final parsedDepth = depth.text.trim().isEmpty
                ? null
                : int.tryParse(depth.text.trim());
            if (depth.text.trim().isNotEmpty &&
                (parsedDepth == null || parsedDepth <= 0)) {
              return;
            }
            Navigator.pop(
              context,
              CloneOptions(
                url: url.text.trim(),
                target: destination.text.trim(),
                remoteName: remoteName.text.trim().isEmpty
                    ? 'origin'
                    : remoteName.text.trim(),
                branch: branch.text.trim().isEmpty ? null : branch.text.trim(),
                depth: parsedDepth,
                singleBranch: singleBranch,
                noTags: noTags,
                recurseSubmodules: recurseSubmodules,
                shallowSubmodules: shallowSubmodules,
                blobless: blobless,
                sparseDirectories: sparseDirectories.text
                    .split(RegExp(r'[\r\n]+'))
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
              ),
            );
          },
          child: Text(widget.strings.cloneRepository),
        ),
      ],
    );
  }
}

class _SubtreeManagerDialog extends ConsumerStatefulWidget {
  const _SubtreeManagerDialog({
    required this.strings,
    required this.repositoryPath,
  });

  final GitFrontStrings strings;
  final String repositoryPath;

  @override
  ConsumerState<_SubtreeManagerDialog> createState() =>
      _SubtreeManagerDialogState();
}

class _SubtreeManagerDialogState extends ConsumerState<_SubtreeManagerDialog> {
  final prefix = TextEditingController();
  final repository = TextEditingController();
  final reference = TextEditingController(text: 'main');
  List<SubtreeInfo> entries = const [];
  List<String> output = const [];
  GitCapabilities? capabilities;
  bool squash = true;
  bool loading = true;
  String? operationId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    prefix.dispose();
    repository.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        git_api.gitCapabilities(),
        git_api.listSubtrees(path: widget.repositoryPath),
      ]);
      if (!mounted) return;
      setState(() {
        capabilities = values[0] as GitCapabilities;
        entries = values[1] as List<SubtreeInfo>;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        output = [...output, error.toString()];
        loading = false;
      });
    }
  }

  SubtreeInfo? _formEntry() {
    if (prefix.text.trim().isEmpty ||
        repository.text.trim().isEmpty ||
        reference.text.trim().isEmpty) {
      return null;
    }
    return SubtreeInfo(
      id: 'st${DateTime.now().microsecondsSinceEpoch}',
      prefix: prefix.text.trim(),
      repository: repository.text.trim(),
      reference: reference.text.trim(),
      squash: squash,
    );
  }

  Future<void> _register() async {
    final entry = _formEntry();
    if (entry == null) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Register subtree',
            (path) => git_api.registerSubtree(path: path, subtree: entry),
          );
      await _load();
    } catch (error) {
      if (mounted) setState(() => output = [...output, error.toString()]);
    }
  }

  Future<void> _run(SubtreeOperationOptions options) async {
    final id = 'subtree${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      operationId = id;
      output = const [];
    });
    try {
      await for (final event in git_api.runSubtreeOperation(
        path: widget.repositoryPath,
        operationId: id,
        options: options,
      )) {
        ref.read(gitFrontProvider.notifier).recordOperationEvent(event);
        if (!mounted) continue;
        setState(() {
          output = [...output, event.message];
          if (output.length > 100) output = output.sublist(output.length - 100);
        });
      }
      await ref
          .read(gitFrontProvider.notifier)
          .refresh(repositoryPath: widget.repositoryPath, reloadHistory: true);
      await _load();
    } catch (error) {
      if (mounted) setState(() => output = [...output, error.toString()]);
    } finally {
      if (mounted) setState(() => operationId = null);
    }
  }

  Future<void> _runEntry(SubtreeInfo entry, SubtreeAction action) async {
    if (action == SubtreeAction.push &&
        !await _confirmAction(
          context,
          strings: widget.strings,
          title: 'Subtree push',
          message: '${entry.repository}  ${entry.reference}',
        )) {
      return;
    }
    String? branch;
    if (action == SubtreeAction.split) {
      if (!mounted) return;
      branch = await _textPrompt(
        context,
        title: 'Subtree split',
        label: widget.strings.text(
          '결과 브랜치 (비워도 됨)',
          'Result branch (optional)',
        ),
        allowEmpty: true,
      );
      if (branch == null) return;
    }
    await _run(
      SubtreeOperationOptions(
        action: action,
        prefix: entry.prefix,
        repository: action == SubtreeAction.split ? null : entry.repository,
        reference: action == SubtreeAction.split ? null : entry.reference,
        squash: entry.squash,
        branch: branch?.isEmpty == true ? null : branch,
      ),
    );
  }

  Future<void> _forget(SubtreeInfo entry) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Forget subtree ${entry.prefix}',
            (path) => git_api.forgetSubtree(path: path, id: entry.id),
          );
      await _load();
    } catch (error) {
      if (mounted) setState(() => output = [...output, error.toString()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final supported = capabilities?.supportsSubtree ?? false;
    return AlertDialog(
      title: Text(strings.manageSubtrees),
      content: SizedBox(
        width: 720,
        height: 560,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!supported)
                    MaterialBanner(
                      content: Text(
                        capabilities?.subtreeDiagnostic ??
                            strings.text(
                              '시스템 Git에서 subtree를 사용할 수 없습니다.',
                              'Subtree is unavailable in the system Git installation.',
                            ),
                      ),
                      actions: const [SizedBox.shrink()],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: prefix,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Prefix',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: repository,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.repoUrl,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: reference,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Ref'),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: squash,
                    onChanged: (value) =>
                        setState(() => squash = value ?? true),
                    title: const Text('Squash'),
                  ),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed:
                            supported &&
                                operationId == null &&
                                _formEntry() != null
                            ? () {
                                final entry = _formEntry()!;
                                _run(
                                  SubtreeOperationOptions(
                                    action: SubtreeAction.add,
                                    prefix: entry.prefix,
                                    repository: entry.repository,
                                    reference: entry.reference,
                                    squash: entry.squash,
                                    branch: null,
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(strings.add),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: operationId == null && _formEntry() != null
                            ? _register
                            : null,
                        child: Text(
                          strings.text('기존 Subtree 등록', 'Register existing'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final entry in entries)
                          ListTile(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: Text(entry.prefix),
                            subtitle: Text(
                              '${entry.repository} · ${entry.reference}${entry.squash ? ' · squash' : ''}',
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: supported && operationId == null,
                              onSelected: (action) => switch (action) {
                                'pull' => _runEntry(entry, SubtreeAction.pull),
                                'push' => _runEntry(entry, SubtreeAction.push),
                                'split' => _runEntry(
                                  entry,
                                  SubtreeAction.split,
                                ),
                                _ => _forget(entry),
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'pull',
                                  child: Text('Pull'),
                                ),
                                PopupMenuItem(
                                  value: 'push',
                                  child: Text('Push…'),
                                ),
                                PopupMenuItem(
                                  value: 'split',
                                  child: Text('Split…'),
                                ),
                                PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'forget',
                                  child: Text('Forget'),
                                ),
                              ],
                            ),
                          ),
                        if (output.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: SelectableText(
                              output.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (operationId != null)
          TextButton.icon(
            onPressed: () =>
                git_api.cancelGitOperation(operationId: operationId!),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(strings.cancel),
          ),
        TextButton(
          onPressed: operationId == null ? () => Navigator.pop(context) : null,
          child: Text(strings.close),
        ),
      ],
    );
  }
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog({required this.strings});
  final GitFrontStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gitFrontProvider);
    final controller = ref.read(gitFrontProvider.notifier);
    return AlertDialog(
      title: Text(strings.settings),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.language,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              SegmentedButton<AppLanguage>(
                segments: const [
                  ButtonSegment(
                    value: AppLanguage.system,
                    label: Text('System'),
                  ),
                  ButtonSegment(value: AppLanguage.korean, label: Text('한국어')),
                  ButtonSegment(
                    value: AppLanguage.english,
                    label: Text('English'),
                  ),
                ],
                selected: {state.language},
                onSelectionChanged: (value) =>
                    unawaited(controller.setLanguage(value.first)),
              ),
              const SizedBox(height: 18),
              Text(
                strings.theme,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(strings.system)),
                  ButtonSegment(value: 1, label: Text(strings.light)),
                  ButtonSegment(value: 2, label: Text(strings.dark)),
                ],
                selected: {
                  state.darkMode == null
                      ? 0
                      : state.darkMode!
                      ? 2
                      : 1,
                },
                onSelectionChanged: (value) => unawaited(
                  controller.setDarkMode(
                    value.first == 0 ? null : value.first == 2,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings.externalEditor,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<ExternalEditor>(
                initialValue: state.externalEditor,
                decoration: const InputDecoration(isDense: true),
                items: const [
                  DropdownMenuItem(
                    value: ExternalEditor.vsCode,
                    child: Text('Visual Studio Code'),
                  ),
                  DropdownMenuItem(
                    value: ExternalEditor.systemDefault,
                    child: Text('System default application'),
                  ),
                  DropdownMenuItem(
                    value: ExternalEditor.gitMergeTool,
                    child: Text('Git mergetool'),
                  ),
                  DropdownMenuItem(
                    value: ExternalEditor.custom,
                    child: Text('Custom executable'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(controller.setExternalEditor(value));
                  }
                },
              ),
              if (state.externalEditor == ExternalEditor.custom) ...[
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: state.customEditorExecutable,
                  decoration: InputDecoration(
                    labelText: strings.customExecutable,
                    isDense: true,
                  ),
                  onChanged: (value) => unawaited(
                    controller.setExternalEditor(
                      ExternalEditor.custom,
                      customExecutable: value,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: Text(strings.gitSettings),
                subtitle: Text(
                  strings.text(
                    '저장소별·사용자 전역 Git 설정',
                    'Repository and global Git configuration',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => _GitSettingsDialog(
                    strings: strings,
                    repositoryPath: state.activeTab?.snapshot.workdir,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_outlined),
                title: Text(strings.manageRemotes),
                subtitle: Text(
                  state.activeTab?.snapshot.name ??
                      strings.text('저장소를 먼저 여세요', 'Open a repository first'),
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: state.activeTab != null,
                onTap: state.activeTab == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) => _RemoteSettingsDialog(
                          strings: strings,
                          repositoryPath: state.activeTab!.snapshot.workdir,
                        ),
                      ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.filter_alt_outlined),
                title: Text(strings.sparseCheckout),
                trailing: const Icon(Icons.chevron_right),
                enabled: state.activeTab != null,
                onTap: state.activeTab == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) => _SparseCheckoutDialog(
                          strings: strings,
                          repositoryPath: state.activeTab!.snapshot.workdir,
                        ),
                      ),
              ),
              const Divider(),
              const _UpdateCard(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.close),
        ),
      ],
    );
  }
}

const _commonGitConfigKeys = <String>[
  'user.name',
  'user.email',
  'core.autocrlf',
  'core.editor',
  'init.defaultBranch',
  'pull.rebase',
  'pull.ff',
  'fetch.prune',
  'push.autoSetupRemote',
  'commit.gpgSign',
  'user.signingKey',
];

class _GitSettingsDialog extends ConsumerStatefulWidget {
  const _GitSettingsDialog({
    required this.strings,
    required this.repositoryPath,
  });

  final GitFrontStrings strings;
  final String? repositoryPath;

  @override
  ConsumerState<_GitSettingsDialog> createState() => _GitSettingsDialogState();
}

class _GitSettingsDialogState extends ConsumerState<_GitSettingsDialog> {
  GitConfigSnapshot? snapshot;
  late GitConfigScope scope;
  String query = '';
  String? error;

  @override
  void initState() {
    super.initState();
    scope = widget.repositoryPath == null
        ? GitConfigScope.global
        : GitConfigScope.local;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final value = await git_api.readGitConfig(path: widget.repositoryPath);
      if (mounted) setState(() => snapshot = value);
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Iterable<GitConfigEntry> get _scopeEntries =>
      (snapshot?.entries ?? const <GitConfigEntry>[]).where(
        (entry) =>
            entry.scope == scope &&
            (query.isEmpty ||
                entry.key.toLowerCase().contains(query.toLowerCase())),
      );

  GitConfigEntry? _directEntry(String key) {
    GitConfigEntry? result;
    for (final entry in snapshot?.entries ?? const <GitConfigEntry>[]) {
      if (entry.scope == scope &&
          entry.key.toLowerCase() == key.toLowerCase()) {
        result = entry;
      }
    }
    return result;
  }

  GitConfigEntry? _effectiveEntry(String key) {
    GitConfigEntry? result;
    for (final entry in snapshot?.entries ?? const <GitConfigEntry>[]) {
      if (entry.key.toLowerCase() == key.toLowerCase()) result = entry;
    }
    return result;
  }

  Future<void> _setValue(String key, {String? initialValue}) async {
    final current = initialValue ?? _directEntry(key)?.value ?? '';
    final value = await _textPrompt(
      context,
      title: key,
      label: widget.strings.text('설정 값', 'Configuration value'),
      initialValue: current == '••••••••' ? '' : current,
    );
    if (value == null) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runStandaloneOperation(
            'Set $key (${scope.name})',
            () => git_api.setGitConfig(
              path: widget.repositoryPath,
              scope: scope,
              key: key,
              value: value,
            ),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _unset(String key, {String? value}) async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runStandaloneOperation(
            'Unset $key (${scope.name})',
            () => git_api.unsetGitConfigValue(
              path: widget.repositoryPath,
              scope: scope,
              key: key,
              value: value,
            ),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _addAdvanced() async {
    final draft = await _showConfigDraftDialog(context, widget.strings);
    if (draft == null) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runStandaloneOperation(
            'Add ${draft.key} (${scope.name})',
            () => git_api.addGitConfigValue(
              path: widget.repositoryPath,
              scope: scope,
              key: draft.key,
              value: draft.value,
            ),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final directEntries = _scopeEntries.toList();
    return AlertDialog(
      title: Text(strings.gitSettings),
      content: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            SegmentedButton<GitConfigScope>(
              segments: [
                ButtonSegment(
                  value: GitConfigScope.local,
                  enabled: widget.repositoryPath != null,
                  label: Text(strings.repositoryScope),
                ),
                ButtonSegment(
                  value: GitConfigScope.global,
                  label: Text(strings.globalScope),
                ),
              ],
              selected: {scope},
              onSelectionChanged: (value) =>
                  setState(() => scope = value.first),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        Text(
                          strings.text('자주 쓰는 설정', 'Common settings'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        ..._commonGitConfigKeys
                            .where(
                              (key) =>
                                  scope == GitConfigScope.global ||
                                  key != 'init.defaultBranch',
                            )
                            .map((key) {
                              final direct = _directEntry(key);
                              final effective = _effectiveEntry(key);
                              final inherited =
                                  direct == null && effective != null;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(key),
                                subtitle: Text(
                                  direct == null
                                      ? (effective == null
                                            ? strings.noItems
                                            : '${effective.value} · ${strings.inherited} (${effective.scope.name}: ${effective.origin})')
                                      : '${direct.value}\n${direct.origin}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: inherited
                                    ? const Icon(Icons.subdirectory_arrow_right)
                                    : const Icon(Icons.tune, size: 20),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: strings.edit,
                                      onPressed: () => _setValue(key),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: strings.text('설정 해제', 'Unset'),
                                      onPressed: direct == null
                                          ? null
                                          : () => _unset(key),
                                      icon: const Icon(Icons.undo, size: 19),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search),
                                  labelText: strings.advancedConfig,
                                ),
                                onChanged: (value) =>
                                    setState(() => query = value),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: _addAdvanced,
                              icon: const Icon(Icons.add),
                              label: Text(strings.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (directEntries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(strings.noItems),
                          )
                        else
                          ...directEntries.map(
                            (entry) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.key),
                              subtitle: Text(
                                '${entry.value}\n${entry.origin}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: strings.edit,
                                    onPressed: () => _setValue(
                                      entry.key,
                                      initialValue: entry.value,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 19,
                                    ),
                                  ),
                                  Tooltip(
                                    message: strings.text(
                                      '이 값만 삭제합니다.',
                                      'Remove only this value.',
                                    ),
                                    child: IconButton(
                                      tooltip: strings.delete,
                                      onPressed: () => _unset(
                                        entry.key,
                                        value: entry.sensitive
                                            ? null
                                            : entry.value,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _load, child: Text(strings.refresh)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.close),
        ),
      ],
    );
  }
}

typedef _ConfigDraft = ({String key, String value});

Future<_ConfigDraft?> _showConfigDraftDialog(
  BuildContext context,
  GitFrontStrings strings,
) async {
  final key = TextEditingController();
  final value = TextEditingController();
  final result = await showDialog<_ConfigDraft>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.advancedConfig),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: key,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: value,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (key.text.trim().isEmpty) return;
            Navigator.pop(context, (key: key.text.trim(), value: value.text));
          },
          child: Text(strings.add),
        ),
      ],
    ),
  );
  key.dispose();
  value.dispose();
  return result;
}

class _RemoteSettingsDialog extends ConsumerStatefulWidget {
  const _RemoteSettingsDialog({
    required this.strings,
    required this.repositoryPath,
  });
  final GitFrontStrings strings;
  final String repositoryPath;

  @override
  ConsumerState<_RemoteSettingsDialog> createState() =>
      _RemoteSettingsDialogState();
}

class _RemoteSettingsDialogState extends ConsumerState<_RemoteSettingsDialog> {
  List<RemoteDetails>? remotes;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await git_api.listRemoteDetails(
        path: widget.repositoryPath,
      );
      if (mounted) {
        setState(() {
          remotes = value;
          error = null;
        });
      }
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _edit([RemoteDetails? existing]) async {
    final draft = await _showRemoteDialog(context, widget.strings, existing);
    if (draft == null) return;
    try {
      final controller = ref.read(gitFrontProvider.notifier);
      if (existing == null) {
        await controller.runOperation(
          'Add remote ${draft.name}',
          (path) => git_api.addRemote(
            path: path,
            name: draft.name,
            fetchUrl: draft.fetchUrl,
          ),
        );
      } else {
        var activeName = existing.name;
        if (draft.name != existing.name) {
          await controller.runOperation(
            'Rename remote ${existing.name}',
            (path) => git_api.renameRemote(
              path: path,
              oldName: existing.name,
              newName: draft.name,
            ),
          );
          activeName = draft.name;
        }
        await controller.runOperation(
          'Update remote $activeName',
          (path) => git_api.updateRemote(
            path: path,
            name: activeName,
            fetchUrl: draft.fetchUrl,
            pushUrl: draft.pushUrl,
          ),
        );
      }
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _remove(RemoteDetails remote) async {
    final confirmed = await _confirmTyped(
      context,
      title: widget.strings.text('원격 삭제', 'Remove remote'),
      value: remote.name,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Remove remote ${remote.name}',
            (path) => git_api.removeRemote(path: path, name: remote.name),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.manageRemotes),
      content: SizedBox(
        width: 650,
        height: 440,
        child: Column(
          children: [
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: remotes == null
                  ? const Center(child: CircularProgressIndicator())
                  : remotes!.isEmpty
                  ? Center(child: Text(widget.strings.noItems))
                  : ListView.builder(
                      itemCount: remotes!.length,
                      itemBuilder: (context, index) {
                        final remote = remotes![index];
                        final fetch = remote.fetchUrls.join('\n');
                        final push = remote.pushUrls.isEmpty
                            ? widget.strings.text(
                                'Fetch URL 사용',
                                'Uses fetch URL',
                              )
                            : remote.pushUrls.join('\n');
                        final multipleUrls =
                            remote.fetchUrls.length > 1 ||
                            remote.pushUrls.length > 1;
                        return ListTile(
                          leading: const Icon(Icons.cloud_outlined),
                          title: Text(remote.name),
                          subtitle: Text(
                            'Fetch: $fetch\nPush: $push${multipleUrls ? '\n${widget.strings.text('복수 URL은 고급 Git 설정에서 관리하세요.', 'Manage multiple URLs in advanced Git settings.')}' : ''}',
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') unawaited(_edit(remote));
                              if (value == 'delete') unawaited(_remove(remote));
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(widget.strings.edit),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(widget.strings.delete),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: Text(widget.strings.add),
        ),
        TextButton(onPressed: _load, child: Text(widget.strings.refresh)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.close),
        ),
      ],
    );
  }
}

typedef _RemoteDraft = ({String name, String fetchUrl, String? pushUrl});

Future<_RemoteDraft?> _showRemoteDialog(
  BuildContext context,
  GitFrontStrings strings,
  RemoteDetails? existing,
) async {
  final firstFetch = existing == null || existing.fetchUrls.isEmpty
      ? null
      : existing.fetchUrls.first;
  final firstPush = existing == null || existing.pushUrls.isEmpty
      ? null
      : existing.pushUrls.first;
  final redacted = firstFetch?.contains('***') ?? false;
  final name = TextEditingController(text: existing?.name ?? 'origin');
  final fetch = TextEditingController(text: redacted ? '' : firstFetch ?? '');
  final push = TextEditingController(text: firstPush ?? '');
  final result = await showDialog<_RemoteDraft>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        existing == null ? strings.text('원격 추가', 'Add remote') : strings.edit,
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: strings.remoteName),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: fetch,
              decoration: InputDecoration(
                labelText: 'Fetch URL',
                helperText: redacted
                    ? strings.text(
                        '보호된 자격 증명 URL을 다시 입력하세요.',
                        'Re-enter the protected credential URL.',
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: push,
              decoration: const InputDecoration(
                labelText: 'Push URL (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty || fetch.text.trim().isEmpty) return;
            Navigator.pop(context, (
              name: name.text.trim(),
              fetchUrl: fetch.text.trim(),
              pushUrl: push.text.trim().isEmpty ? null : push.text.trim(),
            ));
          },
          child: Text(strings.save),
        ),
      ],
    ),
  );
  name.dispose();
  fetch.dispose();
  push.dispose();
  return result;
}

class _SparseCheckoutDialog extends ConsumerStatefulWidget {
  const _SparseCheckoutDialog({
    required this.strings,
    required this.repositoryPath,
  });
  final GitFrontStrings strings;
  final String repositoryPath;

  @override
  ConsumerState<_SparseCheckoutDialog> createState() =>
      _SparseCheckoutDialogState();
}

class _SparseCheckoutDialogState extends ConsumerState<_SparseCheckoutDialog> {
  final directories = TextEditingController();
  SparseCheckoutState? sparse;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await git_api.readSparseCheckout(
        path: widget.repositoryPath,
      );
      if (mounted) {
        setState(() {
          sparse = value;
          directories.text = value.directories.join('\n');
          error = null;
        });
      }
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _apply() async {
    final values = directories.text
        .split(RegExp(r'[\r\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.isEmpty) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Set sparse checkout',
            (path) =>
                git_api.setSparseCheckout(path: path, directories: values),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  Future<void> _disable() async {
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Disable sparse checkout',
            (path) => git_api.disableSparseCheckout(path: path),
          );
      await _load();
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
  }

  @override
  void dispose() {
    directories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.sparseCheckout),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sparse == null
                  ? widget.strings.text('상태 확인 중…', 'Checking status…')
                  : sparse!.enabled
                  ? widget.strings.text(
                      'Cone mode 활성화됨',
                      'Cone mode is enabled',
                    )
                  : widget.strings.text('비활성화됨', 'Disabled'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: directories,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: widget.strings.sparseDirectories,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: sparse?.enabled == true ? _disable : null,
          child: Text(widget.strings.disable),
        ),
        FilledButton(onPressed: _apply, child: Text(widget.strings.save)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.close),
        ),
      ],
    );
  }
}

class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  UpdateStatus? status;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final current = status;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: const Text('Updates'),
      subtitle: Text(current?.message ?? 'Check GitHub Releases for updates'),
      trailing: FilledButton.tonal(
        onPressed: busy ? null : _performAction,
        child: Text(switch (current?.state) {
          UpdateState.available => 'Download',
          UpdateState.downloaded => 'Restart & update',
          _ => 'Check',
        }),
      ),
    );
  }

  Future<void> _performAction() async {
    setState(() => busy = true);
    try {
      final current = status;
      if (current?.state == UpdateState.available) {
        status = await update_api.downloadUpdate();
      } else if (current?.state == UpdateState.downloaded) {
        await update_api.applyUpdateAndRestart();
      } else {
        status = await update_api.checkForUpdate();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _OperationLog extends ConsumerWidget {
  const _OperationLog({required this.strings});
  final GitFrontStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(
      gitFrontProvider.select((state) => state.operationLog),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                strings.operationLog,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: ref
                    .read(gitFrontProvider.notifier)
                    .clearOperationLog,
                child: Text(strings.clear),
              ),
            ],
          ),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: log.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No operations yet.'),
                    )
                  : SelectionArea(
                      child: ListView.separated(
                        key: const ValueKey('virtualized-operation-log'),
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: log.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => Text(
                          log[log.length - index - 1],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.strings,
    required this.recentRepositories,
    required this.onCreate,
    required this.onRecent,
    required this.onOpen,
    required this.onClone,
  });

  final GitFrontStrings strings;
  final List<String> recentRepositories;
  final VoidCallback onCreate;
  final ValueChanged<String> onRecent;
  final VoidCallback onOpen;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_split_rounded, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              strings.noRepository,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(strings.noRepositoryDescription, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(strings.createRepository),
                ),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open),
                  label: Text(strings.openRepository),
                ),
                OutlinedButton.icon(
                  onPressed: onClone,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(strings.cloneRepository),
                ),
              ],
            ),
            if (recentRepositories.isNotEmpty) ...[
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  strings.recentRepositories,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              ...recentRepositories
                  .take(5)
                  .map(
                    (path) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.history, size: 19),
                      title: Text(
                        path.split(RegExp(r'[\\/]')).last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onRecent(path),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PanelResizer extends StatelessWidget {
  const _PanelResizer({
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
  });

  final VoidCallback onStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => onStart(),
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        onHorizontalDragCancel: onEnd,
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(width: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.tab,
    required this.onTap,
    required this.onAction,
  });

  final BranchInfo branch;
  final RepoTabState tab;
  final VoidCallback? onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: branch.isHead,
      leading: Icon(
        branch.isHead ? Icons.radio_button_checked : Icons.call_split,
        size: 17,
      ),
      title: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: branch.ahead == 0 && branch.behind == 0
          ? null
          : Text('↑${branch.ahead} ↓${branch.behind}'),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        enabled: !tab.busy,
        onSelected: onAction,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (!branch.isHead) ...const [
            PopupMenuItem(value: 'merge', child: Text('Merge into current')),
            PopupMenuItem(
              value: 'rebase',
              child: Text('Rebase current onto this'),
            ),
            PopupMenuItem(
              value: 'interactive',
              child: Text('Interactive rebase…'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('Delete…')),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.kind});
  final ChangeKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      ChangeKind.added => ('A', Colors.green),
      ChangeKind.modified => ('M', Colors.orange),
      ChangeKind.deleted => ('D', Colors.red),
      ChangeKind.renamed => ('R', Colors.blue),
      ChangeKind.typeChanged => ('T', Colors.purple),
      ChangeKind.untracked => ('?', Colors.teal),
      ChangeKind.conflicted => ('!', Colors.redAccent),
      ChangeKind.unreadable => ('×', Colors.grey),
      ChangeKind.none => ('·', Colors.grey),
    };
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _GraphDot extends StatelessWidget {
  const _GraphDot({required this.lane});
  final GraphLane lane;

  @override
  Widget build(BuildContext context) {
    final palette = [
      Theme.of(context).colorScheme.primary,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.blue,
    ];
    return SizedBox(
      width: 32,
      child: Align(
        alignment: Alignment(
          -1 + (lane.column.clamp(0, 4).toDouble() * 0.45),
          0,
        ),
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette[lane.column.toInt() % palette.length],
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _textPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  bool allowEmpty = false,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (!allowEmpty && value.isEmpty) return;
            Navigator.pop(context, value);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> _confirmTyped(
  BuildContext context, {
  required String title,
  required String value,
}) async {
  final controller = TextEditingController();
  final result =
      await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Type the value below to confirm this destructive action.',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: controller.text == value
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      ) ??
      false;
  controller.dispose();
  return result;
}

String _formatTimestamp(int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}
