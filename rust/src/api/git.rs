use crate::api::models::*;
use crate::frb_generated::StreamSink;
use git2::{
    BranchType, DiffDelta, DiffOptions, ErrorCode, ObjectType, Oid, Patch, Repository,
    RepositoryState as GitRepositoryState, Sort, Status, StatusOptions,
};
use notify::{RecursiveMode, Watcher};
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use regex::Regex;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{BufRead, BufReader, Write};
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use uuid::Uuid;

const MAX_RENDER_BYTES: u64 = 5 * 1024 * 1024;
type HeadInformation = (Option<String>, Option<String>, Option<String>, i64, i64);

static GENERATIONS: Lazy<Mutex<HashMap<String, u64>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static REPOSITORY_LOCKS: Lazy<Mutex<HashMap<String, Arc<Mutex<()>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static GLOBAL_GIT_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));
static HISTORY_CACHES: Lazy<Mutex<HashMap<String, HistoryCache>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CHERRY_PICK_ASSESSMENTS: Lazy<Mutex<HashMap<String, CherryPickApplicability>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CHANGE_CACHES: Lazy<Mutex<HashMap<String, ChangeCache>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static BRANCH_CACHES: Lazy<Mutex<HashMap<String, BranchCache>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static SUBMODULE_CACHES: Lazy<Mutex<HashMap<String, SubmoduleCache>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static ACTIVE_GIT_OPERATIONS: Lazy<Mutex<HashMap<String, u32>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CANCELLED_GIT_OPERATIONS: Lazy<Mutex<HashSet<String>>> =
    Lazy::new(|| Mutex::new(HashSet::new()));
static CREDENTIAL_URL: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)(https?://)([^/@\s:]+):([^/@\s]+)@").expect("valid credential regex")
});
static CREDENTIAL_USER_URL: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)(https?://)([^/@\s:]+)@").expect("valid credential user regex"));

#[derive(Debug)]
struct HistoryCache {
    head_key: String,
    oids: Vec<Oid>,
    commits: Vec<CommitSummary>,
    lanes: Vec<String>,
    requests: Option<mpsc::Sender<usize>>,
    responses: mpsc::Receiver<Result<(Vec<Oid>, bool), String>>,
    worker: Option<JoinHandle<()>>,
    exhausted: bool,
}

impl Drop for HistoryCache {
    fn drop(&mut self) {
        self.requests.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

#[derive(Debug)]
struct ChangeCache {
    generation: u64,
    files: Vec<FileChange>,
}

#[derive(Debug)]
struct BranchCache {
    generation: u64,
    branches: Vec<BranchInfo>,
}

#[derive(Debug)]
struct SubmoduleCache {
    fingerprint: String,
    submodules: Vec<SubmoduleInfo>,
}

pub fn git_version() -> Result<String, String> {
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    let output = command
        .arg("--version")
        .output()
        .map_err(|error| format!("Git was not found: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

pub fn git_capabilities() -> Result<GitCapabilities, String> {
    let version = git_version()?;
    let numbers = version
        .split_whitespace()
        .find(|part| {
            part.chars()
                .next()
                .is_some_and(|value| value.is_ascii_digit())
        })
        .unwrap_or_default()
        .split('.')
        .take(3)
        .map(|part| {
            part.chars()
                .take_while(|value| value.is_ascii_digit())
                .collect::<String>()
                .parse::<u32>()
                .unwrap_or_default()
        })
        .collect::<Vec<_>>();
    let major = numbers.first().copied().unwrap_or_default();
    let minor = numbers.get(1).copied().unwrap_or_default();
    let at_least = |required_minor| major > 2 || (major == 2 && minor >= required_minor);
    let subtree = run_subtree_capture(None, vec!["-h".to_owned()]);
    let (supports_subtree, subtree_diagnostic) = match subtree {
        Ok(output) if output.status.success() || output.status.code() == Some(129) => (true, None),
        Ok(output) => {
            let detail = [output.stdout, output.stderr].concat();
            (false, Some(redact(String::from_utf8_lossy(&detail).trim())))
        }
        Err(error) => (false, Some(error)),
    };
    Ok(GitCapabilities {
        version,
        supports_repository_setup: at_least(28),
        supports_fixed_value_config: at_least(31),
        supports_sparse_checkout: at_least(25),
        supports_subtree,
        subtree_diagnostic,
    })
}

pub fn open_repository(path: String) -> Result<RepositorySnapshot, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    build_snapshot(&repo)
}

pub fn refresh_repository(path: String) -> Result<RepositorySnapshot, String> {
    open_repository(path)
}

pub fn refresh_working_tree(path: String) -> Result<WorkingTreeSnapshot, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let canonical = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());
    let repository_path = display_path(&canonical);
    Ok(WorkingTreeSnapshot {
        generation: next_generation(&repository_path),
        state: map_repository_state(repo.state()),
        files: collect_status(&repo)?,
    })
}

pub fn open_repository_paged(
    path: String,
    change_limit: u32,
) -> Result<RepositorySnapshotPage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let mut snapshot = build_snapshot(&repo)?;
    let files = std::mem::take(&mut snapshot.files);
    let branches = std::mem::take(&mut snapshot.branches);
    let changes = replace_change_cache(
        snapshot.workdir.clone(),
        snapshot.generation,
        files,
        change_limit,
    );
    let branches =
        replace_branch_cache(snapshot.workdir.clone(), snapshot.generation, branches, 250);
    Ok(RepositorySnapshotPage {
        snapshot,
        changes,
        branches,
    })
}

pub fn refresh_repository_paged(
    path: String,
    change_limit: u32,
) -> Result<RepositorySnapshotPage, String> {
    open_repository_paged(path, change_limit)
}

pub fn refresh_working_tree_paged(
    path: String,
    change_limit: u32,
) -> Result<WorkingTreeSnapshotPage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let canonical = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());
    let repository_path = display_path(&canonical);
    let generation = next_generation(&repository_path);
    let files = collect_status(&repo)?;
    let changes = replace_change_cache(repository_path, generation, files, change_limit);
    Ok(WorkingTreeSnapshotPage {
        snapshot: WorkingTreeSnapshot {
            generation,
            state: map_repository_state(repo.state()),
            files: Vec::new(),
        },
        changes,
    })
}

pub fn list_changes_cursor(
    path: String,
    cursor: String,
    limit: u32,
) -> Result<FileChangePage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let cache_key = display_path(
        workdir
            .canonicalize()
            .unwrap_or_else(|_| workdir.to_path_buf()),
    );
    let (generation, position) = cursor
        .split_once(':')
        .ok_or_else(|| "The change cursor is invalid. Refresh the changes.".to_owned())?;
    let generation = generation
        .parse::<u64>()
        .map_err(|_| "The change cursor is invalid. Refresh the changes.".to_owned())?;
    let position = position
        .parse::<usize>()
        .map_err(|_| "The change cursor is invalid. Refresh the changes.".to_owned())?;
    let caches = CHANGE_CACHES.lock();
    let cache = caches
        .get(&cache_key)
        .filter(|cache| cache.generation == generation)
        .ok_or_else(|| "The working tree changed. Refresh the changes.".to_owned())?;
    if position > cache.files.len() {
        return Err("The change cursor is out of sequence. Refresh the changes.".to_owned());
    }
    Ok(change_page(cache, position, limit))
}

pub fn list_branches_cursor(
    path: String,
    cursor: String,
    limit: u32,
) -> Result<BranchPage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let cache_key = display_path(
        workdir
            .canonicalize()
            .unwrap_or_else(|_| workdir.to_path_buf()),
    );
    let (generation, position) = cursor
        .split_once(':')
        .ok_or_else(|| "The branch cursor is invalid. Refresh the branches.".to_owned())?;
    let generation = generation
        .parse::<u64>()
        .map_err(|_| "The branch cursor is invalid. Refresh the branches.".to_owned())?;
    let position = position
        .parse::<usize>()
        .map_err(|_| "The branch cursor is invalid. Refresh the branches.".to_owned())?;
    let caches = BRANCH_CACHES.lock();
    let cache = caches
        .get(&cache_key)
        .filter(|cache| cache.generation == generation)
        .ok_or_else(|| "The repository refs changed. Refresh the branches.".to_owned())?;
    if position > cache.branches.len() {
        return Err("The branch cursor is out of sequence. Refresh the branches.".to_owned());
    }
    Ok(branch_page(cache, position, limit))
}

pub fn get_cached_file_change(
    path: String,
    file_path: String,
) -> Result<Option<FileChange>, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let cache_key = display_path(
        workdir
            .canonicalize()
            .unwrap_or_else(|_| workdir.to_path_buf()),
    );
    Ok(CHANGE_CACHES.lock().get(&cache_key).and_then(|cache| {
        cache
            .files
            .iter()
            .find(|file| file.path == file_path)
            .cloned()
    }))
}

pub fn watch_repository(
    path: String,
    sink: StreamSink<RepositoryWatchEvent>,
) -> Result<(), String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories cannot be watched.".to_owned())?
        .to_path_buf();
    let repository_path = display_path(&workdir);
    let (sender, receiver) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |event| {
        let _ = sender.send(event);
    })
    .map_err(|error| error.to_string())?;
    watcher
        .watch(&workdir, RecursiveMode::Recursive)
        .map_err(|error| error.to_string())?;

    loop {
        let first = receiver.recv().map_err(|error| error.to_string())?;
        let mut paths = match first {
            Ok(event) => event.paths,
            Err(error) => return Err(error.to_string()),
        };
        loop {
            match receiver.recv_timeout(Duration::from_millis(300)) {
                Ok(Ok(event)) => paths.extend(event.paths),
                Ok(Err(error)) => return Err(error.to_string()),
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
        }
        let mut unique = HashSet::new();
        let paths = paths
            .into_iter()
            .map(|path| display_path(path.strip_prefix(&workdir).unwrap_or(&path)))
            .filter(|path| unique.insert(path.clone()))
            .collect();
        if sink
            .add(RepositoryWatchEvent {
                repository_path: repository_path.clone(),
                paths,
            })
            .is_err()
        {
            return Ok(());
        }
    }
}

fn build_snapshot(repo: &Repository) -> Result<RepositorySnapshot, String> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let canonical = workdir
        .canonicalize()
        .unwrap_or_else(|_| workdir.to_path_buf());
    let repository_path = display_path(&canonical);
    let name = canonical
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| repository_path.clone());

    let (head_name, head_oid, upstream, ahead, behind) = head_information(repo)?;
    let files = collect_status(repo)?;
    let branches = collect_branches(repo, head_name.as_deref(), ahead, behind)?;
    let remotes = collect_remotes(repo)?;
    let stashes = collect_stashes(repo)?;
    let generation = next_generation(&repository_path);

    Ok(RepositorySnapshot {
        repository_path,
        workdir: display_path(&canonical),
        name,
        head_name,
        head_oid,
        upstream,
        ahead,
        behind,
        state: map_repository_state(repo.state()),
        generation,
        files,
        branches,
        remotes,
        stashes,
    })
}

fn head_information(repo: &Repository) -> Result<HeadInformation, String> {
    let head = match repo.head() {
        Ok(head) => head,
        Err(error) if error.code() == ErrorCode::UnbornBranch => {
            let symbolic = repo.find_reference("HEAD").ok().and_then(|reference| {
                reference
                    .symbolic_target()
                    .ok()
                    .flatten()
                    .map(short_reference)
            });
            return Ok((symbolic, None, None, 0, 0));
        }
        Err(error) if error.code() == ErrorCode::NotFound => return Ok((None, None, None, 0, 0)),
        Err(error) => return Err(format_git_error(error)),
    };

    let head_name = if head.is_branch() {
        head.shorthand().ok().map(str::to_owned)
    } else {
        None
    };
    let head_oid = head.target().map(|oid| oid.to_string());
    let Some(branch_name) = head_name.as_ref() else {
        return Ok((None, head_oid, None, 0, 0));
    };
    let branch = repo
        .find_branch(branch_name, BranchType::Local)
        .map_err(format_git_error)?;
    let Ok(upstream_branch) = branch.upstream() else {
        return Ok((head_name, head_oid, None, 0, 0));
    };
    let upstream_name = upstream_branch.name().ok().flatten().map(str::to_owned);
    let counts = match (branch.get().target(), upstream_branch.get().target()) {
        (Some(local), Some(remote)) => repo.graph_ahead_behind(local, remote).unwrap_or((0, 0)),
        _ => (0, 0),
    };
    Ok((
        head_name,
        head_oid,
        upstream_name,
        counts.0 as i64,
        counts.1 as i64,
    ))
}

fn collect_status(repo: &Repository) -> Result<Vec<FileChange>, String> {
    const INDEX_ENTRY_SKIP_WORKTREE: u16 = 0x4000;
    let sparse_excluded = repo
        .index()
        .map_err(format_git_error)?
        .iter()
        .filter(|entry| entry.flags_extended & INDEX_ENTRY_SKIP_WORKTREE != 0)
        .map(|entry| String::from_utf8_lossy(&entry.path).replace('\\', "/"))
        .collect::<HashSet<_>>();
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .renames_head_to_index(true)
        .renames_index_to_workdir(true)
        .include_unreadable(true);
    let statuses = repo
        .statuses(Some(&mut options))
        .map_err(format_git_error)?;
    let mut files = Vec::with_capacity(statuses.len());
    for entry in statuses.iter() {
        let status = entry.status();
        let path = entry.path().unwrap_or_default().replace('\\', "/");
        if sparse_excluded.contains(&path)
            && status.is_wt_deleted()
            && !status.is_index_deleted()
            && !status.is_conflicted()
        {
            continue;
        }
        let old_path = entry
            .head_to_index()
            .or_else(|| entry.index_to_workdir())
            .and_then(|delta| delta.old_file().path())
            .map(display_path)
            .filter(|old| old != &path);
        files.push(FileChange {
            path,
            old_path,
            staged: staged_kind(status),
            unstaged: unstaged_kind(status),
            conflicted: status.is_conflicted(),
            untracked: status.is_wt_new(),
        });
    }
    files.sort_by_cached_key(|file| (!file.conflicted, !file.untracked, file.path.to_lowercase()));
    Ok(files)
}

fn replace_change_cache(
    cache_key: String,
    generation: u64,
    files: Vec<FileChange>,
    limit: u32,
) -> FileChangePage {
    let mut caches = CHANGE_CACHES.lock();
    caches.insert(cache_key.clone(), ChangeCache { generation, files });
    if caches.len() > 8 {
        let oldest = caches.keys().find(|key| *key != &cache_key).cloned();
        if let Some(oldest) = oldest {
            caches.remove(&oldest);
        }
    }
    change_page(
        caches.get(&cache_key).expect("change cache inserted"),
        0,
        limit,
    )
}

fn change_page(cache: &ChangeCache, start: usize, limit: u32) -> FileChangePage {
    let end = start
        .saturating_add(limit.clamp(1, 1000) as usize)
        .min(cache.files.len());
    let staged_count = cache
        .files
        .iter()
        .filter(|file| file.staged != ChangeKind::None)
        .count();
    let unstaged_count = cache
        .files
        .iter()
        .filter(|file| file.unstaged != ChangeKind::None)
        .count();
    let conflict_count = cache.files.iter().filter(|file| file.conflicted).count();
    let untracked_count = cache.files.iter().filter(|file| file.untracked).count();
    FileChangePage {
        files: cache.files.get(start..end).unwrap_or_default().to_vec(),
        next_cursor: (end < cache.files.len()).then(|| format!("{}:{end}", cache.generation)),
        total_files: cache.files.len().min(u32::MAX as usize) as u32,
        staged_count: staged_count.min(u32::MAX as usize) as u32,
        unstaged_count: unstaged_count.min(u32::MAX as usize) as u32,
        conflict_count: conflict_count.min(u32::MAX as usize) as u32,
        untracked_count: untracked_count.min(u32::MAX as usize) as u32,
    }
}

fn replace_branch_cache(
    cache_key: String,
    generation: u64,
    branches: Vec<BranchInfo>,
    limit: u32,
) -> BranchPage {
    let mut caches = BRANCH_CACHES.lock();
    caches.insert(
        cache_key.clone(),
        BranchCache {
            generation,
            branches,
        },
    );
    if caches.len() > 8 {
        let oldest = caches.keys().find(|key| *key != &cache_key).cloned();
        if let Some(oldest) = oldest {
            caches.remove(&oldest);
        }
    }
    branch_page(
        caches.get(&cache_key).expect("branch cache inserted"),
        0,
        limit,
    )
}

fn branch_page(cache: &BranchCache, start: usize, limit: u32) -> BranchPage {
    let end = start
        .saturating_add(limit.clamp(1, 1000) as usize)
        .min(cache.branches.len());
    BranchPage {
        branches: cache.branches.get(start..end).unwrap_or_default().to_vec(),
        next_cursor: (end < cache.branches.len()).then(|| format!("{}:{end}", cache.generation)),
        total_branches: cache.branches.len().min(u32::MAX as usize) as u32,
    }
}

