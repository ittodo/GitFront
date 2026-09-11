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
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::time::Duration;
use uuid::Uuid;

const MAX_RENDER_BYTES: u64 = 5 * 1024 * 1024;
type HeadInformation = (Option<String>, Option<String>, Option<String>, i64, i64);

static GENERATIONS: Lazy<Mutex<HashMap<String, u64>>> = Lazy::new(|| Mutex::new(HashMap::new()));
static REPOSITORY_LOCKS: Lazy<Mutex<HashMap<String, Arc<Mutex<()>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static CREDENTIAL_URL: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)(https?://)([^/@\s:]+):([^/@\s]+)@").expect("valid credential regex")
});

pub fn git_version() -> Result<String, String> {
    let output = Command::new("git")
        .arg("--version")
        .output()
        .map_err(|error| format!("Git was not found: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

pub fn open_repository(path: String) -> Result<RepositorySnapshot, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    build_snapshot(&repo)
}

pub fn refresh_repository(path: String) -> Result<RepositorySnapshot, String> {
    open_repository(path)
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
    let branches = collect_branches(repo)?;
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
    files.sort_by(|left, right| {
        right
            .conflicted
            .cmp(&left.conflicted)
            .then_with(|| right.untracked.cmp(&left.untracked))
            .then_with(|| left.path.to_lowercase().cmp(&right.path.to_lowercase()))
    });
    Ok(files)
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

fn collect_branches(repo: &Repository) -> Result<Vec<BranchInfo>, String> {
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
        let mut ahead = 0;
        let mut behind = 0;
        if !is_remote && let Ok(upstream_branch) = branch.upstream() {
            upstream = upstream_branch.name().ok().flatten().map(str::to_owned);
            if let (Some(local_oid), Some(remote_oid)) =
                (branch.get().target(), upstream_branch.get().target())
                && let Ok((a, b)) = repo.graph_ahead_behind(local_oid, remote_oid)
            {
                ahead = a as i64;
                behind = b as i64;
            }
        }
        branches.push(BranchInfo {
            name,
            full_name,
            oid,
            is_head: branch.is_head(),
            is_remote,
            upstream,
            ahead,
            behind,
        });
    }
    branches.sort_by(|left, right| {
        right
            .is_head
            .cmp(&left.is_head)
            .then_with(|| left.is_remote.cmp(&right.is_remote))
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
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

    let references = references_by_oid(&repo)?;
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
            references: references.get(&oid).cloned().unwrap_or_default(),
            lane: GraphLane {
                column: 0,
                parent_columns: Vec::new(),
            },
        });
    }
    let has_more = raw.len() > requested;
    raw.truncate(requested);
    assign_graph_lanes(&mut raw);
    Ok(CommitPage {
        commits: raw,
        next_offset: has_more.then_some(offset + requested as u32),
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

fn references_by_oid(repo: &Repository) -> Result<HashMap<Oid, Vec<String>>, String> {
    let mut result: HashMap<Oid, Vec<String>> = HashMap::new();
    for reference_result in repo.references().map_err(format_git_error)? {
        let reference = reference_result.map_err(format_git_error)?;
        if let Ok(commit) = reference.peel(ObjectType::Commit)
            && let Ok(name) = reference.shorthand()
        {
            result.entry(commit.id()).or_default().push(name.to_owned());
        }
    }
    Ok(result)
}

fn assign_graph_lanes(commits: &mut [CommitSummary]) {
    let mut lanes: Vec<String> = Vec::new();
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
    let mut args = vec!["add".to_owned(), "--".to_owned()];
    args.extend(paths);
    run_git(&path, args, None, &[])
}

pub fn unstage_paths(path: String, paths: Vec<String>) -> Result<OperationResult, String> {
    let repo = Repository::discover(&path).map_err(format_git_error)?;
    let mut args = if repo.head().is_ok() {
        vec!["restore".to_owned(), "--staged".to_owned(), "--".to_owned()]
    } else {
        vec!["rm".to_owned(), "--cached".to_owned(), "--".to_owned()]
    };
    args.extend(paths);
    run_git(&path, args, None, &[])
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
    if message.trim().is_empty() {
        return Err("A commit message is required.".to_owned());
    }
    run_git(
        &path,
        vec!["commit".to_owned(), "-m".to_owned(), message],
        None,
        &[],
    )
}

pub fn clone_repository(url: String, target: String) -> Result<OperationResult, String> {
    let target_path = Path::new(&target);
    if target_path.exists()
        && target_path
            .read_dir()
            .map_err(|error| error.to_string())?
            .next()
            .is_some()
    {
        return Err("The clone destination must be empty.".to_owned());
    }
    let args = vec!["clone".to_owned(), "--progress".to_owned(), url, target];
    run_git_without_repo(args)
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

fn run_git_without_repo(args: Vec<String>) -> Result<OperationResult, String> {
    let mut command = Command::new("git");
    command
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let output = command
        .output()
        .map_err(|error| format!("Git could not be started: {error}"))?;
    Ok(result_from_output("git clone", output))
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

fn validate_ref_name(name: &str) -> Result<(), String> {
    if name.trim().is_empty() || name.starts_with('-') || name.contains('\0') {
        return Err("Invalid branch or revision name.".to_owned());
    }
    Ok(())
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
    CREDENTIAL_URL.replace_all(value, "$1***:***@").into_owned()
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
}
