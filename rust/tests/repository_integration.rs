use rust_lib_gitfront_preview::api::git::{
    apply_hunk, clone_repository, control_merge, create_branch, create_commit, fetch_all,
    get_worktree_diff, list_commits, load_conflict, merge_branch, open_repository, push_current,
    stage_paths, stash_apply, stash_save, switch_branch,
};
use rust_lib_gitfront_preview::api::models::{ChangeKind, MergeControl, RepositoryState};
use std::fs;
use std::path::Path;
use std::process::Command;
use tempfile::TempDir;

fn git(directory: &Path, arguments: &[&str]) {
    let output = Command::new("git")
        .arg("-C")
        .arg(directory)
        .args(arguments)
        .output()
        .expect("git starts");
    assert!(
        output.status.success(),
        "git {:?} failed: {}",
        arguments,
        String::from_utf8_lossy(&output.stderr)
    );
}

fn repository() -> TempDir {
    let directory = tempfile::tempdir().expect("temp repository");
    git(directory.path(), &["init", "-b", "main"]);
    git(directory.path(), &["config", "user.name", "GitFront Test"]);
    git(
        directory.path(),
        &["config", "user.email", "gitfront@example.invalid"],
    );
    fs::write(directory.path().join("notes.txt"), "one\ntwo\n").expect("fixture file");
    git(directory.path(), &["add", "notes.txt"]);
    git(directory.path(), &["commit", "-m", "initial"]);
    directory
}

#[test]
fn reads_diff_stages_and_commits() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(
        directory.path().join("notes.txt"),
        "one\ntwo changed\nthree\n",
    )
    .expect("modify fixture");

    let snapshot = open_repository(path.clone()).expect("snapshot");
    assert_eq!(snapshot.head_name.as_deref(), Some("main"));
    assert_eq!(snapshot.files.len(), 1);
    assert_eq!(snapshot.files[0].unstaged, ChangeKind::Modified);

    let diff = get_worktree_diff(path.clone(), Some("notes.txt".to_owned()), false)
        .expect("worktree diff");
    assert_eq!(diff.files.len(), 1);
    assert!(!diff.files[0].hunks.is_empty());

    let staged = stage_paths(path.clone(), vec!["notes.txt".to_owned()]).expect("stage");
    assert!(staged.success, "{}", staged.stderr);
    let after_stage = open_repository(path.clone()).expect("staged snapshot");
    assert_eq!(after_stage.files[0].staged, ChangeKind::Modified);

    let committed = create_commit(path.clone(), "update notes".to_owned()).expect("commit");
    assert!(committed.success, "{}", committed.stderr);
    let page = list_commits(path, 0, 200).expect("history");
    assert_eq!(page.commits.len(), 2);
    assert_eq!(page.commits[0].summary, "update notes");
}

#[test]
fn manages_branches_and_stashes() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();

    let branch =
        create_branch(path.clone(), "feature/test".to_owned(), None, true).expect("create branch");
    assert!(branch.success, "{}", branch.stderr);
    assert_eq!(
        open_repository(path.clone()).unwrap().head_name.as_deref(),
        Some("feature/test")
    );

    fs::write(directory.path().join("notes.txt"), "stashed\n").expect("stash fixture");
    let saved = stash_save(path.clone(), "work in progress".to_owned(), false).expect("stash");
    assert!(saved.success, "{}", saved.stderr);
    let snapshot = open_repository(path.clone()).expect("snapshot with stash");
    assert_eq!(snapshot.stashes.len(), 1);

    let applied = stash_apply(path.clone(), 0, true).expect("pop stash");
    assert!(applied.success, "{}", applied.stderr);
    assert!(!open_repository(path.clone()).unwrap().files.is_empty());

    let switched = switch_branch(path.clone(), "main".to_owned()).expect("switch main");
    assert!(switched.success, "{}", switched.stderr);
    assert_eq!(
        open_repository(path).unwrap().head_name.as_deref(),
        Some("main")
    );
}