fn staged_kind(status: Status) -> ChangeKind {
    if status.is_conflicted() {
        ChangeKind::Conflicted
    } else if status.is_index_new() {
        ChangeKind::Added
    } else if status.is_index_modified() {
        ChangeKind::Modified
    } else if status.is_index_deleted() {
        ChangeKind::Deleted
    } else if status.is_index_renamed() {
        ChangeKind::Renamed
    } else if status.is_index_typechange() {
        ChangeKind::TypeChanged
    } else {
        ChangeKind::None
    }
}

fn unstaged_kind(status: Status) -> ChangeKind {
    if status.is_conflicted() {
        ChangeKind::Conflicted
    } else if status.is_wt_new() {
        ChangeKind::Untracked
    } else if status.is_wt_modified() {
        ChangeKind::Modified
    } else if status.is_wt_deleted() {
        ChangeKind::Deleted
    } else if status.is_wt_renamed() {
        ChangeKind::Renamed
    } else if status.is_wt_typechange() {
        ChangeKind::TypeChanged
    } else if status.contains(Status::WT_UNREADABLE) {
        ChangeKind::Unreadable
    } else {
        ChangeKind::None
    }
}

fn collect_branches(
    repo: &Repository,
    head_name: Option<&str>,
    head_ahead: i64,
    head_behind: i64,
) -> Result<Vec<BranchInfo>, String> {
    let mut branches = Vec::new();
    for branch_result in repo.branches(None).map_err(format_git_error)? {
        let (branch, branch_type) = branch_result.map_err(format_git_error)?;
        let is_remote = branch_type == BranchType::Remote;
        let name = branch
            .name()
            .map_err(format_git_error)?
            .unwrap_or("(invalid utf-8)")
            .to_owned();
        let full_name = branch.get().name().unwrap_or_default().to_owned();
        let oid = branch.get().target().map(|oid| oid.to_string());
        let mut upstream = None;
        let is_head = branch.is_head();
        let mut ahead = 0;
        let mut behind = 0;
        if !is_remote && let Ok(upstream_branch) = branch.upstream() {
            upstream = upstream_branch.name().ok().flatten().map(str::to_owned);
            // Walking the graph for every local branch makes repositories with
            // hundreds of branches painfully slow. The toolbar only needs live
            // counts for the checked-out branch; other branches keep their
            // upstream name and can be evaluated when they become current.
            if is_head && head_name == Some(name.as_str()) {
                ahead = head_ahead;
                behind = head_behind;
            }
        }
        branches.push(BranchInfo {
            name,
            full_name,
            oid,
            is_head,
            is_remote,
            upstream,
            ahead,
            behind,
        });
    }
    branches.sort_by_cached_key(|branch| {
        (
            !branch.is_head,
            branch.is_remote,
            branch.name.to_lowercase(),
        )
    });
    Ok(branches)
}

fn collect_remotes(repo: &Repository) -> Result<Vec<RemoteInfo>, String> {
    let names = repo.remotes().map_err(format_git_error)?;
    let mut remotes = Vec::new();
    for index in 0..names.len() {
        let Ok(Some(name)) = names.get(index) else {
            continue;
        };
        let remote = repo.find_remote(name).map_err(format_git_error)?;
        remotes.push(RemoteInfo {
            name: name.to_owned(),
            fetch_url: remote.url().ok().map(redact),
            push_url: remote
                .pushurl()
                .ok()
                .flatten()
                .or_else(|| remote.url().ok())
                .map(redact),
        });
    }
    Ok(remotes)
}

fn collect_stashes(repo: &Repository) -> Result<Vec<StashEntry>, String> {
    let mut repo = Repository::open(repo.path()).map_err(format_git_error)?;
    let mut stashes = Vec::new();
    repo.stash_foreach(|index, message, oid| {
        stashes.push(StashEntry {
            index: index as u32,
            message: message.to_owned(),
            oid: oid.to_string(),
        });
        true
    })
    .map_err(format_git_error)?;
    Ok(stashes)
}

pub fn list_commits(path: String, offset: u32, limit: u32) -> Result<CommitPage, String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    let mut revwalk = repo.revwalk().map_err(format_git_error)?;
    if let Err(error) = revwalk.push_head() {
        if error.code() == ErrorCode::UnbornBranch || error.code() == ErrorCode::NotFound {
            return Ok(CommitPage {
                commits: Vec::new(),
                next_offset: None,
            });
        }
        return Err(format_git_error(error));
    }
    revwalk
        .set_sorting(Sort::TOPOLOGICAL | Sort::TIME)
        .map_err(format_git_error)?;

    let requested = limit.clamp(1, 500) as usize;
    let mut raw = Vec::with_capacity(requested + 1);
    for oid_result in revwalk.skip(offset as usize).take(requested + 1) {
        let oid = oid_result.map_err(format_git_error)?;
        let commit = repo.find_commit(oid).map_err(format_git_error)?;
        raw.push(CommitSummary {
            oid: oid.to_string(),
            short_oid: oid.to_string()[..8].to_owned(),
            summary: commit
                .summary()
                .ok()
                .flatten()
                .unwrap_or("(no message)")
                .to_owned(),
            author_name: commit.author().name().unwrap_or("Unknown").to_owned(),
            author_email: commit.author().email().unwrap_or_default().to_owned(),
            authored_at: commit.author().when().seconds(),
            parent_oids: commit
                .parent_ids()
                .map(|parent| parent.to_string())
                .collect(),
            references: Vec::new(),
            lane: GraphLane {
                column: 0,
                parent_columns: Vec::new(),
            },
        });
    }
    let has_more = raw.len() > requested;
    raw.truncate(requested);
    let visible_oids = raw
        .iter()
        .filter_map(|commit| Oid::from_str(&commit.oid).ok())
        .collect::<HashSet<_>>();
    let references = references_by_oid(&repo, &visible_oids)?;
    for commit in &mut raw {
        if let Ok(oid) = Oid::from_str(&commit.oid) {
            commit.references = references.get(&oid).cloned().unwrap_or_default();
        }
    }
    assign_graph_lanes(&mut raw);
    Ok(CommitPage {
        commits: raw,
        next_offset: has_more.then_some(offset + requested as u32),
    })
}

fn start_history_cache(path: String, head_key: String) -> HistoryCache {
    let (request_sender, request_receiver) = mpsc::channel::<usize>();
    let (response_sender, response_receiver) = mpsc::channel::<Result<(Vec<Oid>, bool), String>>();
    let worker = thread::spawn(move || {
        let requested = match request_receiver.recv() {
            Ok(requested) => requested,
            Err(_) => return,
        };
        let repo = match Repository::discover(path) {
            Ok(repo) => repo,
            Err(error) => {
                let _ = response_sender.send(Err(format_git_error(error)));
                return;
            }
        };
        let mut revwalk = match repo.revwalk() {
            Ok(revwalk) => revwalk,
            Err(error) => {
                let _ = response_sender.send(Err(format_git_error(error)));
                return;
            }
        };
        if let Err(error) = revwalk.push_head() {
            if error.code() == ErrorCode::UnbornBranch || error.code() == ErrorCode::NotFound {
                let _ = response_sender.send(Ok((Vec::new(), true)));
            } else {
                let _ = response_sender.send(Err(format_git_error(error)));
            }
            return;
        }
        if let Err(error) = revwalk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME) {
            let _ = response_sender.send(Err(format_git_error(error)));
            return;
        }

        let mut requested = requested;
        loop {
            let mut oids = Vec::with_capacity(requested);
            let mut exhausted = false;
            for _ in 0..requested {
                match revwalk.next() {
                    Some(Ok(oid)) => oids.push(oid),
                    Some(Err(error)) => {
                        let _ = response_sender.send(Err(format_git_error(error)));
                        return;
                    }
                    None => {
                        exhausted = true;
                        break;
                    }
                }
            }
            if response_sender.send(Ok((oids, exhausted))).is_err() || exhausted {
                return;
            }
            requested = match request_receiver.recv() {
                Ok(requested) => requested,
                Err(_) => return,
            };
        }
    });

    HistoryCache {
        head_key,
        oids: Vec::new(),
        commits: Vec::new(),
        lanes: Vec::new(),
        requests: Some(request_sender),
        responses: response_receiver,
        worker: Some(worker),
        exhausted: false,
    }
}

fn ensure_history_oids(cache: &mut HistoryCache, required: usize) -> Result<(), String> {
    while cache.oids.len() < required && !cache.exhausted {
        let requested = required - cache.oids.len();
        cache
            .requests
            .as_ref()
            .ok_or_else(|| "The history reader stopped unexpectedly. Refresh the log.".to_owned())?
            .send(requested)
            .map_err(|_| "The history reader stopped unexpectedly. Refresh the log.".to_owned())?;
        let (oids, exhausted) = cache.responses.recv().map_err(|_| {
            "The history reader stopped unexpectedly. Refresh the log.".to_owned()
        })??;
        cache.oids.extend(oids);
        cache.exhausted = exhausted;
        if exhausted {
            cache.requests.take();
        }
    }
    Ok(())
}

/// Returns a stable cursor page without replaying or fully consuming the
/// revwalk for every page.
///
/// A background reader owns the revwalk and advances it only far enough to
/// produce the visible page plus one look-ahead commit. Commit metadata and
/// graph lanes are materialized lazily as pages become visible. A cursor is
/// tied to the current HEAD and is rejected after history changes.
pub fn list_commits_cursor(
    path: String,
    cursor: Option<String>,
    limit: u32,
) -> Result<CommitCursorPage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported in the desktop view.".to_owned())?;
    let cache_key = display_path(
        workdir
            .canonicalize()
            .unwrap_or_else(|_| workdir.to_path_buf()),
    );
    let head_key = repo
        .head()
        .ok()
        .and_then(|head| head.peel_to_commit().ok())
        .map(|commit| commit.id().to_string())
        .unwrap_or_else(|| "unborn".to_owned());

    let requested = limit.clamp(1, 500) as usize;
    let start = match cursor.as_deref() {
        None => 0,
        Some(value) => {
            let (cursor_head, position) = value
                .rsplit_once(':')
                .ok_or_else(|| "The history cursor is invalid. Refresh the log.".to_owned())?;
            if cursor_head != head_key {
                return Err("The repository history changed. Refresh the log.".to_owned());
            }
            position
                .parse::<usize>()
                .map_err(|_| "The history cursor is invalid. Refresh the log.".to_owned())?
        }
    };

    let mut caches = HISTORY_CACHES.lock();
    let rebuild = cursor.is_none()
        || caches
            .get(&cache_key)
            .is_none_or(|cache| cache.head_key != head_key);
    if rebuild {
        caches.insert(
            cache_key.clone(),
            start_history_cache(cache_key.clone(), head_key.clone()),
        );
        if caches.len() > 8 {
            let oldest = caches.keys().find(|key| *key != &cache_key).cloned();
            if let Some(oldest) = oldest {
                caches.remove(&oldest);
            }
        }
    }
    let cache = caches.get_mut(&cache_key).expect("history cache inserted");
    if start > cache.commits.len() {
        return Err("The history cursor is out of sequence. Refresh the log.".to_owned());
    }
    ensure_history_oids(cache, start.saturating_add(requested).saturating_add(1))?;
    let end = start.saturating_add(requested).min(cache.oids.len());
    if end > cache.commits.len() {
        let mut new_commits = Vec::with_capacity(end - cache.commits.len());
        for oid in &cache.oids[cache.commits.len()..end] {
            let commit = repo.find_commit(*oid).map_err(format_git_error)?;
            new_commits.push(CommitSummary {
                oid: oid.to_string(),
                short_oid: oid.to_string()[..8].to_owned(),
                summary: commit
                    .summary()
                    .ok()
                    .flatten()
                    .unwrap_or("(no message)")
                    .to_owned(),
                author_name: commit.author().name().unwrap_or("Unknown").to_owned(),
                author_email: commit.author().email().unwrap_or_default().to_owned(),
                authored_at: commit.author().when().seconds(),
                parent_oids: commit
                    .parent_ids()
                    .map(|parent| parent.to_string())
                    .collect(),
                references: Vec::new(),
                lane: GraphLane {
                    column: 0,
                    parent_columns: Vec::new(),
                },
            });
        }
        let visible_oids = new_commits
            .iter()
            .filter_map(|commit| Oid::from_str(&commit.oid).ok())
            .collect::<HashSet<_>>();
        let references = references_by_oid(&repo, &visible_oids)?;
        for commit in &mut new_commits {
            if let Ok(oid) = Oid::from_str(&commit.oid) {
                commit.references = references.get(&oid).cloned().unwrap_or_default();
            }
        }
        assign_graph_lanes_with_state(&mut new_commits, &mut cache.lanes);
        cache.commits.extend(new_commits);
    }

    Ok(CommitCursorPage {
        commits: cache.commits[start..end].to_vec(),
        next_cursor: (end < cache.oids.len() || !cache.exhausted)
            .then(|| format!("{head_key}:{end}")),
        // Until the reader reaches the end this is a lower bound, not an
        // eagerly computed repository-wide total.
        total_commits: cache.oids.len().min(u32::MAX as usize) as u32,
    })
}

pub fn get_commit_detail(path: String, oid: String) -> Result<CommitDetail, String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    let oid = Oid::from_str(&oid).map_err(format_git_error)?;
    let commit = repo.find_commit(oid).map_err(format_git_error)?;
    let tree = commit.tree().map_err(format_git_error)?;
    let parent_tree = if commit.parent_count() > 0 {
        Some(
            commit
                .parent(0)
                .map_err(format_git_error)?
                .tree()
                .map_err(format_git_error)?,
        )
    } else {
        None
    };
    let diff = repo
        .diff_tree_to_tree(parent_tree.as_ref(), Some(&tree), None)
        .map_err(format_git_error)?;
    let diff = convert_diff(&diff, false)?;
    Ok(CommitDetail {
        oid: oid.to_string(),
        message: commit.message().unwrap_or_default().to_owned(),
        author_name: commit.author().name().unwrap_or("Unknown").to_owned(),
        author_email: commit.author().email().unwrap_or_default().to_owned(),
        authored_at: commit.author().when().seconds(),
        committer_name: commit.committer().name().unwrap_or("Unknown").to_owned(),
        committer_email: commit.committer().email().unwrap_or_default().to_owned(),
        committed_at: commit.committer().when().seconds(),
        parent_oids: commit
            .parent_ids()
            .map(|parent| parent.to_string())
            .collect(),
        diff,
    })
}

pub fn compare_commits(
    path: String,
    from_oid: String,
    to_oid: String,
) -> Result<DiffDocument, String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    let from = find_commit(&repo, &from_oid)?;
    let to = find_commit(&repo, &to_oid)?;
    let from_tree = from.tree().map_err(format_git_error)?;
    let to_tree = to.tree().map_err(format_git_error)?;
    let diff = repo
        .diff_tree_to_tree(Some(&from_tree), Some(&to_tree), None)
        .map_err(format_git_error)?;
    convert_diff(&diff, false)
}

pub fn get_worktree_diff(
    path: String,
    file_path: Option<String>,
    staged: bool,
) -> Result<DiffDocument, String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    let mut options = DiffOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .show_untracked_content(true)
        .include_typechange(true)
        .context_lines(3);
    if let Some(file_path) = file_path.as_ref() {
        options.pathspec(file_path);
    }
    let diff = if staged {
        let head_tree = repo.head().ok().and_then(|head| head.peel_to_tree().ok());
        repo.diff_tree_to_index(head_tree.as_ref(), None, Some(&mut options))
            .map_err(format_git_error)?
    } else {
        repo.diff_index_to_workdir(None, Some(&mut options))
            .map_err(format_git_error)?
    };
    let mut document = convert_diff(&diff, staged)?;
    if let Some(file_path) = file_path {
        let args = if staged {
            vec![
                "diff".to_owned(),
                "--cached".to_owned(),
                "--".to_owned(),
                file_path,
            ]
        } else {
            vec!["diff".to_owned(), "--".to_owned(), file_path]
        };
        if let Ok(output) = run_git_capture(
            &display_path(repo.workdir().unwrap_or(repo.path())),
            args,
            &[],
        ) && output.status.success()
        {
            document.fingerprint = format!("{:x}", Sha256::digest(&output.stdout));
        }
    }
    Ok(document)
}

