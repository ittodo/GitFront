import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

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
              onOpen: () => _openRepository(strings),
              onClone: () => _showCloneDialog(strings),
              onSettings: () => _showSettings(strings),
              onShowLog: () => _showOperationLog(strings),
            ),
            if (state.tabs.isNotEmpty)
              _RepositoryTabs(
                state: state,
                onSelect: ref.read(gitFrontProvider.notifier).activateTab,
                onClose: ref.read(gitFrontProvider.notifier).closeTab,
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
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _CloneDialog(strings: strings),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(gitFrontProvider.notifier).clone(result.$1, result.$2);
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
    required this.onOpen,
    required this.onClone,
    required this.onSettings,
    required this.onShowLog,
  });

  final GitFrontStrings strings;
  final GitFrontState state;
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
    required this.state,
    required this.onSelect,
    required this.onClose,
  });

  final GitFrontState state;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: state.tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final tab = state.tabs[index];
          final selected = state.activeIndex == index;
          final dirty = tab.snapshot.files.isNotEmpty;
          return Material(
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onSelect(index),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dirty)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 7),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(tab.snapshot.name),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => onClose(index),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
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
                  label: Text(
                    '${strings.changes} (${tab.snapshot.files.length})',
                  ),
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
    return _VirtualSidebarList(
      strings: strings,
      tab: tab,
      onCreateBranch: () => _createBranch(context, ref),
      onSaveStash: () => _saveStash(context, ref),
      onSwitchBranch: (branch) => _switchBranch(ref, branch),
      onBranchAction: (branch, action) =>
          _branchAction(context, ref, branch, action),
      onShowStash: (stash) => _showStash(context, stash),
      onStashAction: (stash, action) =>
          _stashAction(context, ref, stash, action),
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

class _VirtualSidebarList extends StatefulWidget {
  const _VirtualSidebarList({
    required this.strings,
    required this.tab,
    required this.onCreateBranch,
    required this.onSaveStash,
    required this.onSwitchBranch,
    required this.onBranchAction,
    required this.onShowStash,
    required this.onStashAction,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final VoidCallback onCreateBranch;
  final VoidCallback onSaveStash;
  final ValueChanged<BranchInfo> onSwitchBranch;
  final _BranchActionCallback onBranchAction;
  final ValueChanged<StashEntry> onShowStash;
  final _StashActionCallback onStashAction;

  @override
  State<_VirtualSidebarList> createState() => _VirtualSidebarListState();
}

class _VirtualSidebarListState extends State<_VirtualSidebarList> {
  late List<_SidebarListItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  @override
  void didUpdateWidget(covariant _VirtualSidebarList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.tab.snapshot.branches,
          widget.tab.snapshot.branches,
        ) ||
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
    for (final branch in widget.tab.snapshot.branches) {
      (branch.isRemote ? remotes : locals).add(branch);
    }
    return [
      _SidebarSectionItem(widget.strings.branches, _SidebarSection.branches),
      ...locals.map(_SidebarBranchItem.new),
      const _SidebarGapItem(),
      _SidebarSectionItem(widget.strings.remotes, _SidebarSection.remotes),
      ...remotes.map(_SidebarRemoteItem.new),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      cacheExtent: 180,
      itemCount: _items.length,
      itemExtentBuilder: (index, _) => switch (_items[index]) {
        _SidebarSectionItem() => 34,
        _SidebarBranchItem(:final branch) =>
          branch.ahead == 0 && branch.behind == 0 ? 48 : 60,
        _SidebarRemoteItem() => 48,
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
            _SidebarSection.remotes => null,
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
        _SidebarRemoteItem(:final branch) => ListTile(
          dense: true,
          leading: const Icon(Icons.cloud_outlined, size: 16),
          title: Text(
            branch.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    if (tab.snapshot.files.isEmpty) {
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

class _VirtualChangeList extends StatefulWidget {
  const _VirtualChangeList({
    required this.strings,
    required this.tab,
    required this.onError,
  });

  final GitFrontStrings strings;
  final RepoTabState tab;
  final ValueChanged<Object> onError;

  @override
  State<_VirtualChangeList> createState() => _VirtualChangeListState();
}

class _VirtualChangeListState extends State<_VirtualChangeList> {
  late List<_ChangeListItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  @override
  void didUpdateWidget(covariant _VirtualChangeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab.snapshot.files, widget.tab.snapshot.files) ||
        oldWidget.strings.locale.languageCode !=
            widget.strings.locale.languageCode) {
      _items = _buildItems();
    }
  }

  List<_ChangeListItem> _buildItems() {
    final conflicts = <FileChange>[];
    final staged = <FileChange>[];
    final unstaged = <FileChange>[];
    for (final file in widget.tab.snapshot.files) {
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
    return ListView.builder(
      key: const ValueKey('virtualized-change-list'),
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
          onError: widget.onError,
        ),
      },
    );
  }
}

class _ChangeTile extends ConsumerWidget {
  const _ChangeTile({
    super.key,
    required this.file,
    required this.staged,
    required this.tab,
    required this.onError,
  });

  final FileChange file;
  final bool staged;
  final RepoTabState tab;
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
      leading: _StatusBadge(kind: kind),
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

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stagedCount = widget.tab.snapshot.files
        .where((file) => file.staged != ChangeKind.none)
        .length;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: widget.strings.commitMessage,
              isDense: true,
            ),
            onSubmitted: (_) => _commit(stagedCount),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: stagedCount == 0 || widget.tab.busy
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
    if (stagedCount == 0 || _message.text.trim().isEmpty) return;
    try {
      await ref
          .read(gitFrontProvider.notifier)
          .runOperation(
            'Commit',
            (path) =>
                git_api.createCommit(path: path, message: _message.text.trim()),
            reloadHistory: true,
          );
      _message.clear();
    } catch (error) {
      widget.onError(error);
    }
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
      return const Center(child: Text('No commits'));
    }
    return ListView.builder(
      key: const ValueKey('virtualized-commit-list'),
      cacheExtent: 192,
      itemExtent: 64,
      itemCount: tab.commits.length + (tab.nextOffset == null ? 0 : 1),
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

  bool get _canMutate =>
      !widget.tab.busy && widget.tab.snapshot.state == RepositoryState.clean;

  bool get _canMoveBranch =>
      _canMutate &&
      widget.tab.snapshot.headName != null &&
      widget.tab.snapshot.headOid != widget.commit.oid;

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
          onPressed: _canMutate ? () => _runSequence(false) : null,
          child: Text(strings.cherryPick),
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
            _focusCommit();
            controller.open();
          },
        },
        child: Focus(
          focusNode: _focusNode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              _focusCommit();
              controller.open(position: details.localPosition);
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
                        onPressed: () {
                          _focusCommit();
                          controller.open();
                        },
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
    final title = revert
        ? widget.strings.revertCommit
        : widget.strings.cherryPick;
    final confirmed = await _confirmAction(
      context,
      strings: widget.strings,
      title: title,
      message: '${widget.commit.shortOid} · ${widget.commit.summary}',
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

  @override
  void initState() {
    super.initState();
    items = _buildItems();
  }

  @override
  void didUpdateWidget(covariant _DiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
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
        for (final line in hunk.lines) {
          result.add(
            sideBySide
                ? _DiffSideLine(line, language)
                : _DiffUnifiedLine(line, language),
          );
        }
      }
    }
    return result;
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = items[index];
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
      _DiffUnifiedLine(:final line, :final language) => _DiffLineRow(
        line: line,
        language: language,
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
  const _DiffUnifiedLine(this.line, this.language);
  final DiffLine line;
  final String language;
}

class _DiffSideLine extends _DiffListItem {
  const _DiffSideLine(this.line, this.language);
  final DiffLine line;
  final String language;
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    required this.line,
    required this.language,
    this.showOldNumber = true,
    this.showNewNumber = true,
  });
  final DiffLine line;
  final String language;
  final bool showOldNumber;
  final bool showNewNumber;

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

class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.strings});
  final GitFrontStrings strings;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  final url = TextEditingController();
  final destination = TextEditingController();

  @override
  void dispose() {
    url.dispose();
    destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.cloneRepository),
      content: SizedBox(
        width: 540,
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
          ],
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
            Navigator.pop(context, (url.text.trim(), destination.text.trim()));
          },
          child: Text(widget.strings.cloneRepository),
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
        width: 440,
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
                ButtonSegment(value: AppLanguage.system, label: Text('System')),
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
            Text(strings.theme, style: Theme.of(context).textTheme.labelLarge),
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
            const _UpdateCard(),
          ],
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
    required this.onRecent,
    required this.onOpen,
    required this.onClone,
  });

  final GitFrontStrings strings;
  final List<String> recentRepositories;
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