#[test]
fn stages_and_unstages_individual_hunks() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let original = (1..=24)
        .map(|line| format!("line {line}\n"))
        .collect::<String>();
    fs::write(directory.path().join("hunks.txt"), &original).expect("hunk fixture");
    git(directory.path(), &["add", "hunks.txt"]);
    git(directory.path(), &["commit", "-m", "add hunk fixture"]);
    let changed = original
        .replace("line 2\n", "line 2 changed\n")
        .replace("line 22\n", "line 22 changed\n");
    fs::write(directory.path().join("hunks.txt"), changed).expect("modify hunks");

    let unstaged = get_worktree_diff(path.clone(), Some("hunks.txt".to_owned()), false)
        .expect("unstaged diff");
    assert_eq!(unstaged.files[0].hunks.len(), 2);
    let staged = apply_hunk(
        path.clone(),
        "hunks.txt".to_owned(),
        false,
        0,
        unstaged.fingerprint,
        false,
    )
    .expect("stage first hunk");
    assert!(staged.success, "{}", staged.stderr);
    let snapshot = open_repository(path.clone()).expect("partially staged snapshot");
    assert_eq!(snapshot.files[0].staged, ChangeKind::Modified);
    assert_eq!(snapshot.files[0].unstaged, ChangeKind::Modified);

    let staged_diff =
        get_worktree_diff(path.clone(), Some("hunks.txt".to_owned()), true).expect("staged diff");
    let unstaged = apply_hunk(
        path.clone(),
        "hunks.txt".to_owned(),
        true,
        0,
        staged_diff.fingerprint,
        true,
    )
    .expect("unstage first hunk");
    assert!(unstaged.success, "{}", unstaged.stderr);
    assert_eq!(
        open_repository(path).unwrap().files[0].staged,
        ChangeKind::None
    );
}

#[test]
fn exposes_and_aborts_merge_conflicts() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    git(directory.path(), &["switch", "-c", "feature"]);
    fs::write(directory.path().join("notes.txt"), "feature\n").expect("feature change");
    git(directory.path(), &["commit", "-am", "feature change"]);
    git(directory.path(), &["switch", "main"]);
    fs::write(directory.path().join("notes.txt"), "main\n").expect("main change");
    git(directory.path(), &["commit", "-am", "main change"]);

    let result = merge_branch(path.clone(), "feature".to_owned()).expect("merge starts");
    assert!(!result.success);
    let snapshot = open_repository(path.clone()).expect("merge snapshot");
    assert_eq!(snapshot.state, RepositoryState::Merge);
    assert!(snapshot.files[0].conflicted);
    let conflict = load_conflict(path.clone(), "notes.txt".to_owned()).expect("conflict data");
    assert!(!conflict.ours.is_empty());
    assert!(!conflict.theirs.is_empty());

    let aborted = control_merge(path.clone(), MergeControl::Abort).expect("abort merge");
    assert!(aborted.success, "{}", aborted.stderr);
    assert_eq!(open_repository(path).unwrap().state, RepositoryState::Clean);
}

#[test]
fn clones_and_pushes_to_a_local_remote() {
    let source = repository();
    let remote = tempfile::tempdir().expect("bare remote directory");
    git(remote.path(), &["init", "--bare", "--initial-branch=main"]);
    git(
        source.path(),
        &["remote", "add", "origin", &remote.path().to_string_lossy()],
    );
    git(source.path(), &["push", "-u", "origin", "main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    let clone_path = clone_parent.path().join("clone");
    let cloned = clone_repository(
        remote.path().to_string_lossy().into_owned(),
        clone_path.to_string_lossy().into_owned(),
    )
    .expect("clone result");
    assert!(cloned.success, "{}", cloned.stderr);
    git(&clone_path, &["config", "user.name", "GitFront Test"]);
    git(
        &clone_path,
        &["config", "user.email", "gitfront@example.invalid"],
    );
    fs::write(clone_path.join("remote.txt"), "pushed\n").expect("remote fixture");
    let path = clone_path.to_string_lossy().into_owned();
    assert!(
        stage_paths(path.clone(), vec!["remote.txt".to_owned()])
            .unwrap()
            .success
    );
    assert!(
        create_commit(path.clone(), "remote update".to_owned())
            .unwrap()
            .success
    );
    assert!(push_current(path.clone(), false, false).unwrap().success);
    assert!(fetch_all(path).unwrap().success);

    let output = Command::new("git")
        .arg("--git-dir")
        .arg(remote.path())
        .args(["log", "-1", "--pretty=%s", "main"])
        .output()
        .expect("inspect remote");
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "remote update"
    );
}