fn convert_diff(diff: &git2::Diff<'_>, staged: bool) -> Result<DiffDocument, String> {
    let mut files = Vec::new();
    for index in 0..diff.deltas().len() {
        let delta = diff
            .get_delta(index)
            .ok_or_else(|| "Missing diff delta.".to_owned())?;
        let old_size = delta.old_file().size();
        let new_size = delta.new_file().size();
        let too_large = old_size.max(new_size) > MAX_RENDER_BYTES;
        let binary = delta.flags().contains(git2::DiffFlags::BINARY);
        let mut file = DiffFile {
            old_path: delta.old_file().path().map(display_path),
            new_path: delta.new_file().path().map(display_path),
            status: delta_status(delta),
            binary,
            too_large,
            hunks: Vec::new(),
        };
        if !binary
            && !too_large
            && let Some(patch) = Patch::from_diff(diff, index).map_err(format_git_error)?
        {
            let mut invalid_encoding = false;
            for hunk_index in 0..patch.num_hunks() {
                let (hunk, line_count) = patch.hunk(hunk_index).map_err(format_git_error)?;
                let mut lines = Vec::with_capacity(line_count);
                for line_index in 0..line_count {
                    let line = patch
                        .line_in_hunk(hunk_index, line_index)
                        .map_err(format_git_error)?;
                    invalid_encoding |= std::str::from_utf8(line.content()).is_err();
                    let kind = match line.origin() {
                        '+' => DiffLineKind::Addition,
                        '-' => DiffLineKind::Deletion,
                        ' ' => DiffLineKind::Context,
                        _ => DiffLineKind::Header,
                    };
                    lines.push(DiffLine {
                        kind,
                        old_line: line.old_lineno(),
                        new_line: line.new_lineno(),
                        content: String::from_utf8_lossy(line.content()).into_owned(),
                    });
                }
                file.hunks.push(DiffHunk {
                    index: hunk_index as u32,
                    header: String::from_utf8_lossy(hunk.header()).trim_end().to_owned(),
                    old_start: hunk.old_start(),
                    old_lines: hunk.old_lines(),
                    new_start: hunk.new_start(),
                    new_lines: hunk.new_lines(),
                    lines,
                });
            }
            if invalid_encoding {
                file.binary = true;
                file.hunks.clear();
            }
        }
        files.push(file);
    }
    let mut hasher = Sha256::new();
    for file in &files {
        hasher.update(file.old_path.as_deref().unwrap_or_default());
        hasher.update(file.new_path.as_deref().unwrap_or_default());
        for hunk in &file.hunks {
            hasher.update(&hunk.header);
            for line in &hunk.lines {
                hasher.update(&line.content);
            }
        }
    }
    Ok(DiffDocument {
        fingerprint: format!("{:x}", hasher.finalize()),
        staged,
        files,
    })
}

fn delta_status(delta: DiffDelta<'_>) -> String {
    format!("{:?}", delta.status()).to_lowercase()
}

fn references_by_oid(
    repo: &Repository,
    visible_oids: &HashSet<Oid>,
) -> Result<HashMap<Oid, Vec<CommitReference>>, String> {
    let mut result: HashMap<Oid, Vec<CommitReference>> = HashMap::new();
    for reference_result in repo.references().map_err(format_git_error)? {
        let reference = reference_result.map_err(format_git_error)?;
        let Ok(full_name) = reference.name() else {
            continue;
        };
        let (kind, name) = if let Some(name) = full_name.strip_prefix("refs/heads/") {
            (CommitReferenceKind::LocalBranch, name)
        } else if let Some(name) = full_name.strip_prefix("refs/remotes/") {
            (CommitReferenceKind::RemoteBranch, name)
        } else if let Some(name) = full_name.strip_prefix("refs/tags/") {
            (CommitReferenceKind::Tag, name)
        } else {
            continue;
        };
        let target = match kind {
            CommitReferenceKind::Tag => reference
                .peel(ObjectType::Commit)
                .ok()
                .map(|commit| commit.id()),
            _ => reference.target().or_else(|| {
                reference
                    .resolve()
                    .ok()
                    .and_then(|resolved| resolved.target())
            }),
        };
        if let Some(target) = target
            && visible_oids.contains(&target)
        {
            result.entry(target).or_default().push(CommitReference {
                name: name.to_owned(),
                full_name: full_name.to_owned(),
                kind,
            });
        }
    }
    if let Ok(head) = repo.head()
        && let Ok(commit) = head.peel(ObjectType::Commit)
        && visible_oids.contains(&commit.id())
    {
        result
            .entry(commit.id())
            .or_default()
            .push(CommitReference {
                name: "HEAD".to_owned(),
                full_name: "HEAD".to_owned(),
                kind: CommitReferenceKind::Head,
            });
    }
    for references in result.values_mut() {
        references.sort_by_cached_key(|reference| {
            (
                reference_rank(&reference.kind),
                reference.name.to_lowercase(),
            )
        });
        references.dedup_by(|left, right| left.full_name == right.full_name);
    }
    Ok(result)
}

fn reference_rank(kind: &CommitReferenceKind) -> u8 {
    match kind {
        CommitReferenceKind::Head => 0,
        CommitReferenceKind::LocalBranch => 1,
        CommitReferenceKind::RemoteBranch => 2,
        CommitReferenceKind::Tag => 3,
    }
}

fn assign_graph_lanes(commits: &mut [CommitSummary]) {
    let mut lanes: Vec<String> = Vec::new();
    assign_graph_lanes_with_state(commits, &mut lanes);
}

fn assign_graph_lanes_with_state(commits: &mut [CommitSummary], lanes: &mut Vec<String>) {
    for commit in commits {
        let column = if let Some(index) = lanes.iter().position(|oid| oid == &commit.oid) {
            index
        } else {
            lanes.insert(0, commit.oid.clone());
            0
        };
        if commit.parent_oids.is_empty() {
            lanes.remove(column);
            commit.lane = GraphLane {
                column: column as u32,
                parent_columns: Vec::new(),
            };
            continue;
        }
        lanes[column] = commit.parent_oids[0].clone();
        for (offset, parent) in commit.parent_oids.iter().skip(1).enumerate() {
            if !lanes.contains(parent) {
                lanes.insert(column + offset + 1, parent.clone());
            }
        }
        let mut seen = HashSet::new();
        lanes.retain(|oid| seen.insert(oid.clone()));
        let parent_columns = commit
            .parent_oids
            .iter()
            .filter_map(|parent| lanes.iter().position(|lane| lane == parent))
            .map(|position| position as u32)
            .collect();
        commit.lane = GraphLane {
            column: column as u32,
            parent_columns,
        };
    }
}

pub fn stage_paths(path: String, paths: Vec<String>) -> Result<OperationResult, String> {
    let input = nul_pathspec(&paths)?;
    run_git(
        &path,
        vec![
            "add".to_owned(),
            "--pathspec-from-file=-".to_owned(),
            "--pathspec-file-nul".to_owned(),
        ],
        Some(input),
        &[],
    )
}

pub fn unstage_paths(path: String, paths: Vec<String>) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let input = nul_pathspec(&paths)?;
    let args = if repo.head().is_ok() {
        vec![
            "restore".to_owned(),
            "--staged".to_owned(),
            "--pathspec-from-file=-".to_owned(),
            "--pathspec-file-nul".to_owned(),
        ]
    } else {
        vec![
            "rm".to_owned(),
            "--cached".to_owned(),
            "--pathspec-from-file=-".to_owned(),
            "--pathspec-file-nul".to_owned(),
        ]
    };
    run_git(&path, args, Some(input), &[])
}

pub fn intent_to_add(path: String, paths: Vec<String>) -> Result<OperationResult, String> {
    let input = nul_pathspec(&paths)?;
    run_git(
        &path,
        vec![
            "add".to_owned(),
            "--intent-to-add".to_owned(),
            "--pathspec-from-file=-".to_owned(),
            "--pathspec-file-nul".to_owned(),
        ],
        Some(input),
        &[],
    )
}

pub fn apply_hunk(
    path: String,
    file_path: String,
    staged: bool,
    hunk_index: u32,
    expected_fingerprint: String,
    reverse: bool,
) -> Result<OperationResult, String> {
    let args = if staged {
        vec![
            "diff".to_owned(),
            "--cached".to_owned(),
            "--".to_owned(),
            file_path,
        ]
    } else {
        vec!["diff".to_owned(), "--".to_owned(), file_path]
    };
    let patch = run_git_capture(&path, args, &[])?;
    if !patch.status.success() {
        return Ok(result_from_output("load hunk", patch));
    }
    let patch_text = String::from_utf8_lossy(&patch.stdout).into_owned();
    let fingerprint = format!("{:x}", Sha256::digest(patch_text.as_bytes()));
    if fingerprint != expected_fingerprint {
        return Err(
            "The file changed after the diff was loaded. Refresh and try again.".to_owned(),
        );
    }
    let selected = select_hunk(&patch_text, hunk_index as usize)?;
    let mut apply_args = vec!["apply".to_owned()];
    if !reverse || staged {
        apply_args.push("--cached".to_owned());
    }
    if reverse {
        apply_args.push("--reverse".to_owned());
    }
    apply_args.push("--whitespace=nowarn".to_owned());
    apply_args.push("-".to_owned());
    run_git(&path, apply_args, Some(selected.into_bytes()), &[])
}

pub fn apply_hunk_lines(
    path: String,
    file_path: String,
    staged: bool,
    hunk_index: u32,
    line_indices: Vec<u32>,
    expected_fingerprint: String,
    reverse: bool,
) -> Result<OperationResult, String> {
    let args = if staged {
        vec![
            "diff".to_owned(),
            "--cached".to_owned(),
            "--".to_owned(),
            file_path,
        ]
    } else {
        vec!["diff".to_owned(), "--".to_owned(), file_path]
    };
    let patch = run_git_capture(&path, args, &[])?;
    if !patch.status.success() {
        return Ok(result_from_output("load selected lines", patch));
    }
    let patch_text = String::from_utf8_lossy(&patch.stdout).into_owned();
    let fingerprint = format!("{:x}", Sha256::digest(patch_text.as_bytes()));
    if fingerprint != expected_fingerprint {
        return Err(
            "The file changed after the diff was loaded. Refresh and try again.".to_owned(),
        );
    }
    let selected = select_hunk_lines(
        &patch_text,
        hunk_index as usize,
        &line_indices.into_iter().collect(),
        reverse,
    )?;
    let mut apply_args = vec!["apply".to_owned(), "--recount".to_owned()];
    if !reverse || staged {
        apply_args.push("--cached".to_owned());
    }
    if reverse {
        apply_args.push("--reverse".to_owned());
    }
    apply_args.push("--whitespace=nowarn".to_owned());
    apply_args.push("-".to_owned());
    run_git(&path, apply_args, Some(selected.into_bytes()), &[])
}

pub fn discard_file(
    path: String,
    file_path: String,
    untracked: bool,
) -> Result<OperationResult, String> {
    if untracked {
        let repo = Repository::discover(&path).map_err(format_git_error)?;
        let target = safe_worktree_path(&repo, &file_path)?;
        trash::delete(&target)
            .map_err(|error| format!("Could not move file to the Recycle Bin: {error}"))?;
        return Ok(OperationResult {
            success: true,
            exit_code: 0,
            summary: "Moved untracked file to the Recycle Bin.".to_owned(),
            stdout: String::new(),
            stderr: String::new(),
        });
    }
    run_git(
        &path,
        vec![
            "restore".to_owned(),
            "--worktree".to_owned(),
            "--".to_owned(),
            file_path,
        ],
        None,
        &[],
    )
}

pub fn create_commit(path: String, message: String) -> Result<OperationResult, String> {
    create_commit_with_options(
        path,
        CommitOptions {
            message: Some(message),
            amend: false,
            signoff: false,
            signing: CommitSigningMode::UseConfig,
            author_name: None,
            author_email: None,
            authored_at: None,
            allow_empty: false,
            fixup_target: None,
            squash_target: None,
        },
    )
}

pub fn load_commit_defaults(path: String) -> Result<CommitDefaults, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let config = repo.config().map_err(format_git_error)?;
    let cleanup = config.get_string("commit.cleanup").ok();
    let signing_enabled = config.get_bool("commit.gpgsign").unwrap_or(false);
    let previous_message = repo
        .head()
        .ok()
        .and_then(|head| head.peel_to_commit().ok())
        .and_then(|commit| commit.message().ok().map(str::to_owned));
    let template = run_git_capture(
        &path,
        vec![
            "config".to_owned(),
            "--path".to_owned(),
            "--get".to_owned(),
            "commit.template".to_owned(),
        ],
        &[],
    )
    .ok()
    .filter(|output| output.status.success())
    .and_then(|output| {
        let value = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        (!value.is_empty()).then_some(value)
    })
    .and_then(|template_path| {
        let template_path = PathBuf::from(template_path);
        let resolved = if template_path.is_absolute() {
            template_path
        } else {
            repo.workdir().unwrap_or(repo.path()).join(template_path)
        };
        fs::read_to_string(resolved).ok()
    })
    .unwrap_or_default();
    Ok(CommitDefaults {
        template,
        cleanup,
        signing_enabled,
        previous_message,
    })
}

pub fn create_commit_with_options(
    path: String,
    options: CommitOptions,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    ensure_no_operation_in_progress(&repo)?;
    let special_count = usize::from(options.amend)
        + usize::from(options.fixup_target.is_some())
        + usize::from(options.squash_target.is_some());
    if special_count > 1 {
        return Err("Amend, fixup, and squash cannot be combined.".to_owned());
    }
    for target in [&options.fixup_target, &options.squash_target]
        .into_iter()
        .flatten()
    {
        find_commit(&repo, target)?;
    }
    let message = options.message.as_deref().map(str::trim);
    if message.is_some_and(str::is_empty) {
        return Err("A commit message cannot be blank.".to_owned());
    }
    if message.is_none()
        && !options.amend
        && options.fixup_target.is_none()
        && options.squash_target.is_none()
    {
        return Err("A commit message is required.".to_owned());
    }
    if options.author_name.is_some() != options.author_email.is_some() {
        return Err("Provide both the author name and email, or leave both empty.".to_owned());
    }

    let mut args = vec!["commit".to_owned()];
    if options.amend {
        args.push("--amend".to_owned());
    }
    if options.signoff {
        args.push("--signoff".to_owned());
    }
    match options.signing {
        CommitSigningMode::UseConfig => {}
        CommitSigningMode::Sign => args.push("--gpg-sign".to_owned()),
        CommitSigningMode::DoNotSign => args.push("--no-gpg-sign".to_owned()),
    }
    if options.allow_empty {
        args.push("--allow-empty".to_owned());
    }
    if let Some(target) = options.fixup_target {
        args.push(format!("--fixup={target}"));
    }
    if let Some(target) = options.squash_target {
        args.push(format!("--squash={target}"));
    }
    if let (Some(name), Some(email)) = (options.author_name, options.author_email) {
        validate_identity(&name, &email)?;
        args.extend(["--author".to_owned(), format!("{name} <{email}>")]);
    }
    if let Some(date) = options.authored_at {
        if date.contains(['\r', '\n']) {
            return Err("The author date is invalid.".to_owned());
        }
        args.push(format!("--date={date}"));
    }
    let stdin = if let Some(message) = options.message {
        args.extend(["--file".to_owned(), "-".to_owned()]);
        Some(message.into_bytes())
    } else {
        if options.amend {
            args.push("--no-edit".to_owned());
        }
        None
    };
    run_git(&path, args, stdin, &[])
}

pub fn create_tag(
    path: String,
    target_oid: String,
    name: String,
    annotated: bool,
    message: Option<String>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    find_commit(&repo, &target_oid)?;
    validate_tag_name(&path, &name)?;
    let mut args = vec!["tag".to_owned()];
    if annotated {
        let message = message
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| "An annotated tag message is required.".to_owned())?;
        args.extend(["-a".to_owned(), name, target_oid, "-m".to_owned(), message]);
    } else {
        args.extend([name, target_oid]);
    }
    run_git(&path, args, None, &[])
}

pub fn checkout_commit(path: String, oid: String) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    find_commit(&repo, &oid)?;
    ensure_no_operation_in_progress(&repo)?;
    run_git(
        &path,
        vec!["switch".to_owned(), "--detach".to_owned(), oid],
        None,
        &[],
    )
}

pub fn cherry_pick_commit(
    path: String,
    oid: String,
    mainline_parent: Option<u32>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let commit = find_commit(&repo, &oid)?;
    ensure_no_operation_in_progress(&repo)?;
    ensure_clean_tracked(&repo)?;
    validate_mainline(&commit, mainline_parent)?;
    let mut args = vec!["cherry-pick".to_owned()];
    if let Some(parent) = mainline_parent {
        args.extend(["-m".to_owned(), parent.to_string()]);
    }
    args.push(oid);
    run_git(&path, args, None, &[])
}

/// Simulates a single-commit cherry-pick against HEAD without changing the
/// repository. Unlike an ancestry or patch-id check, this correctly allows an
/// old commit whose effect was removed by a later revert.
pub fn assess_cherry_pick(
    path: String,
    oid: String,
    mainline_parent: Option<u32>,
) -> Result<CherryPickApplicability, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let commit = find_commit(&repo, &oid)?;
    validate_mainline(&commit, mainline_parent)?;
    let head = repo
        .head()
        .map_err(format_git_error)?
        .peel_to_commit()
        .map_err(format_git_error)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "A working tree is required.".to_owned())?;
    let cache_key = format!(
        "{}\0{}\0{}\0{}",
        display_path(
            workdir
                .canonicalize()
                .unwrap_or_else(|_| workdir.to_path_buf())
        ),
        head.id(),
        commit.id(),
        mainline_parent.unwrap_or(0),
    );
    if let Some(cached) = CHERRY_PICK_ASSESSMENTS.lock().get(&cache_key).cloned() {
        return Ok(cached);
    }

    let index = repo
        .cherrypick_commit(&commit, &head, mainline_parent.unwrap_or(0), None)
        .map_err(format_git_error)?;
    let applicability = if index.has_conflicts() {
        CherryPickApplicability::Conflicts
    } else {
        let head_tree = head.tree().map_err(format_git_error)?;
        let diff = repo
            .diff_tree_to_index(Some(&head_tree), Some(&index), None)
            .map_err(format_git_error)?;
        if diff.deltas().next().is_none() {
            CherryPickApplicability::AlreadyApplied
        } else {
            CherryPickApplicability::Applicable
        }
    };

    let mut cache = CHERRY_PICK_ASSESSMENTS.lock();
    if cache.len() >= 512 {
        cache.clear();
    }
    cache.insert(cache_key, applicability.clone());
    Ok(applicability)
}

pub fn control_cherry_pick(
    path: String,
    action: SequenceControl,
) -> Result<OperationResult, String> {
    control_sequence(&path, "cherry-pick", action)
}

pub fn revert_commit(
    path: String,
    oid: String,
    mainline_parent: Option<u32>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let commit = find_commit(&repo, &oid)?;
    ensure_no_operation_in_progress(&repo)?;
    ensure_clean_tracked(&repo)?;
    validate_mainline(&commit, mainline_parent)?;
    let mut args = vec!["revert".to_owned(), "--no-edit".to_owned()];
    if let Some(parent) = mainline_parent {
        args.extend(["-m".to_owned(), parent.to_string()]);
    }
    args.push(oid);
    run_git(&path, args, None, &[])
}

pub fn control_revert(path: String, action: SequenceControl) -> Result<OperationResult, String> {
    control_sequence(&path, "revert", action)
}

pub fn preview_reset(path: String, target_oid: String) -> Result<ResetPreview, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    build_reset_preview(&repo, &target_oid)
}

pub fn reset_to_commit(
    path: String,
    target_oid: String,
    mode: ResetMode,
    expected_fingerprint: String,
    branch_confirmation: Option<String>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let preview = build_reset_preview(&repo, &target_oid)?;
    if preview.fingerprint != expected_fingerprint {
        return Err("The repository changed after the reset preview. Review it again.".to_owned());
    }
    if mode == ResetMode::Hard
        && branch_confirmation.as_deref() != Some(preview.current_branch.as_str())
    {
        return Err("Type the current branch name to confirm the hard reset.".to_owned());
    }

    let mut recycled = Vec::new();
    if mode == ResetMode::Hard {
        for relative in &preview.untracked_collisions {
            let target = safe_worktree_path(&repo, relative)?;
            if target.exists() {
                trash::delete(&target).map_err(|error| {
                    format!("Could not move {relative} to the Recycle Bin: {error}")
                })?;
                recycled.push(relative.clone());
            }
        }
    }

    let option = match mode {
        ResetMode::Soft => "--soft",
        ResetMode::Mixed => "--mixed",
        ResetMode::Hard => "--hard",
    };
    let mut result = run_git(
        &path,
        vec!["reset".to_owned(), option.to_owned(), target_oid],
        None,
        &[],
    )?;
    if !recycled.is_empty() {
        let note = format!(
            "Moved to the Recycle Bin before reset:\n{}",
            recycled.join("\n")
        );
        if result.stdout.trim().is_empty() {
            result.stdout = note;
        } else {
            result.stdout.push_str(&format!("\n{note}"));
        }
    }
    Ok(result)
}

pub fn initialize_repository(
    options: RepositoryInitOptions,
) -> Result<RepositoryInitResult, String> {
    let target = PathBuf::from(options.target_path.trim());
    if options.target_path.trim().is_empty() {
        return Err("Choose a repository folder.".to_owned());
    }
    if target.exists() && !target.is_dir() {
        return Err("The repository path is not a folder.".to_owned());
    }
    if target.exists() && Repository::discover(&target).is_ok() {
        return Err("The selected folder is already inside a Git repository.".to_owned());
    }
    validate_branch_name(&options.initial_branch)?;
    validate_optional_url(options.origin_url.as_deref())?;

    fs::create_dir_all(&target).map_err(|error| error.to_string())?;
    let target_text = display_path(&target);
    let mut operation = run_git_without_repo_named(
        "git init",
        vec![
            "init".to_owned(),
            "-b".to_owned(),
            options.initial_branch,
            target_text.clone(),
        ],
    )?;
    let mut warnings = Vec::new();
    if !operation.success {
        return Ok(RepositoryInitResult {
            path: target_text,
            operation,
            warnings,
        });
    }

    if options.create_readme {
        let readme = target.join("README.md");
        if readme.exists() {
            warnings.push("README.md already exists and was not overwritten.".to_owned());
        } else {
            let name = target
                .file_name()
                .and_then(|value| value.to_str())
                .filter(|value| !value.is_empty())
                .unwrap_or("Repository");
            if let Err(error) = fs::write(&readme, format!("# {name}\n")) {
                warnings.push(format!("README.md could not be created: {error}"));
            }
        }
    }
    if let Some(contents) = gitignore_contents(&options.gitignore_template) {
        let gitignore = target.join(".gitignore");
        if gitignore.exists() {
            warnings.push(".gitignore already exists and was not overwritten.".to_owned());
        } else if let Err(error) = fs::write(&gitignore, contents) {
            warnings.push(format!(".gitignore could not be created: {error}"));
        }
    }
    if let Some(url) = options.origin_url.filter(|value| !value.trim().is_empty()) {
        let remote = run_git(
            &target_text,
            vec![
                "remote".to_owned(),
                "add".to_owned(),
                "origin".to_owned(),
                url,
            ],
            None,
            &[],
        )?;
        append_operation(&mut operation, &remote);
    }
    Ok(RepositoryInitResult {
        path: target_text,
        operation,
        warnings,
    })
}

pub fn clone_repository(url: String, target: String) -> Result<OperationResult, String> {
    Ok(clone_repository_advanced(CloneOptions {
        url,
        target,
        remote_name: "origin".to_owned(),
        branch: None,
        depth: None,
        single_branch: false,
        no_tags: false,
        recurse_submodules: false,
        shallow_submodules: false,
        blobless: false,
        sparse_directories: Vec::new(),
    })?
    .operation)
}

pub fn clone_repository_advanced(options: CloneOptions) -> Result<CloneResult, String> {
    validate_optional_url(Some(&options.url))?;
    validate_remote_name(&options.remote_name)?;
    if let Some(branch) = options.branch.as_deref() {
        validate_ref_name(branch)?;
    }
    if options.depth == Some(0) {
        return Err("Clone depth must be greater than zero.".to_owned());
    }
    let sparse = normalize_sparse_directories(options.sparse_directories)?;
    let target_path = Path::new(&options.target);
    if target_path.exists()
        && target_path
            .read_dir()
            .map_err(|error| error.to_string())?
            .next()
            .is_some()
    {
        return Err("The clone destination must be empty.".to_owned());
    }
    let mut args = vec!["clone".to_owned(), "--progress".to_owned()];
    if options.remote_name != "origin" {
        args.extend(["--origin".to_owned(), options.remote_name]);
    }
    if let Some(branch) = options.branch {
        args.extend(["--branch".to_owned(), branch]);
    }
    if let Some(depth) = options.depth {
        args.extend(["--depth".to_owned(), depth.to_string()]);
    }
    if options.single_branch {
        args.push("--single-branch".to_owned());
    }
    if options.no_tags {
        args.push("--no-tags".to_owned());
    }
    if options.recurse_submodules {
        args.push("--recurse-submodules".to_owned());
    }
    if options.shallow_submodules {
        if !options.recurse_submodules {
            return Err("Shallow submodules require recursive submodule clone.".to_owned());
        }
        args.push("--shallow-submodules".to_owned());
    }
    if options.blobless {
        args.extend(["--filter".to_owned(), "blob:none".to_owned()]);
    }
    if !sparse.is_empty() {
        args.push("--sparse".to_owned());
    }
    args.extend([options.url, options.target.clone()]);
    let mut operation = run_git_without_repo_named("git clone", args)?;
    let mut warnings = Vec::new();
    if operation.success && !sparse.is_empty() {
        let sparse_result = run_git(
            &options.target,
            [
                vec![
                    "sparse-checkout".to_owned(),
                    "set".to_owned(),
                    "--cone".to_owned(),
                ],
                sparse,
            ]
            .concat(),
            None,
            &[],
        )?;
        if !sparse_result.success {
            warnings.push(
                "The repository was cloned, but sparse checkout could not be applied.".to_owned(),
            );
        }
        append_operation(&mut operation, &sparse_result);
    }
    Ok(CloneResult {
        path: options.target,
        operation,
        warnings,
    })
}

pub fn read_git_config(path: Option<String>) -> Result<GitConfigSnapshot, String> {
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    if let Some(repository) = path.as_deref() {
        Repository::discover(repository).map_err(format_git_error)?;
        command.args(["-C", repository]);
    }
    let output = command
        .args([
            "config",
            "--null",
            "--show-origin",
            "--show-scope",
            "--includes",
            "--list",
        ])
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    if !output.status.success() {
        return Err(redact(&String::from_utf8_lossy(&output.stderr)));
    }
    let fields = output.stdout.split(|byte| *byte == 0).collect::<Vec<_>>();
    let mut entries = Vec::new();
    for record in fields.chunks(3) {
        if record.len() < 3 || record[0].is_empty() {
            continue;
        }
        let scope_text = String::from_utf8_lossy(record[0]);
        let scope = config_scope(&scope_text);
        let key_value = record[2];
        let separator = key_value
            .iter()
            .position(|byte| *byte == b'\n')
            .unwrap_or(key_value.len());
        let key = String::from_utf8_lossy(&key_value[..separator]).into_owned();
        let value = if separator < key_value.len() {
            &key_value[separator + 1..]
        } else {
            &[]
        };
        let sensitive = is_sensitive_config_key(&key);
        entries.push(GitConfigEntry {
            key,
            value: if sensitive {
                "••••••••".to_owned()
            } else {
                redact(&String::from_utf8_lossy(value))
            },
            scope: scope.clone(),
            origin: display_config_origin(&String::from_utf8_lossy(record[1])),
            inherited: path.is_some()
                && !matches!(scope, GitConfigScope::Local | GitConfigScope::Worktree),
            sensitive,
        });
    }
    Ok(GitConfigSnapshot { entries })
}

pub fn set_git_config(
    path: Option<String>,
    scope: GitConfigScope,
    key: String,
    value: String,
) -> Result<OperationResult, String> {
    validate_config_key(&key)?;
    validate_config_value(&value)?;
    run_config_mutation(path, scope, vec!["--replace-all".to_owned(), key, value])
}

pub fn add_git_config_value(
    path: Option<String>,
    scope: GitConfigScope,
    key: String,
    value: String,
) -> Result<OperationResult, String> {
    validate_config_key(&key)?;
    validate_config_value(&value)?;
    run_config_mutation(path, scope, vec!["--add".to_owned(), key, value])
}

pub fn unset_git_config_value(
    path: Option<String>,
    scope: GitConfigScope,
    key: String,
    value: Option<String>,
) -> Result<OperationResult, String> {
    validate_config_key(&key)?;
    let mut args = if value.is_some() {
        vec!["--fixed-value".to_owned(), "--unset".to_owned(), key]
    } else {
        vec!["--unset-all".to_owned(), key]
    };
    if let Some(value) = value {
        validate_config_value(&value)?;
        args.push(value);
    }
    run_config_mutation(path, scope, args)
}

pub fn list_remote_details(path: String) -> Result<Vec<RemoteDetails>, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let mut result = Vec::new();
    for name in repo.remotes().map_err(format_git_error)?.iter() {
        let Some(name) = name.map_err(format_git_error)? else {
            continue;
        };
        let fetch_urls = git_output_lines(&path, vec!["remote", "get-url", "--all", name])?;
        let mut push_urls =
            git_output_lines(&path, vec!["remote", "get-url", "--push", "--all", name])?;
        if push_urls == fetch_urls {
            push_urls.clear();
        }
        result.push(RemoteDetails {
            name: name.to_owned(),
            fetch_urls: fetch_urls.into_iter().map(|value| redact(&value)).collect(),
            push_urls: push_urls.into_iter().map(|value| redact(&value)).collect(),
        });
    }
    result.sort_by_key(|remote| remote.name.to_lowercase());
    Ok(result)
}

pub fn add_remote(
    path: String,
    name: String,
    fetch_url: String,
) -> Result<OperationResult, String> {
    validate_remote_name(&name)?;
    validate_optional_url(Some(&fetch_url))?;
    run_git(
        &path,
        vec!["remote".to_owned(), "add".to_owned(), name, fetch_url],
        None,
        &[],
    )
}

pub fn rename_remote(
    path: String,
    old_name: String,
    new_name: String,
) -> Result<OperationResult, String> {
    validate_remote_name(&old_name)?;
    validate_remote_name(&new_name)?;
    run_git(
        &path,
        vec!["remote".to_owned(), "rename".to_owned(), old_name, new_name],
        None,
        &[],
    )
}

pub fn update_remote(
    path: String,
    name: String,
    fetch_url: String,
    push_url: Option<String>,
) -> Result<OperationResult, String> {
    validate_remote_name(&name)?;
    validate_optional_url(Some(&fetch_url))?;
    validate_optional_url(push_url.as_deref())?;
    let mut result = run_git(
        &path,
        vec![
            "remote".to_owned(),
            "set-url".to_owned(),
            name.clone(),
            fetch_url,
        ],
        None,
        &[],
    )?;
    if !result.success {
        return Ok(result);
    }
    let push_result = if let Some(push_url) = push_url.filter(|value| !value.trim().is_empty()) {
        run_git(
            &path,
            vec![
                "remote".to_owned(),
                "set-url".to_owned(),
                "--push".to_owned(),
                name,
                push_url,
            ],
            None,
            &[],
        )?
    } else {
        run_config_mutation(
            Some(path),
            GitConfigScope::Local,
            vec!["--unset-all".to_owned(), format!("remote.{name}.pushurl")],
        )?
    };
    if push_result.exit_code != 5 {
        append_operation(&mut result, &push_result);
    }
    Ok(result)
}

pub fn remove_remote(path: String, name: String) -> Result<OperationResult, String> {
    validate_remote_name(&name)?;
    run_git(
        &path,
        vec!["remote".to_owned(), "remove".to_owned(), name],
        None,
        &[],
    )
}

pub fn create_tracking_branch(
    path: String,
    remote_branch: String,
    local_branch: String,
) -> Result<OperationResult, String> {
    validate_ref_name(&remote_branch)?;
    validate_branch_name(&local_branch)?;
    run_git(
        &path,
        vec![
            "switch".to_owned(),
            "-c".to_owned(),
            local_branch,
            "--track".to_owned(),
            remote_branch,
        ],
        None,
        &[],
    )
}

pub fn read_sparse_checkout(path: String) -> Result<SparseCheckoutState, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let config = repo.config().map_err(format_git_error)?;
    let enabled = config.get_bool("core.sparseCheckout").unwrap_or(false);
    let cone_mode = config.get_bool("core.sparseCheckoutCone").unwrap_or(true);
    let directories = if enabled {
        git_output_lines(&path, vec!["sparse-checkout", "list"])?
    } else {
        Vec::new()
    };
    Ok(SparseCheckoutState {
        enabled,
        cone_mode,
        directories,
    })
}

pub fn set_sparse_checkout(
    path: String,
    directories: Vec<String>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    ensure_no_operation_in_progress(&repo)?;
    ensure_clean_tracked(&repo)?;
    let directories = normalize_sparse_directories(directories)?;
    if directories.is_empty() {
        return Err("Add at least one sparse checkout directory.".to_owned());
    }
    run_git(
        &path,
        [
            vec![
                "sparse-checkout".to_owned(),
                "set".to_owned(),
                "--cone".to_owned(),
            ],
            directories,
        ]
        .concat(),
        None,
        &[],
    )
}

pub fn disable_sparse_checkout(path: String) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    ensure_no_operation_in_progress(&repo)?;
    ensure_clean_tracked(&repo)?;
    run_git(
        &path,
        vec!["sparse-checkout".to_owned(), "disable".to_owned()],
        None,
        &[],
    )
}

pub fn list_submodules(path: String, recursive: bool, limit: u32) -> Result<SubmodulePage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let key = repository_cache_key(&repo)?;
    let fingerprint = submodule_fingerprint(&repo)?;
    let submodules = collect_submodules(&path, &repo, recursive)?;
    let mut caches = SUBMODULE_CACHES.lock();
    caches.insert(
        key.clone(),
        SubmoduleCache {
            fingerprint: fingerprint.clone(),
            submodules,
        },
    );
    if caches.len() > 8
        && let Some(oldest) = caches.keys().find(|candidate| *candidate != &key).cloned()
    {
        caches.remove(&oldest);
    }
    Ok(submodule_page(
        caches.get(&key).expect("submodule cache inserted"),
        0,
        limit,
    ))
}

pub fn list_submodules_cursor(
    path: String,
    cursor: String,
    limit: u32,
) -> Result<SubmodulePage, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let key = repository_cache_key(&repo)?;
    let (fingerprint, offset) = cursor
        .rsplit_once(':')
        .ok_or_else(|| "The submodule cursor is invalid. Refresh the list.".to_owned())?;
    let offset = offset
        .parse::<usize>()
        .map_err(|_| "The submodule cursor is invalid. Refresh the list.".to_owned())?;
    if submodule_fingerprint(&repo)? != fingerprint {
        return Err("Submodule configuration changed. Refresh the list.".to_owned());
    }
    let caches = SUBMODULE_CACHES.lock();
    let cache = caches
        .get(&key)
        .filter(|cache| cache.fingerprint == fingerprint)
        .ok_or_else(|| "The submodule list expired. Refresh it.".to_owned())?;
    Ok(submodule_page(cache, offset, limit))
}

pub fn init_submodules(
    path: String,
    paths: Vec<String>,
    recursive: bool,
) -> Result<OperationResult, String> {
    submodule_update_command(path, paths, recursive, SubmoduleUpdateMode::Recorded)
}

pub fn update_submodules(
    path: String,
    paths: Vec<String>,
    recursive: bool,
    mode: SubmoduleUpdateMode,
) -> Result<OperationResult, String> {
    submodule_update_command(path, paths, recursive, mode)
}

fn submodule_update_command(
    path: String,
    paths: Vec<String>,
    recursive: bool,
    mode: SubmoduleUpdateMode,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    for item in &paths {
        safe_worktree_path(&repo, item)?;
    }
    let mut args = vec![
        "submodule".to_owned(),
        "update".to_owned(),
        "--init".to_owned(),
    ];
    if recursive {
        args.push("--recursive".to_owned());
    }
    if mode == SubmoduleUpdateMode::Remote {
        args.push("--remote".to_owned());
    }
    if !paths.is_empty() {
        args.push("--".to_owned());
        args.extend(paths);
    }
    run_git(&path, args, None, &[])
}

pub fn sync_submodules(
    path: String,
    paths: Vec<String>,
    recursive: bool,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    for item in &paths {
        safe_worktree_path(&repo, item)?;
    }
    let mut args = vec!["submodule".to_owned(), "sync".to_owned()];
    if recursive {
        args.push("--recursive".to_owned());
    }
    if !paths.is_empty() {
        args.push("--".to_owned());
        args.extend(paths);
    }
    run_git(&path, args, None, &[])
}

pub fn add_submodule(
    path: String,
    options: SubmoduleAddOptions,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let target = safe_worktree_path(&repo, &options.path)?;
    if target.exists() {
        return Err("The submodule path already exists.".to_owned());
    }
    if options.url.trim().is_empty() {
        return Err("A submodule URL is required.".to_owned());
    }
    let mut args = vec!["submodule".to_owned(), "add".to_owned()];
    if let Some(name) = options.name.filter(|value| !value.trim().is_empty()) {
        validate_config_component(&name)?;
        args.extend(["--name".to_owned(), name]);
    }
    if let Some(branch) = options.branch.filter(|value| !value.trim().is_empty()) {
        validate_ref_name(&branch)?;
        args.extend(["--branch".to_owned(), branch]);
    }
    if let Some(depth) = options.depth {
        if depth == 0 {
            return Err("Submodule depth must be greater than zero.".to_owned());
        }
        args.extend(["--depth".to_owned(), depth.to_string()]);
    }
    args.extend(["--".to_owned(), options.url, options.path]);
    run_git(&path, args, None, &[])
}

pub fn preview_remove_submodule(
    path: String,
    submodule_path: String,
) -> Result<SubmoduleRemovePreview, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    safe_worktree_path(&repo, &submodule_path)?;
    let item = collect_submodules(&path, &repo, false)?
        .into_iter()
        .find(|item| item.path == submodule_path)
        .ok_or_else(|| "The submodule is not registered in this repository.".to_owned())?;
    if matches!(
        item.state,
        SubmoduleState::Modified | SubmoduleState::Untracked | SubmoduleState::Conflicted
    ) {
        return Err(
            "The submodule has local changes. Clean or commit them before removal.".to_owned(),
        );
    }
    let cache = repo.path().join("modules").join(&item.name);
    let fingerprint = submodule_remove_fingerprint(&repo, &item)?;
    Ok(SubmoduleRemovePreview {
        name: item.name,
        path: item.path.clone(),
        affected_paths: vec![".gitmodules".to_owned(), item.path],
        module_cache_path: cache.exists().then(|| display_path(cache)),
        fingerprint,
    })
}

pub fn remove_submodule(
    path: String,
    submodule_path: String,
    expected_fingerprint: String,
    confirmation: String,
) -> Result<OperationResult, String> {
    if confirmation != submodule_path {
        return Err("The confirmation must exactly match the submodule path.".to_owned());
    }
    let preview = preview_remove_submodule(path.clone(), submodule_path.clone())?;
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let item = collect_submodules(&path, &repo, false)?
        .into_iter()
        .find(|item| item.path == submodule_path)
        .ok_or_else(|| "The submodule is no longer registered.".to_owned())?;
    if preview.fingerprint != expected_fingerprint
        || submodule_remove_fingerprint(&repo, &item)? != expected_fingerprint
    {
        return Err("The submodule changed after the preview. Review it again.".to_owned());
    }
    let mut result = run_git(
        &path,
        vec![
            "submodule".to_owned(),
            "deinit".to_owned(),
            "-f".to_owned(),
            "--".to_owned(),
            submodule_path.clone(),
        ],
        None,
        &[],
    )?;
    if !result.success {
        return Ok(result);
    }
    let removed = run_git(
        &path,
        vec![
            "rm".to_owned(),
            "-f".to_owned(),
            "--".to_owned(),
            submodule_path,
        ],
        None,
        &[],
    )?;
    append_operation(&mut result, &removed);
    if result.success
        && let Some(cache) = preview.module_cache_path
    {
        let cache = PathBuf::from(cache);
        if cache.exists() {
            match trash::delete(&cache) {
                Ok(()) => result
                    .stdout
                    .push_str("\nMoved the submodule cache to the Recycle Bin."),
                Err(recycle_error) => {
                    let quarantine_root = repo.path().join("gitfront-trash");
                    fs::create_dir_all(&quarantine_root).map_err(|fallback_error| {
                        format!(
                            "Could not move the submodule cache to the Recycle Bin ({recycle_error}) or create a recoverable quarantine ({fallback_error})."
                        )
                    })?;
                    let quarantine = quarantine_root
                        .join(format!("submodule-cache-{}", Uuid::new_v4().simple()));
                    fs::rename(&cache, &quarantine).map_err(|fallback_error| {
                        format!(
                            "Could not move the submodule cache to the Recycle Bin ({recycle_error}) or the recoverable quarantine ({fallback_error})."
                        )
                    })?;
                    result.stdout.push_str(&format!(
                        "\nThe Recycle Bin was unavailable. Moved the submodule cache to recoverable quarantine: {}",
                        display_path(quarantine)
                    ));
                }
            }
        }
    }
    Ok(result)
}

pub fn list_subtrees(path: String) -> Result<Vec<SubtreeInfo>, String> {
    let output = run_git_capture(
        &path,
        vec![
            "config".to_owned(),
            "--local".to_owned(),
            "--get-regexp".to_owned(),
            "^gitfront\\.subtree\\.".to_owned(),
        ],
        &[],
    )?;
    if !output.status.success() && output.status.code() != Some(1) {
        return Err(redact(String::from_utf8_lossy(&output.stderr).trim()));
    }
    let mut values: HashMap<String, HashMap<String, String>> = HashMap::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let Some((key, value)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        let Some(rest) = key.strip_prefix("gitfront.subtree.") else {
            continue;
        };
        let Some((id, field)) = rest.rsplit_once('.') else {
            continue;
        };
        values
            .entry(id.to_owned())
            .or_default()
            .insert(field.to_owned(), value.trim().to_owned());
    }
    let mut result = values
        .into_iter()
        .filter_map(|(id, values)| {
            Some(SubtreeInfo {
                id,
                prefix: values.get("prefix")?.to_owned(),
                repository: values.get("repository")?.to_owned(),
                reference: values.get("reference")?.to_owned(),
                squash: values.get("squash").is_none_or(|value| value != "false"),
            })
        })
        .collect::<Vec<_>>();
    result.sort_by_cached_key(|item| item.prefix.to_lowercase());
    Ok(result)
}

pub fn register_subtree(path: String, subtree: SubtreeInfo) -> Result<OperationResult, String> {
    validate_config_component(&subtree.id)?;
    validate_subtree_values(
        &path,
        &subtree.prefix,
        &subtree.repository,
        &subtree.reference,
    )?;
    write_subtree_registry(&path, &subtree)
}

pub fn forget_subtree(path: String, id: String) -> Result<OperationResult, String> {
    validate_config_component(&id)?;
    run_git(
        &path,
        vec![
            "config".to_owned(),
            "--local".to_owned(),
            "--remove-section".to_owned(),
            format!("gitfront.subtree.{id}"),
        ],
        None,
        &[],
    )
}

pub fn create_branch(
    path: String,
    name: String,
    start_point: Option<String>,
    checkout: bool,
) -> Result<OperationResult, String> {
    validate_ref_name(&name)?;
    let mut args = if checkout {
        vec!["switch".to_owned(), "-c".to_owned(), name]
    } else {
        vec!["branch".to_owned(), name]
    };
    if let Some(start) = start_point {
        args.push(start);
    }
    run_git(&path, args, None, &[])
}

pub fn switch_branch(path: String, name: String) -> Result<OperationResult, String> {
    validate_ref_name(&name)?;
    run_git(&path, vec!["switch".to_owned(), name], None, &[])
}

pub fn rename_branch(
    path: String,
    old_name: String,
    new_name: String,
) -> Result<OperationResult, String> {
    validate_ref_name(&old_name)?;
    validate_ref_name(&new_name)?;
    run_git(
        &path,
        vec!["branch".to_owned(), "-m".to_owned(), old_name, new_name],
        None,
        &[],
    )
}

pub fn delete_local_branch(
    path: String,
    name: String,
    force: bool,
) -> Result<OperationResult, String> {
    validate_ref_name(&name)?;
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    if repo
        .head()
        .ok()
        .and_then(|head| head.shorthand().ok().map(str::to_owned))
        .as_deref()
        == Some(name.as_str())
    {
        return Err("The current branch cannot be deleted.".to_owned());
    }
    run_git(
        &path,
        vec![
            "branch".to_owned(),
            if force { "-D" } else { "-d" }.to_owned(),
            name,
        ],
        None,
        &[],
    )
}

pub fn fetch_all(path: String) -> Result<OperationResult, String> {
    run_git(
        &path,
        vec![
            "fetch".to_owned(),
            "--all".to_owned(),
            "--prune".to_owned(),
            "--progress".to_owned(),
        ],
        None,
        &[],
    )
}

pub fn pull(path: String, mode: PullMode) -> Result<OperationResult, String> {
    let mut args = vec!["pull".to_owned()];
    match mode {
        PullMode::Configured => {}
        PullMode::Merge => args.push("--no-rebase".to_owned()),
        PullMode::Rebase => args.push("--rebase".to_owned()),
        PullMode::FastForwardOnly => args.push("--ff-only".to_owned()),
    }
    run_git(&path, args, None, &[])
}

pub fn push_current(
    path: String,
    force_with_lease: bool,
    set_upstream: bool,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let branch = repo
        .head()
        .ok()
        .filter(|head| head.is_branch())
        .and_then(|head| head.shorthand().ok().map(str::to_owned))
        .ok_or_else(|| "A checked-out local branch is required.".to_owned())?;
    let mut args = vec!["push".to_owned()];
    if force_with_lease {
        args.push("--force-with-lease".to_owned());
    }
    if set_upstream {
        args.extend(["--set-upstream".to_owned(), "origin".to_owned(), branch]);
    }
    run_git(&path, args, None, &[])
}

pub fn push_current_to(
    path: String,
    remote: String,
    remote_branch: String,
    force_with_lease: bool,
) -> Result<OperationResult, String> {
    validate_remote_name(&remote)?;
    validate_branch_name(&remote_branch)?;
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let branch = repo
        .head()
        .ok()
        .filter(|head| head.is_branch())
        .and_then(|head| head.shorthand().ok().map(str::to_owned))
        .ok_or_else(|| "A checked-out local branch is required.".to_owned())?;
    let mut args = vec!["push".to_owned()];
    if force_with_lease {
        args.push("--force-with-lease".to_owned());
    }
    args.extend([
        "--set-upstream".to_owned(),
        remote,
        format!("{branch}:{remote_branch}"),
    ]);
    run_git(&path, args, None, &[])
}

pub fn merge_branch(path: String, target: String) -> Result<OperationResult, String> {
    validate_ref_name(&target)?;
    run_git(&path, vec!["merge".to_owned(), target], None, &[])
}

pub fn control_merge(path: String, action: MergeControl) -> Result<OperationResult, String> {
    let args = match action {
        MergeControl::Continue => vec!["merge".to_owned(), "--continue".to_owned()],
        MergeControl::Abort => vec!["merge".to_owned(), "--abort".to_owned()],
    };
    run_git(&path, args, None, &[])
}

pub fn rebase_branch(
    path: String,
    upstream: String,
    onto: Option<String>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    ensure_no_operation_in_progress(&repo)?;
    ensure_clean_tracked(&repo)?;
    validate_ref_name(&upstream)?;
    let args = if let Some(onto) = onto {
        validate_ref_name(&onto)?;
        vec!["rebase".to_owned(), "--onto".to_owned(), onto, upstream]
    } else {
        vec!["rebase".to_owned(), upstream]
    };
    run_git(&path, args, None, &[])
}

pub fn control_rebase(path: String, action: RebaseControl) -> Result<OperationResult, String> {
    let option = match action {
        RebaseControl::Continue => "--continue",
        RebaseControl::Skip => "--skip",
        RebaseControl::Abort => "--abort",
    };
    let session = rebase_session_path(&Repository::discover(&path).map_err(format_git_error)?);
    let session_dir = fs::read_to_string(&session)
        .ok()
        .map(|value| value.trim().to_owned());
    let mut env = Vec::new();
    if let Some(directory) = session_dir.as_ref() {
        env.push(("GITFRONT_REBASE_SESSION".to_owned(), directory.clone()));
        if let Ok(helper) = sequence_editor_path() {
            env.push((
                "GIT_EDITOR".to_owned(),
                quoted_editor_command(&helper, "message"),
            ));
        }
    }
    let env_refs: Vec<(&str, &str)> = env
        .iter()
        .map(|(key, value)| (key.as_str(), value.as_str()))
        .collect();
    let result = run_git(
        &path,
        vec!["rebase".to_owned(), option.to_owned()],
        None,
        &env_refs,
    )?;
    if result.success || action == RebaseControl::Abort {
        cleanup_rebase_session(&session, session_dir.as_deref());
    }
    Ok(result)
}

pub fn prepare_interactive_rebase(path: String, upstream: String) -> Result<RebasePlan, String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    let upstream_object = repo.revparse_single(&upstream).map_err(format_git_error)?;
    let upstream_oid = upstream_object
        .peel_to_commit()
        .map_err(format_git_error)?
        .id();
    let head_oid = repo
        .head()
        .map_err(format_git_error)?
        .peel_to_commit()
        .map_err(format_git_error)?
        .id();
    let mut walk = repo.revwalk().map_err(format_git_error)?;
    walk.push(head_oid).map_err(format_git_error)?;
    walk.hide(upstream_oid).map_err(format_git_error)?;
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::REVERSE)
        .map_err(format_git_error)?;
    let mut items = Vec::new();
    let mut contains_merge_commits = false;
    for oid in walk {
        let commit = repo
            .find_commit(oid.map_err(format_git_error)?)
            .map_err(format_git_error)?;
        contains_merge_commits |= commit.parent_count() > 1;
        items.push(RebasePlanItem {
            action: RebaseAction::Pick,
            oid: commit.id().to_string(),
            summary: commit
                .summary()
                .ok()
                .flatten()
                .unwrap_or("(no message)")
                .to_owned(),
            new_message: None,
        });
    }
    Ok(RebasePlan {
        upstream,
        onto: None,
        items,
        contains_merge_commits,
    })
}

pub fn start_interactive_rebase(path: String, plan: RebasePlan) -> Result<OperationResult, String> {
    validate_rebase_plan(&plan)?;
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let helper = sequence_editor_path()?;
    let session_dir = std::env::temp_dir().join(format!("gitfront-rebase-{}", Uuid::new_v4()));
    fs::create_dir_all(&session_dir).map_err(|error| error.to_string())?;
    let todo = plan
        .items
        .iter()
        .map(|item| {
            format!(
                "{} {} {}",
                rebase_action_name(&item.action),
                item.oid,
                sanitize_todo(&item.summary)
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    fs::write(session_dir.join("todo.txt"), format!("{todo}\n"))
        .map_err(|error| error.to_string())?;
    let messages: Vec<&str> = plan
        .items
        .iter()
        .filter_map(|item| match item.action {
            RebaseAction::Reword | RebaseAction::Squash => item.new_message.as_deref(),
            _ => None,
        })
        .collect();
    fs::write(session_dir.join("messages.bin"), messages.join("\0"))
        .map_err(|error| error.to_string())?;
    fs::write(session_dir.join("message-index"), "0").map_err(|error| error.to_string())?;
    fs::write(rebase_session_path(&repo), display_path(&session_dir))
        .map_err(|error| error.to_string())?;

    let sequence_command = quoted_editor_command(&helper, "sequence");
    let message_command = quoted_editor_command(&helper, "message");
    let session_value = display_path(&session_dir);
    let env = [
        ("GIT_SEQUENCE_EDITOR", sequence_command.as_str()),
        ("GIT_EDITOR", message_command.as_str()),
        ("GITFRONT_REBASE_SESSION", session_value.as_str()),
    ];
    let mut args = vec!["rebase".to_owned(), "--interactive".to_owned()];
    if let Some(onto) = plan.onto {
        args.extend(["--onto".to_owned(), onto, plan.upstream]);
    } else {
        args.push(plan.upstream);
    }
    let result = run_git(&path, args, None, &env)?;
    if result.success {
        cleanup_rebase_session(&rebase_session_path(&repo), Some(&session_value));
    }
    Ok(result)
}

pub fn stash_save(
    path: String,
    message: String,
    include_untracked: bool,
) -> Result<OperationResult, String> {
    let mut args = vec!["stash".to_owned(), "push".to_owned()];
    if include_untracked {
        args.push("--include-untracked".to_owned());
    }
    if !message.trim().is_empty() {
        args.extend(["-m".to_owned(), message]);
    }
    run_git(&path, args, None, &[])
}

pub fn stash_apply(path: String, index: u32, pop: bool) -> Result<OperationResult, String> {
    run_git(
        &path,
        vec![
            "stash".to_owned(),
            if pop { "pop" } else { "apply" }.to_owned(),
            format!("stash@{{{index}}}"),
        ],
        None,
        &[],
    )
}

pub fn stash_drop(path: String, index: u32) -> Result<OperationResult, String> {
    run_git(
        &path,
        vec![
            "stash".to_owned(),
            "drop".to_owned(),
            format!("stash@{{{index}}}"),
        ],
        None,
        &[],
    )
}

pub fn get_stash_diff(path: String, index: u32) -> Result<String, String> {
    let output = run_git_capture(
        &path,
        vec![
            "stash".to_owned(),
            "show".to_owned(),
            "--patch".to_owned(),
            format!("stash@{{{index}}}"),
        ],
        &[],
    )?;
    if !output.status.success() {
        return Err(redact(&String::from_utf8_lossy(&output.stderr)));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn load_conflict(path: String, file_path: String) -> Result<ConflictFile, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let safe_path = safe_relative_path(&file_path)?;
    let index = repo.index().map_err(format_git_error)?;
    let conflict = index
        .conflicts()
        .map_err(format_git_error)?
        .find_map(|item| {
            let item = item.ok()?;
            let entry_path = item
                .our
                .as_ref()
                .or(item.their.as_ref())
                .or(item.ancestor.as_ref())?
                .path
                .as_slice();
            (Path::new(&String::from_utf8_lossy(entry_path).to_string()) == safe_path)
                .then_some(item)
        })
        .ok_or_else(|| "The selected file no longer has an index conflict.".to_owned())?;

    let base_bytes = conflict
        .ancestor
        .as_ref()
        .and_then(|entry| read_blob(&repo, entry.id));
    let ours_bytes = conflict
        .our
        .as_ref()
        .and_then(|entry| read_blob(&repo, entry.id));
    let theirs_bytes = conflict
        .their
        .as_ref()
        .and_then(|entry| read_blob(&repo, entry.id));
    let worktree_path = safe_worktree_path(&repo, &file_path)?;
    let current_bytes = fs::read(&worktree_path).unwrap_or_default();
    let max_size = [
        base_bytes.as_deref(),
        ours_bytes.as_deref(),
        theirs_bytes.as_deref(),
        Some(current_bytes.as_slice()),
    ]
    .into_iter()
    .flatten()
    .map(|bytes| bytes.len() as u64)
    .max()
    .unwrap_or(0);
    let binary = [
        base_bytes.as_deref(),
        ours_bytes.as_deref(),
        theirs_bytes.as_deref(),
        Some(current_bytes.as_slice()),
    ]
    .into_iter()
    .flatten()
    .any(is_binary);
    let base = String::from_utf8_lossy(base_bytes.as_deref().unwrap_or_default()).into_owned();
    let ours = String::from_utf8_lossy(ours_bytes.as_deref().unwrap_or_default()).into_owned();
    let theirs = String::from_utf8_lossy(theirs_bytes.as_deref().unwrap_or_default()).into_owned();
    let current = String::from_utf8_lossy(&current_bytes).into_owned();
    Ok(ConflictFile {
        path: file_path,
        base_label: "Base".to_owned(),
        ours_label: conflict_ours_label(repo.state()),
        theirs_label: conflict_theirs_label(repo.state()),
        regions: parse_conflict_regions(&current),
        base,
        ours,
        theirs,
        current,
        binary,
        too_large: max_size > MAX_RENDER_BYTES,
    })
}

pub fn save_conflict_resolution(
    path: String,
    file_path: String,
    content: String,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let target = safe_worktree_path(&repo, &file_path)?;
    fs::write(&target, content)
        .map_err(|error| format!("Could not save {}: {error}", target.display()))?;
    stage_paths(path, vec![file_path])
}

pub fn open_in_vscode(path: String, file_path: String) -> Result<OperationResult, String> {
    open_external_file(path, file_path, ExternalEditor::VsCode, None)
}

pub fn open_external_file(
    path: String,
    file_path: String,
    editor: ExternalEditor,
    custom_executable: Option<String>,
) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let target = safe_worktree_path(&repo, &file_path)?;
    if editor == ExternalEditor::GitMergeTool {
        return run_git(
            &path,
            vec![
                "mergetool".to_owned(),
                "--no-prompt".to_owned(),
                "--".to_owned(),
                file_path,
            ],
            None,
            &[],
        );
    }

    let workdir = repo.workdir().unwrap_or(repo.path());
    let mut command = match editor {
        ExternalEditor::VsCode => {
            let mut command = Command::new("code");
            command.arg("--reuse-window");
            command
        }
        ExternalEditor::SystemDefault => {
            #[cfg(target_os = "windows")]
            {
                let mut command = Command::new("rundll32.exe");
                command.arg("url.dll,FileProtocolHandler");
                command
            }
            #[cfg(not(target_os = "windows"))]
            {
                Command::new("open")
            }
        }
        ExternalEditor::Custom => {
            let executable = custom_executable
                .filter(|value| !value.trim().is_empty())
                .ok_or_else(|| "Choose a custom editor executable in Settings.".to_owned())?;
            Command::new(executable)
        }
        ExternalEditor::GitMergeTool => unreachable!(),
    };
    let output = command
        .arg(target)
        .current_dir(workdir)
        .output()
        .map_err(|error| format!("The external editor could not be started: {error}"))?;
    Ok(result_from_output("open external editor", output))
}

fn repository_cache_key(repo: &Repository) -> Result<String, String> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported.".to_owned())?;
    Ok(display_path(
        workdir
            .canonicalize()
            .unwrap_or_else(|_| workdir.to_path_buf()),
    ))
}

fn submodule_fingerprint(repo: &Repository) -> Result<String, String> {
    let mut digest = Sha256::new();
    digest.update(
        repo.head()
            .ok()
            .and_then(|head| head.target())
            .map(|oid| oid.to_string())
            .unwrap_or_default(),
    );
    let index = repo.index().map_err(format_git_error)?;
    for entry in index.iter() {
        digest.update(entry.mode.to_le_bytes());
        digest.update(entry.id.as_bytes());
        digest.update(&entry.path);
    }
    if let Some(workdir) = repo.workdir() {
        digest.update(fs::read(workdir.join(".gitmodules")).unwrap_or_default());
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn submodule_page(cache: &SubmoduleCache, offset: usize, limit: u32) -> SubmodulePage {
    let end = offset
        .saturating_add(limit.clamp(1, 500) as usize)
        .min(cache.submodules.len());
    SubmodulePage {
        submodules: cache
            .submodules
            .get(offset..end)
            .unwrap_or_default()
            .to_vec(),
        next_cursor: (end < cache.submodules.len()).then(|| format!("{}:{end}", cache.fingerprint)),
        total_submodules: cache.submodules.len().min(u32::MAX as usize) as u32,
    }
}

fn collect_submodules(
    path: &str,
    repo: &Repository,
    recursive: bool,
) -> Result<Vec<SubmoduleInfo>, String> {
    let mut config_by_path: HashMap<String, (String, Option<String>, Option<String>)> =
        HashMap::new();
    let config = run_git_capture(
        path,
        vec![
            "config".to_owned(),
            "-f".to_owned(),
            ".gitmodules".to_owned(),
            "--get-regexp".to_owned(),
            "^submodule\\..*\\.(path|url|branch)$".to_owned(),
        ],
        &[],
    )?;
    let mut config_fields: HashMap<String, HashMap<String, String>> = HashMap::new();
    if config.status.success() {
        for line in String::from_utf8_lossy(&config.stdout).lines() {
            let Some((key, value)) = line.split_once(char::is_whitespace) else {
                continue;
            };
            let Some(rest) = key.strip_prefix("submodule.") else {
                continue;
            };
            let Some((name, field)) = rest.rsplit_once('.') else {
                continue;
            };
            config_fields
                .entry(name.to_owned())
                .or_default()
                .insert(field.to_owned(), value.trim().to_owned());
        }
    }
    for (name, fields) in config_fields {
        if let Some(module_path) = fields.get("path") {
            config_by_path.insert(
                module_path.replace('\\', "/"),
                (
                    name,
                    fields.get("url").map(|value| redact(value)),
                    fields.get("branch").cloned(),
                ),
            );
        }
    }
    let index_oids = repo
        .index()
        .map_err(format_git_error)?
        .iter()
        .filter(|entry| entry.mode == 0o160000)
        .map(|entry| {
            (
                String::from_utf8_lossy(&entry.path).replace('\\', "/"),
                entry.id.to_string(),
            )
        })
        .collect::<HashMap<_, _>>();
    let status = run_git_capture(
        path,
        vec![
            "status".to_owned(),
            "--porcelain=v2".to_owned(),
            "-z".to_owned(),
            "--ignore-submodules=none".to_owned(),
            "--untracked-files=no".to_owned(),
        ],
        &[],
    )?;
    let mut dirty: HashMap<String, SubmoduleState> = HashMap::new();
    for record in status
        .stdout
        .split(|byte| *byte == 0)
        .filter(|record| !record.is_empty())
    {
        let record = String::from_utf8_lossy(record);
        let fields = record.splitn(9, ' ').collect::<Vec<_>>();
        if fields.first() == Some(&"1") && fields.len() == 9 && fields[2].starts_with('S') {
            let sub = fields[2].as_bytes();
            let state = if fields[1].contains('U') {
                SubmoduleState::Conflicted
            } else if sub.get(3) == Some(&b'U') {
                SubmoduleState::Untracked
            } else if sub.get(2) == Some(&b'M') {
                SubmoduleState::Modified
            } else if sub.get(1) == Some(&b'C') {
                SubmoduleState::CheckedOutDifferent
            } else {
                continue;
            };
            dirty.insert(fields[8].replace('\\', "/"), state);
        }
    }
    let mut args = vec!["submodule".to_owned(), "status".to_owned()];
    if recursive {
        args.push("--recursive".to_owned());
    }
    let output = run_git_capture(path, args, &[])?;
    if !output.status.success() {
        if !repo
            .workdir()
            .is_some_and(|workdir| workdir.join(".gitmodules").exists())
        {
            return Ok(Vec::new());
        }
        return Err(redact(String::from_utf8_lossy(&output.stderr).trim()));
    }
    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if line.len() < 42 {
            continue;
        }
        let marker = line.as_bytes()[0] as char;
        let oid = line[1..41].to_owned();
        let remainder = line[42..].trim();
        let module_path = remainder
            .rsplit_once(" (")
            .map_or(remainder, |value| value.0)
            .replace('\\', "/");
        seen.insert(module_path.clone());
        let (name, url, branch) = config_by_path
            .get(&module_path)
            .cloned()
            .unwrap_or_else(|| (module_path.clone(), None, None));
        let state = dirty.get(&module_path).cloned().unwrap_or(match marker {
            '-' => SubmoduleState::Uninitialized,
            '+' => SubmoduleState::CheckedOutDifferent,
            'U' => SubmoduleState::Conflicted,
            _ => SubmoduleState::Clean,
        });
        result.push(SubmoduleInfo {
            name,
            path: module_path.clone(),
            url,
            branch,
            index_oid: index_oids.get(&module_path).cloned(),
            head_oid: (marker != '-').then_some(oid),
            state,
            depth: module_path.matches('/').count() as u32,
        });
    }
    for (module_path, (name, url, branch)) in config_by_path {
        if seen.contains(&module_path) {
            continue;
        }
        result.push(SubmoduleInfo {
            name,
            path: module_path.clone(),
            url,
            branch,
            index_oid: index_oids.get(&module_path).cloned(),
            head_oid: None,
            state: SubmoduleState::Missing,
            depth: module_path.matches('/').count() as u32,
        });
    }
    result.sort_by_cached_key(|item| item.path.to_lowercase());
    Ok(result)
}

fn submodule_remove_fingerprint(repo: &Repository, item: &SubmoduleInfo) -> Result<String, String> {
    let mut digest = Sha256::new();
    digest.update(submodule_fingerprint(repo)?);
    digest.update(item.name.as_bytes());
    digest.update(item.path.as_bytes());
    digest.update(item.index_oid.as_deref().unwrap_or_default().as_bytes());
    digest.update(item.head_oid.as_deref().unwrap_or_default().as_bytes());
    digest.update(format!("{:?}", item.state));
    Ok(format!("{:x}", digest.finalize()))
}

fn validate_config_component(value: &str) -> Result<(), String> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
    {
        return Err("The identifier may contain only letters, numbers, '-' and '_'.".to_owned());
    }
    Ok(())
}

fn validate_subtree_values(
    path: &str,
    prefix: &str,
    repository: &str,
    reference: &str,
) -> Result<(), String> {
    let repo = Repository::discover(path).map_err(format_git_error)?;
    if prefix.trim().is_empty() || repository.trim().is_empty() || reference.trim().is_empty() {
        return Err("Subtree prefix, repository and ref are required.".to_owned());
    }
    safe_worktree_path(&repo, prefix)?;
    validate_ref_name(reference)
}

fn write_subtree_registry(path: &str, subtree: &SubtreeInfo) -> Result<OperationResult, String> {
    let canonical = Repository::discover(path)
        .map_err(format_git_error)
        .and_then(|repo| repository_cache_key(&repo))?;
    let lock = {
        let mut locks = REPOSITORY_LOCKS.lock();
        locks
            .entry(canonical)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _guard = lock.lock();
    write_subtree_registry_unlocked(path, subtree)
}

fn write_subtree_registry_unlocked(
    path: &str,
    subtree: &SubtreeInfo,
) -> Result<OperationResult, String> {
    let section = format!("gitfront.subtree.{}", subtree.id);
    let mut combined = OperationResult {
        success: true,
        exit_code: 0,
        summary: "Saved subtree registration.".to_owned(),
        stdout: String::new(),
        stderr: String::new(),
    };
    for (field, value) in [
        ("prefix", subtree.prefix.clone()),
        ("repository", subtree.repository.clone()),
        ("reference", subtree.reference.clone()),
        ("squash", subtree.squash.to_string()),
    ] {
        let output = run_git_capture(
            path,
            vec![
                "config".to_owned(),
                "--local".to_owned(),
                format!("{section}.{field}"),
                value,
            ],
            &[],
        )?;
        let result = result_from_output("save subtree registration", output);
        append_operation(&mut combined, &result);
        if !combined.success {
            break;
        }
    }
    Ok(combined)
}

pub fn run_subtree_operation(
    path: String,
    operation_id: String,
    options: SubtreeOperationOptions,
    sink: StreamSink<OperationEvent>,
) -> Result<(), String> {
    validate_config_component(&operation_id)?;
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let repository = options.repository.clone().unwrap_or_default();
    let reference = options.reference.clone().unwrap_or_default();
    if options.action == SubtreeAction::Split {
        let repo = Repository::discover(&path).map_err(format_git_error)?;
        if options.prefix.trim().is_empty() {
            return Err("A subtree prefix is required.".to_owned());
        }
        safe_worktree_path(&repo, &options.prefix)?;
    } else {
        validate_subtree_values(&path, &options.prefix, &repository, &reference)?;
    }
    if matches!(options.action, SubtreeAction::Add | SubtreeAction::Pull)
        && collect_status(&repo)?.iter().any(|file| {
            !file.untracked
                && (file.staged != ChangeKind::None || file.unstaged != ChangeKind::None)
        })
    {
        return Err(
            "Commit or discard tracked changes before running subtree add or pull.".to_owned(),
        );
    }
    let action = match options.action {
        SubtreeAction::Add => "add",
        SubtreeAction::Pull => "pull",
        SubtreeAction::Push => "push",
        SubtreeAction::Split => "split",
    };
    let mut args = vec![
        "subtree".to_owned(),
        action.to_owned(),
        "--prefix".to_owned(),
        options.prefix.clone(),
    ];
    match options.action {
        SubtreeAction::Add | SubtreeAction::Pull | SubtreeAction::Push => {
            args.extend([repository.clone(), reference.clone()]);
            if options.squash && options.action != SubtreeAction::Push {
                args.push("--squash".to_owned());
            }
        }
        SubtreeAction::Split => {
            if let Some(branch) = options
                .branch
                .as_ref()
                .filter(|value| !value.trim().is_empty())
            {
                validate_branch_name(branch)?;
                args.extend(["--branch".to_owned(), branch.to_owned()]);
            }
        }
    }
    let canonical = repository_cache_key(&repo)?;
    let lock = {
        let mut locks = REPOSITORY_LOCKS.lock();
        locks
            .entry(canonical)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _guard = lock.lock();
    let _ = sink.add(OperationEvent {
        operation_id: operation_id.clone(),
        operation: format!("subtree {action}"),
        phase: OperationPhase::Started,
        message: format!("Subtree {action} started."),
        progress: None,
        result: None,
    });
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    configure_subtree_environment(&mut command);
    command
        .arg("-C")
        .arg(&path)
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command
        .spawn()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    let pid = child.id();
    ACTIVE_GIT_OPERATIONS
        .lock()
        .insert(operation_id.clone(), pid);
    let (sender, receiver) = mpsc::channel::<(bool, String)>();
    if let Some(stream) = child.stdout.take() {
        let sender = sender.clone();
        thread::spawn(move || {
            for line in BufReader::new(stream).lines().map_while(Result::ok) {
                let _ = sender.send((false, line));
            }
        });
    }
    if let Some(stream) = child.stderr.take() {
        let sender = sender.clone();
        thread::spawn(move || {
            for line in BufReader::new(stream).lines().map_while(Result::ok) {
                let _ = sender.send((true, line));
            }
        });
    }
    drop(sender);
    let mut stdout = String::new();
    let mut stderr = String::new();
    let percent = Regex::new(r"(?P<value>\d{1,3})%").expect("valid progress regex");
    let status = loop {
        while let Ok((is_error, line)) = receiver.try_recv() {
            let clean = redact(&line);
            let progress = percent
                .captures(&clean)
                .and_then(|capture| capture.name("value"))
                .and_then(|value| value.as_str().parse::<f64>().ok())
                .map(|value| (value / 100.0).clamp(0.0, 1.0));
            let destination = if is_error { &mut stderr } else { &mut stdout };
            destination.push_str(&clean);
            destination.push('\n');
            let _ = sink.add(OperationEvent {
                operation_id: operation_id.clone(),
                operation: format!("subtree {action}"),
                phase: OperationPhase::Progress,
                message: clean,
                progress,
                result: None,
            });
        }
        if let Some(status) = child.try_wait().map_err(|error| error.to_string())? {
            break status;
        }
        thread::sleep(Duration::from_millis(40));
    };
    for (is_error, line) in receiver.try_iter() {
        let destination = if is_error { &mut stderr } else { &mut stdout };
        destination.push_str(&redact(&line));
        destination.push('\n');
    }
    ACTIVE_GIT_OPERATIONS.lock().remove(&operation_id);
    let cancelled = CANCELLED_GIT_OPERATIONS.lock().remove(&operation_id);
    let mut result = OperationResult {
        success: status.success(),
        exit_code: status.code().unwrap_or(-1),
        summary: if status.success() {
            format!("Subtree {action} completed.")
        } else {
            format!("Subtree {action} failed.")
        },
        stdout,
        stderr,
    };
    if result.success && matches!(options.action, SubtreeAction::Add | SubtreeAction::Pull) {
        let id = format!("{:x}", Sha256::digest(options.prefix.as_bytes()))[..12].to_owned();
        let registration = SubtreeInfo {
            id,
            prefix: options.prefix,
            repository,
            reference,
            squash: options.squash,
        };
        let saved = write_subtree_registry_unlocked(&path, &registration)?;
        append_operation(&mut result, &saved);
    }
    let _ = sink.add(OperationEvent {
        operation_id,
        operation: format!("subtree {action}"),
        phase: if cancelled {
            OperationPhase::Cancelled
        } else if result.success {
            OperationPhase::Completed
        } else {
            OperationPhase::Failed
        },
        message: result.summary.clone(),
        progress: result.success.then_some(1.0),
        result: Some(result),
    });
    Ok(())
}

pub fn cancel_git_operation(operation_id: String) -> Result<OperationResult, String> {
    let pid = ACTIVE_GIT_OPERATIONS
        .lock()
        .get(&operation_id)
        .copied()
        .ok_or_else(|| "The Git operation is no longer running.".to_owned())?;
    #[cfg(windows)]
    {
        let mut command = Command::new("taskkill.exe");
        hide_console_window(&mut command);
        let output = command
            .args(["/PID", &pid.to_string(), "/T", "/F"])
            .output()
            .map_err(|error| format!("Could not cancel Git: {error}"))?;
        if output.status.success() {
            CANCELLED_GIT_OPERATIONS.lock().insert(operation_id);
        }
        Ok(result_from_output("cancel Git operation", output))
    }
    #[cfg(not(windows))]
    Err(format!(
        "Cancelling process {pid} is not supported on this platform."
    ))
}

fn run_git(
    path: &str,
    args: Vec<String>,
    stdin: Option<Vec<u8>>,
    environment: &[(&str, &str)],
) -> Result<OperationResult, String> {
    let canonical = Repository::discover(path)
        .ok()
        .and_then(|repo| repo.workdir().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from(path));
    let key = display_path(&canonical);
    let lock = {
        let mut locks = REPOSITORY_LOCKS.lock();
        locks
            .entry(key)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _guard = lock.lock();
    let output = run_git_capture_with_stdin(path, args, stdin, environment)?;
    Ok(result_from_output("git operation", output))
}

fn hide_console_window(command: &mut Command) {
    #[cfg(windows)]
    command.creation_flags(0x0800_0000);
    #[cfg(not(windows))]
    let _ = command;
}

fn run_git_without_repo_named(
    operation: &str,
    args: Vec<String>,
) -> Result<OperationResult, String> {
    let output = run_git_without_repo_raw(args)?;
    Ok(result_from_output(operation, output))
}

fn run_git_without_repo_raw(args: Vec<String>) -> Result<std::process::Output, String> {
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    command
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let output = command
        .output()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    Ok(output)
}

fn run_subtree_capture(
    path: Option<&str>,
    arguments: Vec<String>,
) -> Result<std::process::Output, String> {
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    if let Some(path) = path {
        command.arg("-C").arg(path);
    }
    configure_subtree_environment(&mut command);
    command
        .arg("subtree")
        .args(arguments)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| format!("Git subtree could not be started: {error}"))
}

fn configure_subtree_environment(command: &mut Command) {
    let mut probe = Command::new("git");
    hide_console_window(&mut probe);
    if let Ok(output) = probe.arg("--exec-path").output()
        && output.status.success()
    {
        let exec_path = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        if !exec_path.is_empty() {
            let current = std::env::var_os("PATH").unwrap_or_default();
            let mut paths = vec![PathBuf::from(&exec_path)];
            paths.extend(std::env::split_paths(&current));
            if let Ok(joined) = std::env::join_paths(paths) {
                command.env("PATH", joined).env("GIT_EXEC_PATH", exec_path);
            }
        }
    }
}

fn run_config_mutation(
    path: Option<String>,
    scope: GitConfigScope,
    arguments: Vec<String>,
) -> Result<OperationResult, String> {
    let scope_argument = match scope {
        GitConfigScope::Local => "--local",
        GitConfigScope::Global => "--global",
        _ => return Err("Only repository and global Git settings can be changed.".to_owned()),
    };
    let args = [
        vec!["config".to_owned(), scope_argument.to_owned()],
        arguments,
    ]
    .concat();
    if scope == GitConfigScope::Local {
        let path = path.ok_or_else(|| "A repository is required for local settings.".to_owned())?;
        Repository::discover(&path).map_err(format_git_error)?;
        run_git(&path, args, None, &[])
    } else {
        let _guard = GLOBAL_GIT_LOCK.lock();
        run_git_without_repo_named("git config", args)
    }
}

fn git_output_lines(path: &str, arguments: Vec<&str>) -> Result<Vec<String>, String> {
    let output = run_git_capture(
        path,
        arguments.into_iter().map(str::to_owned).collect(),
        &[],
    )?;
    if !output.status.success() {
        return Err(redact(&String::from_utf8_lossy(&output.stderr)));
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_owned)
        .collect())
}

fn append_operation(target: &mut OperationResult, addition: &OperationResult) {
    target.success &= addition.success;
    if !addition.success {
        target.exit_code = addition.exit_code;
        target.summary = addition.summary.clone();
    }
    for (destination, value) in [
        (&mut target.stdout, &addition.stdout),
        (&mut target.stderr, &addition.stderr),
    ] {
        if !value.trim().is_empty() {
            if !destination.trim().is_empty() {
                destination.push('\n');
            }
            destination.push_str(value);
        }
    }
}

fn run_git_capture(
    path: &str,
    args: Vec<String>,
    environment: &[(&str, &str)],
) -> Result<std::process::Output, String> {
    run_git_capture_with_stdin(path, args, None, environment)
}

fn run_git_capture_with_stdin(
    path: &str,
    args: Vec<String>,
    stdin: Option<Vec<u8>>,
    environment: &[(&str, &str)],
) -> Result<std::process::Output, String> {
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    command
        .arg("-C")
        .arg(path)
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, value) in environment {
        command.env(key, value);
    }
    if stdin.is_some() {
        command.stdin(Stdio::piped());
    }
    let mut child = command
        .spawn()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    if let Some(input) = stdin {
        child
            .stdin
            .as_mut()
            .ok_or_else(|| "Git stdin was not available.".to_owned())?
            .write_all(&input)
            .map_err(|error| error.to_string())?;
    }
    child.wait_with_output().map_err(|error| error.to_string())
}

fn result_from_output(operation: &str, output: std::process::Output) -> OperationResult {
    let stdout = redact(&String::from_utf8_lossy(&output.stdout));
    let stderr = redact(&String::from_utf8_lossy(&output.stderr));
    let summary_source = if output.status.success() {
        stdout.lines().last().or_else(|| stderr.lines().last())
    } else {
        stderr.lines().last().or_else(|| stdout.lines().last())
    };
    OperationResult {
        success: output.status.success(),
        exit_code: output.status.code().unwrap_or(-1),
        summary: summary_source
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .unwrap_or(if output.status.success() {
                operation
            } else {
                "Git operation failed"
            })
            .to_owned(),
        stdout,
        stderr,
    }
}

fn select_hunk(patch: &str, selected: usize) -> Result<String, String> {
    let mut header = String::new();
    let mut hunks: Vec<String> = Vec::new();
    for line in patch.split_inclusive('\n') {
        if line.starts_with("@@") {
            hunks.push(String::new());
        }
        if hunks.is_empty() {
            header.push_str(line);
        } else if let Some(hunk) = hunks.last_mut() {
            hunk.push_str(line);
        }
    }
    let hunk = hunks
        .get(selected)
        .ok_or_else(|| "The selected hunk no longer exists.".to_owned())?;
    Ok(format!("{header}{hunk}"))
}

fn select_hunk_lines(
    patch: &str,
    hunk_index: usize,
    selected_lines: &HashSet<u32>,
    reverse: bool,
) -> Result<String, String> {
    if selected_lines.is_empty() {
        return Err("Select at least one changed line.".to_owned());
    }
    let hunk_patch = select_hunk(patch, hunk_index)?;
    let mut result = String::new();
    let mut in_hunk = false;
    let mut line_index = 0_u32;
    let mut selected_changes = 0_u32;
    for line in hunk_patch.split_inclusive('\n') {
        if line.starts_with("@@") {
            in_hunk = true;
            result.push_str(line);
            continue;
        }
        if !in_hunk {
            result.push_str(line);
            continue;
        }
        let selected = selected_lines.contains(&line_index);
        if line.starts_with('+') {
            if selected {
                result.push_str(line);
                selected_changes += 1;
            } else if reverse {
                result.push(' ');
                result.push_str(line.strip_prefix('+').unwrap_or(line));
            }
        } else if let Some(content) = line.strip_prefix('-') {
            if selected {
                result.push_str(line);
                selected_changes += 1;
            } else if !reverse {
                result.push(' ');
                result.push_str(content);
            }
        } else {
            result.push_str(line);
        }
        line_index += 1;
    }
    if selected_changes == 0 {
        return Err("The selected lines do not contain a change.".to_owned());
    }
    Ok(result)
}

fn nul_pathspec(paths: &[String]) -> Result<Vec<u8>, String> {
    if paths.is_empty() {
        return Err("Select at least one file.".to_owned());
    }
    let mut input = Vec::new();
    for path in paths {
        if path.is_empty() || path.as_bytes().contains(&0) {
            return Err("A selected path is invalid.".to_owned());
        }
        input.extend_from_slice(path.as_bytes());
        input.push(0);
    }
    Ok(input)
}

fn validate_identity(name: &str, email: &str) -> Result<(), String> {
    let invalid = |value: &str| {
        value.trim().is_empty()
            || value.contains(['\r', '\n'])
            || value.contains('<')
            || value.contains('>')
    };
    if invalid(name) || invalid(email) || !email.contains('@') {
        return Err("The commit author name or email is invalid.".to_owned());
    }
    Ok(())
}

fn find_commit<'repo>(repo: &'repo Repository, oid: &str) -> Result<git2::Commit<'repo>, String> {
    let oid = Oid::from_str(oid).map_err(format_git_error)?;
    repo.find_commit(oid).map_err(format_git_error)
}

fn ensure_no_operation_in_progress(repo: &Repository) -> Result<(), String> {
    if repo.state() == GitRepositoryState::Clean {
        Ok(())
    } else {
        Err("Finish or abort the current Git operation first.".to_owned())
    }
}

fn ensure_clean_tracked(repo: &Repository) -> Result<(), String> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| "A working tree is required.".to_owned())?;
    let output = run_git_capture(
        &display_path(workdir),
        vec![
            "status".to_owned(),
            "--porcelain=v1".to_owned(),
            "--untracked-files=no".to_owned(),
        ],
        &[],
    )?;
    if !output.status.success() {
        return Err(redact(&String::from_utf8_lossy(&output.stderr)));
    }
    if !output.stdout.is_empty() {
        Err("Commit or stash tracked changes before starting this operation.".to_owned())
    } else {
        Ok(())
    }
}

fn validate_mainline(
    commit: &git2::Commit<'_>,
    mainline_parent: Option<u32>,
) -> Result<(), String> {
    let count = commit.parent_count();
    if count > 1 {
        match mainline_parent {
            Some(parent) if parent > 0 && parent as usize <= count => Ok(()),
            _ => Err(format!(
                "Choose a mainline parent between 1 and {count} for this merge commit."
            )),
        }
    } else if mainline_parent.is_some() {
        Err("A mainline parent is only valid for a merge commit.".to_owned())
    } else {
        Ok(())
    }
}

fn control_sequence(
    path: &str,
    operation: &str,
    action: SequenceControl,
) -> Result<OperationResult, String> {
    let option = match action {
        SequenceControl::Continue => "--continue",
        SequenceControl::Skip => "--skip",
        SequenceControl::Abort => "--abort",
    };
    run_git(
        path,
        vec![
            "-c".to_owned(),
            "core.editor=true".to_owned(),
            operation.to_owned(),
            option.to_owned(),
        ],
        None,
        &[],
    )
}

fn validate_tag_name(path: &str, name: &str) -> Result<(), String> {
    if name.trim().is_empty() || name.starts_with('-') || name.contains('\0') {
        return Err("Invalid tag name.".to_owned());
    }
    let output = run_git_capture(
        path,
        vec!["check-ref-format".to_owned(), format!("refs/tags/{name}")],
        &[],
    )?;
    if output.status.success() {
        Ok(())
    } else {
        Err("Invalid tag name.".to_owned())
    }
}

fn build_reset_preview(repo: &Repository, target_oid: &str) -> Result<ResetPreview, String> {
    ensure_no_operation_in_progress(repo)?;
    let head = repo.head().map_err(format_git_error)?;
    if !head.is_branch() {
        return Err("Reset requires a checked-out local branch.".to_owned());
    }
    let current_branch = head.shorthand().map_err(format_git_error)?.to_owned();
    let head_commit = head.peel_to_commit().map_err(format_git_error)?;
    let target = find_commit(repo, target_oid)?;
    let target_tree = target.tree().map_err(format_git_error)?;

    let mut walk = repo.revwalk().map_err(format_git_error)?;
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME)
        .map_err(format_git_error)?;
    walk.push(head_commit.id()).map_err(format_git_error)?;
    walk.hide(target.id()).map_err(format_git_error)?;
    let mut outgoing_commits = Vec::new();
    for oid in walk {
        let commit = repo
            .find_commit(oid.map_err(format_git_error)?)
            .map_err(format_git_error)?;
        let value = commit.id().to_string();
        outgoing_commits.push(ResetCommit {
            short_oid: value[..8].to_owned(),
            oid: value,
            summary: commit
                .summary()
                .ok()
                .flatten()
                .unwrap_or("(no message)")
                .to_owned(),
        });
    }

    let status = collect_status(repo)?;
    let mut tracked_paths = status
        .iter()
        .filter(|file| !file.untracked)
        .map(|file| file.path.clone())
        .collect::<Vec<_>>();
    tracked_paths.sort();
    tracked_paths.dedup();
    let mut untracked_collisions = status
        .iter()
        .filter(|file| file.untracked)
        .filter_map(|file| untracked_collision_root(&target_tree, &file.path))
        .collect::<Vec<_>>();
    untracked_collisions.sort();
    untracked_collisions.dedup();

    let mut hasher = Sha256::new();
    hasher.update(head_commit.id().as_bytes());
    hasher.update(target.id().as_bytes());
    hasher.update(current_branch.as_bytes());
    for file in &status {
        hasher.update(file.path.as_bytes());
        hasher.update(format!(
            "{:?}:{:?}:{}",
            file.staged, file.unstaged, file.conflicted
        ));
    }
    for args in [
        vec!["diff".to_owned(), "--binary".to_owned()],
        vec![
            "diff".to_owned(),
            "--cached".to_owned(),
            "--binary".to_owned(),
        ],
    ] {
        let output = run_git_capture(
            &display_path(repo.workdir().unwrap_or(repo.path())),
            args,
            &[],
        )?;
        hasher.update(output.stdout);
    }

    Ok(ResetPreview {
        current_branch,
        target_oid: target.id().to_string(),
        outgoing_commits,
        tracked_paths,
        untracked_collisions,
        fingerprint: format!("{:x}", hasher.finalize()),
    })
}

fn untracked_collision_root(tree: &git2::Tree<'_>, relative: &str) -> Option<String> {
    let path = Path::new(relative);
    let components = path
        .components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value),
            _ => None,
        })
        .collect::<Vec<_>>();
    let mut current = PathBuf::new();
    for (index, component) in components.iter().enumerate() {
        current.push(component);
        let Ok(entry) = tree.get_path(&current) else {
            return None;
        };
        let is_last = index + 1 == components.len();
        if is_last || entry.kind() != Some(ObjectType::Tree) {
            return Some(display_path(current));
        }
    }
    None
}

fn validate_ref_name(name: &str) -> Result<(), String> {
    if name.trim().is_empty() || name.starts_with('-') || name.contains('\0') {
        return Err("Invalid branch or revision name.".to_owned());
    }
    Ok(())
}

fn validate_branch_name(name: &str) -> Result<(), String> {
    validate_ref_name(name)?;
    let mut command = Command::new("git");
    hide_console_window(&mut command);
    let output = command
        .args(["check-ref-format", "--branch", name])
        .output()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err("Invalid branch name.".to_owned())
    }
}

fn validate_remote_name(name: &str) -> Result<(), String> {
    static REMOTE_NAME: Lazy<Regex> =
        Lazy::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]*$").expect("valid remote name regex"));
    if REMOTE_NAME.is_match(name) && !name.ends_with('.') && !name.ends_with(".lock") {
        Ok(())
    } else {
        Err("Invalid remote name.".to_owned())
    }
}

fn validate_optional_url(value: Option<&str>) -> Result<(), String> {
    if let Some(value) = value
        && (value.trim().is_empty() || value.contains(['\0', '\r', '\n']) || value.starts_with('-'))
    {
        return Err("Invalid repository URL or path.".to_owned());
    }
    Ok(())
}

fn validate_config_key(key: &str) -> Result<(), String> {
    static CONFIG_KEY: Lazy<Regex> = Lazy::new(|| {
        Regex::new(r"^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9._-]*)+$")
            .expect("valid config key regex")
    });
    if CONFIG_KEY.is_match(key) && !key.contains("..") {
        Ok(())
    } else {
        Err("Invalid Git config key.".to_owned())
    }
}

fn validate_config_value(value: &str) -> Result<(), String> {
    if value.contains('\0') {
        Err("Git config values cannot contain NUL bytes.".to_owned())
    } else {
        Ok(())
    }
}

fn config_scope(value: &str) -> GitConfigScope {
    match value.trim().to_ascii_lowercase().as_str() {
        "system" => GitConfigScope::System,
        "global" => GitConfigScope::Global,
        "local" => GitConfigScope::Local,
        "worktree" => GitConfigScope::Worktree,
        "command" => GitConfigScope::Command,
        _ => GitConfigScope::Unknown,
    }
}

fn display_config_origin(value: &str) -> String {
    redact(value.trim().strip_prefix("file:").unwrap_or(value.trim()))
}

fn is_sensitive_config_key(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    key.ends_with(".extraheader")
        || key.contains("password")
        || key.contains("accesstoken")
        || key.contains("access-token")
        || key.contains("oauth")
}

fn normalize_sparse_directories(directories: Vec<String>) -> Result<Vec<String>, String> {
    let mut unique = HashSet::new();
    let mut result = Vec::new();
    for directory in directories {
        let normalized = directory.trim().replace('\\', "/");
        let path = Path::new(&normalized);
        if normalized.is_empty()
            || path.is_absolute()
            || path
                .components()
                .any(|part| !matches!(part, Component::Normal(_)))
        {
            return Err(format!("Invalid sparse checkout directory: {directory}"));
        }
        if unique.insert(normalized.to_lowercase()) {
            result.push(normalized);
        }
    }
    Ok(result)
}

fn gitignore_contents(template: &GitignoreTemplate) -> Option<&'static str> {
    match template {
        GitignoreTemplate::None => None,
        GitignoreTemplate::Flutter => Some(
            ".dart_tool/\n.flutter-plugins\n.flutter-plugins-dependencies\n.packages\n.pub-cache/\nbuild/\n*.iml\n.idea/\n",
        ),
        GitignoreTemplate::Rust => Some("/target/\n**/*.rs.bk\n*.pdb\n"),
        GitignoreTemplate::Node => {
            Some("node_modules/\nnpm-debug.log*\nyarn-debug.log*\n.env\ndist/\n")
        }
        GitignoreTemplate::Python => {
            Some("__pycache__/\n*.py[cod]\n.venv/\nvenv/\n.pytest_cache/\n.env\n")
        }
        GitignoreTemplate::VisualStudio => Some(".vs/\n[Bb]in/\n[Oo]bj/\n*.user\n*.suo\n*.pdb\n"),
    }
}

fn validate_rebase_plan(plan: &RebasePlan) -> Result<(), String> {
    validate_ref_name(&plan.upstream)?;
    if plan.items.is_empty() {
        return Err("There are no commits to rebase.".to_owned());
    }
    if matches!(
        plan.items.first().map(|item| &item.action),
        Some(RebaseAction::Squash | RebaseAction::Fixup)
    ) {
        return Err("The first rebase item cannot be squash or fixup.".to_owned());
    }
    for item in &plan.items {
        Oid::from_str(&item.oid).map_err(format_git_error)?;
        if matches!(item.action, RebaseAction::Reword | RebaseAction::Squash)
            && item
                .new_message
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty()
        {
            return Err("Reword and squash items require a commit message.".to_owned());
        }
    }
    Ok(())
}

fn rebase_action_name(action: &RebaseAction) -> &'static str {
    match action {
        RebaseAction::Pick => "pick",
        RebaseAction::Reword => "reword",
        RebaseAction::Squash => "squash",
        RebaseAction::Fixup => "fixup",
        RebaseAction::Drop => "drop",
    }
}

fn sequence_editor_path() -> Result<PathBuf, String> {
    if let Ok(value) = std::env::var("GITFRONT_SEQUENCE_EDITOR") {
        return Ok(PathBuf::from(value));
    }
    let mut path = std::env::current_exe().map_err(|error| error.to_string())?;
    path.set_file_name(if cfg!(windows) {
        "gitfront_sequence_editor.exe"
    } else {
        "gitfront_sequence_editor"
    });
    if path.exists() {
        Ok(path)
    } else {
        Err("The interactive rebase helper is missing from the application directory.".to_owned())
    }
}

fn quoted_editor_command(helper: &Path, mode: &str) -> String {
    format!("\"{}\" {mode}", helper.to_string_lossy())
}

fn rebase_session_path(repo: &Repository) -> PathBuf {
    repo.path().join("gitfront-rebase-session")
}

fn cleanup_rebase_session(marker: &Path, session: Option<&str>) {
    let _ = fs::remove_file(marker);
    if let Some(session) = session {
        let directory = PathBuf::from(session);
        if directory.starts_with(std::env::temp_dir()) {
            let _ = fs::remove_dir_all(directory);
        }
    }
}

fn sanitize_todo(value: &str) -> String {
    value.replace(['\r', '\n', '\0'], " ")
}

fn read_blob(repo: &Repository, oid: Oid) -> Option<Vec<u8>> {
    repo.find_blob(oid).ok().map(|blob| blob.content().to_vec())
}

fn parse_conflict_regions(content: &str) -> Vec<ConflictRegion> {
    enum Part {
        None,
        Ours,
        Base,
        Theirs,
    }
    let mut part = Part::None;
    let mut ours = String::new();
    let mut base = String::new();
    let mut theirs = String::new();
    let mut regions = Vec::new();
    for line in content.split_inclusive('\n') {
        if line.starts_with("<<<<<<<") {
            part = Part::Ours;
            ours.clear();
            base.clear();
            theirs.clear();
        } else if line.starts_with("|||||||") && matches!(part, Part::Ours) {
            part = Part::Base;
        } else if line.starts_with("=======") && matches!(part, Part::Ours | Part::Base) {
            part = Part::Theirs;
        } else if line.starts_with(">>>>>>>") && matches!(part, Part::Theirs) {
            regions.push(ConflictRegion {
                index: regions.len() as u32,
                base: base.clone(),
                ours: ours.clone(),
                theirs: theirs.clone(),
            });
            part = Part::None;
        } else {
            match part {
                Part::Ours => ours.push_str(line),
                Part::Base => base.push_str(line),
                Part::Theirs => theirs.push_str(line),
                Part::None => {}
            }
        }
    }
    regions
}

fn safe_relative_path(path: &str) -> Result<&Path, String> {
    let path = Path::new(path);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err("The selected file is outside the repository.".to_owned());
    }
    Ok(path)
}

fn safe_worktree_path(repo: &Repository, path: &str) -> Result<PathBuf, String> {
    let relative = safe_relative_path(path)?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| "Bare repositories are not supported.".to_owned())?;
    Ok(workdir.join(relative))
}

fn is_binary(bytes: &[u8]) -> bool {
    bytes.iter().take(8192).any(|byte| *byte == 0) || std::str::from_utf8(bytes).is_err()
}

fn conflict_ours_label(state: GitRepositoryState) -> String {
    if matches!(
        state,
        GitRepositoryState::Rebase
            | GitRepositoryState::RebaseInteractive
            | GitRepositoryState::RebaseMerge
    ) {
        "Upstream (current base)".to_owned()
    } else {
        "Current branch".to_owned()
    }
}

fn conflict_theirs_label(state: GitRepositoryState) -> String {
    if matches!(
        state,
        GitRepositoryState::Rebase
            | GitRepositoryState::RebaseInteractive
            | GitRepositoryState::RebaseMerge
    ) {
        "Replayed commit".to_owned()
    } else {
        "Merged branch".to_owned()
    }
}

fn map_repository_state(state: GitRepositoryState) -> RepositoryState {
    match state {
        GitRepositoryState::Clean => RepositoryState::Clean,
        GitRepositoryState::Merge => RepositoryState::Merge,
        GitRepositoryState::Rebase => RepositoryState::Rebase,
        GitRepositoryState::RebaseInteractive => RepositoryState::RebaseInteractive,
        GitRepositoryState::RebaseMerge => RepositoryState::RebaseMerge,
        GitRepositoryState::CherryPick | GitRepositoryState::CherryPickSequence => {
            RepositoryState::CherryPick
        }
        GitRepositoryState::Revert | GitRepositoryState::RevertSequence => RepositoryState::Revert,
        GitRepositoryState::Bisect => RepositoryState::Bisect,
        GitRepositoryState::ApplyMailbox | GitRepositoryState::ApplyMailboxOrRebase => {
            RepositoryState::ApplyMailbox
        }
    }
}

fn next_generation(path: &str) -> u64 {
    let mut generations = GENERATIONS.lock();
    let generation = generations.entry(path.to_owned()).or_insert(0);
    *generation += 1;
    *generation
}

fn short_reference(value: &str) -> String {
    value
        .strip_prefix("refs/heads/")
        .unwrap_or(value)
        .to_owned()
}

fn display_path(path: impl AsRef<Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}

fn redact(value: &str) -> String {
    let value = CREDENTIAL_URL.replace_all(value, "$1***:***@");
    CREDENTIAL_USER_URL
        .replace_all(&value, "$1***@")
        .into_owned()
}

fn format_git_error(error: git2::Error) -> String {
    format!(
        "{} ({:?}/{:?})",
        error.message(),
        error.class(),
        error.code()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_credentials_in_urls() {
        assert_eq!(
            redact("fatal: https://alice:secret@example.com/repo"),
            "fatal: https://***:***@example.com/repo"
        );
        assert_eq!(
            redact("https://secret-token@example.com/repo"),
            "https://***@example.com/repo"
        );
    }

    #[test]
    fn selects_one_patch_hunk() {
        let patch =
            "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-a\n+b\n@@ -3 +3 @@\n-c\n+d\n";
        let selected = select_hunk(patch, 1).unwrap();
        assert!(selected.contains("-c"));
        assert!(!selected.contains("-a"));
        assert!(selected.starts_with("diff --git"));
    }

    #[test]
    fn parses_diff3_conflict_regions() {
        let text = "before\n<<<<<<< ours\nleft\n||||||| base\nold\n=======\nright\n>>>>>>> theirs\nafter\n";
        let regions = parse_conflict_regions(text);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].base, "old\n");
        assert_eq!(regions[0].ours, "left\n");
        assert_eq!(regions[0].theirs, "right\n");
    }

    #[test]
    fn rejects_parent_paths() {
        assert!(safe_relative_path("../outside").is_err());
        assert!(safe_relative_path("src/main.rs").is_ok());
    }

    #[test]
    fn validates_setup_inputs() {
        assert!(validate_remote_name("origin").is_ok());
        assert!(validate_remote_name("upstream-2").is_ok());
        assert!(validate_remote_name("bad/name").is_err());
        assert!(validate_config_key("user.name").is_ok());
        assert!(validate_config_key("remote.origin.url").is_ok());
        assert!(validate_config_key("invalid").is_err());
        assert!(normalize_sparse_directories(vec!["src/core".to_owned()]).is_ok());
        assert!(normalize_sparse_directories(vec!["../outside".to_owned()]).is_err());
        assert!(normalize_sparse_directories(vec!["C:\\outside".to_owned()]).is_err());
    }

    #[test]
    fn masks_sensitive_config_keys() {
        assert!(is_sensitive_config_key("http.example.extraHeader"));
        assert!(is_sensitive_config_key("service.accessToken"));
        assert!(!is_sensitive_config_key("credential.helper"));
        assert!(!is_sensitive_config_key("user.email"));
    }

    #[test]
    fn bundled_gitignore_templates_are_offline() {
        assert!(gitignore_contents(&GitignoreTemplate::None).is_none());
        assert!(
            gitignore_contents(&GitignoreTemplate::Flutter)
                .unwrap()
                .contains(".dart_tool/")
        );
        assert!(
            gitignore_contents(&GitignoreTemplate::Rust)
                .unwrap()
                .contains("/target/")
        );
    }
}
