use rust_lib_gitfront_preview::api::git::{
    add_git_config_value, add_remote, apply_hunk, apply_hunk_lines, assess_cherry_pick,
    checkout_commit, cherry_pick_commit, clone_repository, clone_repository_advanced,
    compare_commits, control_cherry_pick, control_merge, control_revert, create_branch,
    create_commit, create_commit_with_options, create_tag, create_tracking_branch,
    disable_sparse_checkout, fetch_all, get_worktree_diff, initialize_repository, intent_to_add,
    list_branches_cursor, list_changes_cursor, list_commits, list_commits_cursor,
    list_remote_details, list_submodules, list_submodules_cursor, list_subtrees,
    load_commit_defaults, load_conflict, merge_branch, open_repository, preview_remove_submodule,
    preview_reset, push_current, push_current_to, read_git_config, read_sparse_checkout,
    refresh_repository_paged, refresh_working_tree, register_subtree, remove_remote,
    remove_submodule, rename_remote, reset_to_commit, revert_commit, set_git_config,
    set_sparse_checkout, stage_paths, stash_apply, stash_save, switch_branch,
    unset_git_config_value, update_remote,
};
use rust_lib_gitfront_preview::api::models::{
    ChangeKind, CherryPickApplicability, CloneOptions, CommitOptions, CommitReferenceKind,
    CommitSigningMode, GitConfigScope, GitignoreTemplate, MergeControl, RepositoryInitOptions,
    RepositoryState, ResetMode, SequenceControl, SubmoduleState, SubtreeInfo,
};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
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

fn git_text(directory: &Path, arguments: &[&str]) -> String {
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
    String::from_utf8_lossy(&output.stdout).trim().to_owned()
}

fn create_branch_refs(directory: &Path, names: impl IntoIterator<Item = String>) {
    let head = git_text(directory, &["rev-parse", "HEAD"]);
    let mut input = String::new();
    for name in names {
        input.push_str(&format!("create refs/heads/{name} {head}\n"));
    }
    let mut child = Command::new("git")
        .arg("-C")
        .arg(directory)
        .args(["update-ref", "--stdin"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("git update-ref starts");
    child
        .stdin
        .as_mut()
        .expect("git update-ref stdin")
        .write_all(input.as_bytes())
        .expect("write branch refs");
    let output = child.wait_with_output().expect("git update-ref completes");
    assert!(
        output.status.success(),
        "git update-ref failed: {}",
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
fn initializes_a_safe_working_repository() {
    let parent = tempfile::tempdir().expect("temporary parent");
    let target = parent.path().join("new-project");
    fs::create_dir_all(&target).expect("target folder");
    fs::write(target.join("README.md"), "existing\n").expect("existing readme");
    let result = initialize_repository(RepositoryInitOptions {
        target_path: target.to_string_lossy().into_owned(),
        initial_branch: "main".to_owned(),
        create_readme: true,
        gitignore_template: GitignoreTemplate::Rust,
        origin_url: None,
    })
    .expect("initialize repository");
    assert!(result.operation.success, "{}", result.operation.stderr);
    assert!(result.warnings.iter().any(|value| value.contains("README")));
    assert_eq!(
        fs::read_to_string(target.join("README.md")).unwrap(),
        "existing\n"
    );
    assert!(target.join(".gitignore").exists());
    let snapshot = open_repository(target.to_string_lossy().into_owned()).expect("snapshot");
    assert_eq!(snapshot.head_name.as_deref(), Some("main"));
    assert!(snapshot.head_oid.is_none());
}

#[test]
fn manages_local_config_remotes_and_sparse_checkout() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let set = set_git_config(
        Some(path.clone()),
        GitConfigScope::Local,
        "gitfront.test".to_owned(),
        "one".to_owned(),
    )
    .expect("set config");
    assert!(set.success, "{}", set.stderr);
    let added = add_git_config_value(
        Some(path.clone()),
        GitConfigScope::Local,
        "gitfront.multi".to_owned(),
        "first".to_owned(),
    )
    .expect("add config");
    assert!(added.success, "{}", added.stderr);
    let config = read_git_config(Some(path.clone())).expect("read config");
    assert!(config.entries.iter().any(|entry| {
        entry.scope == GitConfigScope::Local && entry.key == "gitfront.test" && entry.value == "one"
    }));
    assert!(
        set_git_config(
            Some(path.clone()),
            GitConfigScope::Local,
            "http.example.extraheader".to_owned(),
            "Authorization: Bearer secret".to_owned(),
        )
        .unwrap()
        .success
    );
    let protected = read_git_config(Some(path.clone())).expect("read protected config");
    assert!(protected.entries.iter().any(|entry| {
        entry.key == "http.example.extraheader" && entry.sensitive && entry.value == "••••••••"
    }));
    let unset = unset_git_config_value(
        Some(path.clone()),
        GitConfigScope::Local,
        "gitfront.multi".to_owned(),
        Some("first".to_owned()),
    )
    .expect("unset config");
    assert!(unset.success, "{}", unset.stderr);

    let remote_directory = tempfile::tempdir().expect("remote directory");
    git(remote_directory.path(), &["init", "--bare"]);
    let added = add_remote(
        path.clone(),
        "backup".to_owned(),
        remote_directory.path().to_string_lossy().into_owned(),
    )
    .expect("add remote");
    assert!(added.success, "{}", added.stderr);
    let renamed = rename_remote(path.clone(), "backup".to_owned(), "mirror".to_owned())
        .expect("rename remote");
    assert!(renamed.success, "{}", renamed.stderr);
    let updated = update_remote(
        path.clone(),
        "mirror".to_owned(),
        remote_directory.path().to_string_lossy().into_owned(),
        None,
    )
    .expect("update remote");
    assert!(updated.success, "{}", updated.stderr);
    assert!(
        list_remote_details(path.clone())
            .unwrap()
            .iter()
            .any(|remote| remote.name == "mirror")
    );
    assert!(
        remove_remote(path.clone(), "mirror".to_owned())
            .unwrap()
            .success
    );

    fs::create_dir_all(directory.path().join("src")).expect("src folder");
    fs::create_dir_all(directory.path().join("docs")).expect("docs folder");
    fs::write(directory.path().join("src/main.rs"), "fn main() {}\n").expect("src file");
    fs::write(directory.path().join("docs/guide.md"), "guide\n").expect("docs file");
    git(directory.path(), &["add", "src", "docs"]);
    git(directory.path(), &["commit", "-m", "add folders"]);
    let sparse = set_sparse_checkout(path.clone(), vec!["src".to_owned()]).expect("set sparse");
    assert!(sparse.success, "{}", sparse.stderr);
    let state = read_sparse_checkout(path.clone()).expect("read sparse");
    assert!(state.enabled);
    assert_eq!(state.directories, vec!["src"]);
    assert!(open_repository(path.clone()).unwrap().files.is_empty());
    assert!(disable_sparse_checkout(path).unwrap().success);
}

#[test]
fn clones_with_practical_options_and_sparse_checkout() {
    let source = repository();
    fs::create_dir_all(source.path().join("src")).expect("src folder");
    fs::write(source.path().join("src/lib.rs"), "pub fn value() {}\n").expect("source file");
    git(source.path(), &["add", "src"]);
    git(source.path(), &["commit", "-m", "add source"]);
    let remote = tempfile::tempdir().expect("bare remote");
    git(remote.path(), &["init", "--bare"]);
    git(
        source.path(),
        &["remote", "add", "origin", &remote.path().to_string_lossy()],
    );
    git(source.path(), &["push", "origin", "main"]);

    let parent = tempfile::tempdir().expect("clone parent");
    let target = parent.path().join("clone");
    let result = clone_repository_advanced(CloneOptions {
        url: remote.path().to_string_lossy().into_owned(),
        target: target.to_string_lossy().into_owned(),
        remote_name: "upstream".to_owned(),
        branch: Some("main".to_owned()),
        depth: Some(1),
        single_branch: true,
        no_tags: true,
        recurse_submodules: false,
        shallow_submodules: false,
        blobless: false,
        sparse_directories: vec!["src".to_owned()],
    })
    .expect("advanced clone");
    assert!(result.operation.success, "{}", result.operation.stderr);
    assert!(target.join("src/lib.rs").exists());
    assert_eq!(
        read_sparse_checkout(target.to_string_lossy().into_owned())
            .unwrap()
            .directories,
        vec!["src"]
    );
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
fn refreshes_only_working_tree_data_for_file_events() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let before = open_repository(path.clone()).expect("initial snapshot");
    fs::write(directory.path().join("notes.txt"), "fast refresh\n").expect("modify fixture");

    let working_tree = refresh_working_tree(path).expect("working tree snapshot");

    assert!(working_tree.generation > before.generation);
    assert_eq!(working_tree.state, RepositoryState::Clean);
    assert_eq!(working_tree.files.len(), 1);
    assert_eq!(working_tree.files[0].unstaged, ChangeKind::Modified);
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

    git(&clone_path, &["switch", "-c", "topic"]);
    fs::write(clone_path.join("topic.txt"), "topic\n").expect("topic fixture");
    git(&clone_path, &["add", "topic.txt"]);
    git(&clone_path, &["commit", "-m", "topic update"]);
    assert!(
        push_current_to(
            clone_path.to_string_lossy().into_owned(),
            "origin".to_owned(),
            "published-topic".to_owned(),
            false,
        )
        .unwrap()
        .success
    );

    let tracking_parent = tempfile::tempdir().expect("tracking clone parent");
    let tracking_path = tracking_parent.path().join("clone");
    assert!(
        clone_repository(
            remote.path().to_string_lossy().into_owned(),
            tracking_path.to_string_lossy().into_owned(),
        )
        .unwrap()
        .success
    );
    let tracked = create_tracking_branch(
        tracking_path.to_string_lossy().into_owned(),
        "origin/published-topic".to_owned(),
        "topic".to_owned(),
    )
    .expect("tracking branch");
    assert!(tracked.success, "{}", tracked.stderr);
    assert_eq!(
        git_text(
            &tracking_path,
            &["rev-parse", "--abbrev-ref", "@{upstream}"]
        ),
        "origin/published-topic"
    );
}

#[test]
fn classifies_commit_references_and_compares_commits() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let first_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    git(directory.path(), &["branch", "feature/readme"]);
    git(
        directory.path(),
        &["update-ref", "refs/remotes/upstream/main", "HEAD"],
    );
    assert!(
        create_tag(
            path.clone(),
            first_oid.clone(),
            "v0.1.0".to_owned(),
            false,
            None,
        )
        .unwrap()
        .success
    );
    assert!(
        create_tag(
            path.clone(),
            first_oid.clone(),
            "v0.1.0-annotated".to_owned(),
            true,
            Some("first release".to_owned()),
        )
        .unwrap()
        .success
    );

    let page = list_commits(path.clone(), 0, 200).expect("history with refs");
    let references = &page.commits[0].references;
    assert_eq!(references[0].kind, CommitReferenceKind::Head);
    assert!(references.iter().any(|reference| {
        reference.kind == CommitReferenceKind::LocalBranch && reference.name == "main"
    }));
    assert!(references.iter().any(|reference| {
        reference.kind == CommitReferenceKind::RemoteBranch && reference.name == "upstream/main"
    }));
    assert_eq!(
        references
            .iter()
            .filter(|reference| reference.kind == CommitReferenceKind::Tag)
            .count(),
        2
    );

    fs::write(directory.path().join("notes.txt"), "one\ntwo changed\n")
        .expect("second commit fixture");
    git(directory.path(), &["commit", "-am", "second"]);
    let second_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    let comparison = compare_commits(path, first_oid, second_oid).expect("comparison");
    assert!(!comparison.files.is_empty());
    assert!(
        comparison.files[0]
            .hunks
            .iter()
            .flat_map(|hunk| &hunk.lines)
            .any(|line| line.content.contains("two changed"))
    );
}

#[test]
fn cherry_picks_reverts_and_checks_out_commits() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let initial_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    git(directory.path(), &["switch", "-c", "feature"]);
    fs::write(directory.path().join("feature.txt"), "feature\n").expect("feature fixture");
    git(directory.path(), &["add", "feature.txt"]);
    git(directory.path(), &["commit", "-m", "feature"]);
    let feature_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    git(directory.path(), &["switch", "main"]);

    let picked = cherry_pick_commit(path.clone(), feature_oid, None).expect("cherry-pick");
    assert!(picked.success, "{}", picked.stderr);
    assert!(directory.path().join("feature.txt").exists());
    let picked_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    let reverted = revert_commit(path.clone(), picked_oid, None).expect("revert");
    assert!(reverted.success, "{}", reverted.stderr);
    assert!(!directory.path().join("feature.txt").exists());

    let checked_out = checkout_commit(path.clone(), initial_oid).expect("detached checkout");
    assert!(checked_out.success, "{}", checked_out.stderr);
    assert!(open_repository(path).unwrap().head_name.is_none());
}

#[test]
fn exposes_and_aborts_cherry_pick_conflicts() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    git(directory.path(), &["switch", "-c", "feature"]);
    fs::write(directory.path().join("notes.txt"), "feature\n").expect("feature change");
    git(directory.path(), &["commit", "-am", "feature change"]);
    let feature_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    git(directory.path(), &["switch", "main"]);
    fs::write(directory.path().join("notes.txt"), "main\n").expect("main change");
    git(directory.path(), &["commit", "-am", "main change"]);

    assert_eq!(
        assess_cherry_pick(path.clone(), feature_oid.clone(), None)
            .expect("assess conflicting cherry-pick"),
        CherryPickApplicability::Conflicts,
    );
    let result = cherry_pick_commit(path.clone(), feature_oid, None).expect("cherry-pick starts");
    assert!(!result.success);
    assert_eq!(
        open_repository(path.clone()).unwrap().state,
        RepositoryState::CherryPick
    );
    let aborted = control_cherry_pick(path.clone(), SequenceControl::Abort).expect("abort");
    assert!(aborted.success, "{}", aborted.stderr);
    assert_eq!(open_repository(path).unwrap().state, RepositoryState::Clean);
}

#[test]
fn previews_and_validates_resets() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let initial_oid = git_text(directory.path(), &["rev-parse", "HEAD"]);
    fs::write(directory.path().join("notes.txt"), "second\n").expect("second fixture");
    git(directory.path(), &["commit", "-am", "second"]);

    let preview = preview_reset(path.clone(), initial_oid.clone()).expect("preview");
    assert_eq!(preview.current_branch, "main");
    assert_eq!(preview.outgoing_commits.len(), 1);
    let reset = reset_to_commit(
        path.clone(),
        initial_oid.clone(),
        ResetMode::Soft,
        preview.fingerprint,
        None,
    )
    .expect("soft reset");
    assert!(reset.success, "{}", reset.stderr);
    assert_eq!(
        git_text(directory.path(), &["rev-parse", "HEAD"]),
        initial_oid
    );
    assert!(!git_text(directory.path(), &["diff", "--cached", "--name-only"]).is_empty());

    git(directory.path(), &["reset", "--hard", "ORIG_HEAD"]);
    let target = git_text(directory.path(), &["rev-parse", "HEAD^"]);
    let stale = preview_reset(path.clone(), target.clone()).expect("stale preview");
    fs::write(
        directory.path().join("notes.txt"),
        "changed after preview\n",
    )
    .expect("stale change");
    let error = reset_to_commit(path, target, ResetMode::Mixed, stale.fingerprint, None)
        .expect_err("stale preview is rejected");
    assert!(error.contains("changed after the reset preview"));
}

#[test]
fn detects_untracked_paths_that_hard_reset_would_overwrite() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(directory.path().join("collision.txt"), "tracked\n").expect("tracked fixture");
    git(directory.path(), &["add", "collision.txt"]);
    git(directory.path(), &["commit", "-m", "add collision target"]);
    let target = git_text(directory.path(), &["rev-parse", "HEAD"]);
    git(directory.path(), &["rm", "collision.txt"]);
    git(
        directory.path(),
        &["commit", "-m", "remove collision target"],
    );
    fs::write(directory.path().join("collision.txt"), "untracked\n").expect("untracked collision");

    let preview = preview_reset(path, target).expect("hard reset preview");
    assert_eq!(preview.untracked_collisions, vec!["collision.txt"]);
}

#[test]
fn exposes_and_aborts_revert_conflicts() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(directory.path().join("notes.txt"), "first change\n").expect("first change");
    git(directory.path(), &["commit", "-am", "first change"]);
    let first_change = git_text(directory.path(), &["rev-parse", "HEAD"]);
    fs::write(directory.path().join("notes.txt"), "second change\n").expect("second change");
    git(directory.path(), &["commit", "-am", "second change"]);

    let result = revert_commit(path.clone(), first_change, None).expect("revert starts");
    assert!(!result.success);
    assert_eq!(
        open_repository(path.clone()).unwrap().state,
        RepositoryState::Revert
    );
    let aborted = control_revert(path.clone(), SequenceControl::Abort).expect("abort revert");
    assert!(aborted.success, "{}", aborted.stderr);
    assert_eq!(open_repository(path).unwrap().state, RepositoryState::Clean);
}

#[test]
fn cherry_pick_assessment_allows_reapplying_a_reverted_commit() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(directory.path().join("feature.txt"), "feature\n").expect("feature fixture");
    git(directory.path(), &["add", "feature.txt"]);
    git(directory.path(), &["commit", "-m", "add feature"]);
    let feature = git_text(directory.path(), &["rev-parse", "HEAD"]);

    assert_eq!(
        assess_cherry_pick(path.clone(), feature.clone(), None).expect("assess applied commit"),
        CherryPickApplicability::AlreadyApplied,
    );

    git(directory.path(), &["revert", "--no-edit", &feature]);
    assert_eq!(
        assess_cherry_pick(path.clone(), feature.clone(), None).expect("assess reverted commit"),
        CherryPickApplicability::Applicable,
    );

    let picked = cherry_pick_commit(path.clone(), feature.clone(), None).expect("reapply feature");
    assert!(picked.success, "{}", picked.stderr);
    assert_eq!(
        assess_cherry_pick(path, feature, None).expect("assess reapplied commit"),
        CherryPickApplicability::AlreadyApplied,
    );
}

#[test]
fn cursor_history_is_stable_and_rejects_changed_head() {
    let directory = repository();
    for index in 1..=4 {
        fs::write(directory.path().join("notes.txt"), format!("{index}\n"))
            .expect("history fixture");
        git(
            directory.path(),
            &["commit", "-am", &format!("commit {index}")],
        );
    }
    let path = directory.path().to_string_lossy().into_owned();
    let first = list_commits_cursor(path.clone(), None, 2).expect("first cursor page");
    assert_eq!(first.commits.len(), 2);
    assert_eq!(first.total_commits, 3);
    let cursor = first.next_cursor.expect("next cursor");
    let second =
        list_commits_cursor(path.clone(), Some(cursor.clone()), 2).expect("second cursor page");
    assert_eq!(second.commits.len(), 2);
    assert_eq!(second.total_commits, 5);
    assert_ne!(first.commits[0].oid, second.commits[0].oid);

    fs::write(directory.path().join("notes.txt"), "new head\n").expect("new head fixture");
    git(directory.path(), &["commit", "-am", "new head"]);
    let error = list_commits_cursor(path, Some(cursor), 2).expect_err("stale cursor");
    assert!(error.contains("history changed"));
}

#[test]
fn bulk_path_operations_are_literal_and_support_intent_to_add() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    for name in ["file with spaces.txt", "-leading-dash.txt"] {
        fs::write(directory.path().join(name), "content\n").expect("bulk fixture");
    }
    let paths = vec![
        "file with spaces.txt".to_owned(),
        "-leading-dash.txt".to_owned(),
    ];
    let staged = stage_paths(path.clone(), paths.clone()).expect("bulk stage");
    assert!(staged.success, "{}", staged.stderr);
    assert_eq!(
        git_text(directory.path(), &["diff", "--cached", "--name-only"])
            .lines()
            .count(),
        2
    );
    let unstaged = rust_lib_gitfront_preview::api::git::unstage_paths(path.clone(), paths)
        .expect("bulk unstage");
    assert!(unstaged.success, "{}", unstaged.stderr);
    let intent =
        intent_to_add(path, vec!["file with spaces.txt".to_owned()]).expect("intent to add");
    assert!(intent.success, "{}", intent.stderr);
    assert!(git_text(directory.path(), &["diff", "--name-only"]).contains("file with spaces.txt"));
}

#[test]
fn change_pages_transfer_only_the_requested_slice() {
    let directory = repository();
    for index in 0..7 {
        fs::write(
            directory.path().join(format!("change-{index}.txt")),
            format!("{index}\n"),
        )
        .expect("change page fixture");
    }
    let path = directory.path().to_string_lossy().into_owned();
    let opened = refresh_repository_paged(path.clone(), 3).expect("paged snapshot");
    assert!(opened.snapshot.files.is_empty());
    assert_eq!(opened.changes.files.len(), 3);
    assert_eq!(opened.changes.total_files, 7);
    assert_eq!(opened.changes.untracked_count, 7);
    let second = list_changes_cursor(path, opened.changes.next_cursor.expect("change cursor"), 3)
        .expect("second change page");
    assert_eq!(second.files.len(), 3);
    assert_eq!(second.total_files, 7);
}

#[test]
fn stages_only_selected_lines_from_a_hunk() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(directory.path().join("notes.txt"), "ONE\ntwo\nTHREE\n")
        .expect("line selection fixture");
    let diff =
        get_worktree_diff(path.clone(), Some("notes.txt".to_owned()), false).expect("working diff");
    let hunk = &diff.files[0].hunks[0];
    let selected = hunk
        .lines
        .iter()
        .enumerate()
        .filter(|(_, line)| line.content.contains("one") || line.content.contains("ONE"))
        .map(|(index, _)| index as u32)
        .collect();
    let result = apply_hunk_lines(
        path,
        "notes.txt".to_owned(),
        false,
        hunk.index,
        selected,
        diff.fingerprint,
        false,
    )
    .expect("stage selected lines");
    assert!(result.success, "{}", result.stderr);
    let staged = git_text(directory.path(), &["diff", "--cached"]);
    let unstaged = git_text(directory.path(), &["diff"]);
    assert!(staged.contains("+ONE"));
    assert!(!staged.contains("+THREE"));
    assert!(unstaged.contains("+THREE"));
    assert!(!unstaged.contains("+ONE"));

    let staged_diff = get_worktree_diff(
        directory.path().to_string_lossy().into_owned(),
        Some("notes.txt".to_owned()),
        true,
    )
    .expect("staged line diff");
    let staged_hunk = &staged_diff.files[0].hunks[0];
    let staged_lines = staged_hunk
        .lines
        .iter()
        .enumerate()
        .filter(|(_, line)| {
            matches!(
                line.kind,
                rust_lib_gitfront_preview::api::models::DiffLineKind::Addition
                    | rust_lib_gitfront_preview::api::models::DiffLineKind::Deletion
            )
        })
        .map(|(index, _)| index as u32)
        .collect();
    let unstaged_result = apply_hunk_lines(
        directory.path().to_string_lossy().into_owned(),
        "notes.txt".to_owned(),
        true,
        staged_hunk.index,
        staged_lines,
        staged_diff.fingerprint,
        true,
    )
    .expect("unstage selected lines");
    assert!(unstaged_result.success, "{}", unstaged_result.stderr);
    assert!(git_text(directory.path(), &["diff", "--cached"]).is_empty());

    let worktree_diff = get_worktree_diff(
        directory.path().to_string_lossy().into_owned(),
        Some("notes.txt".to_owned()),
        false,
    )
    .expect("discard line diff");
    let worktree_hunk = &worktree_diff.files[0].hunks[0];
    let third_line = worktree_hunk
        .lines
        .iter()
        .enumerate()
        .filter(|(_, line)| line.content.contains("THREE"))
        .map(|(index, _)| index as u32)
        .collect();
    let discarded = apply_hunk_lines(
        directory.path().to_string_lossy().into_owned(),
        "notes.txt".to_owned(),
        false,
        worktree_hunk.index,
        third_line,
        worktree_diff.fingerprint,
        true,
    )
    .expect("discard selected lines");
    assert!(discarded.success, "{}", discarded.stderr);
    let contents = fs::read_to_string(directory.path().join("notes.txt"))
        .expect("read line discard result")
        .replace("\r\n", "\n");
    assert_eq!(contents, "ONE\ntwo\n");
}

#[test]
fn branch_pages_transfer_only_the_requested_slice() {
    let directory = repository();
    create_branch_refs(
        directory.path(),
        (0..7).map(|index| format!("branch-{index}")),
    );
    let path = directory.path().to_string_lossy().into_owned();
    let opened = refresh_repository_paged(path.clone(), 3).expect("paged snapshot");
    assert!(opened.snapshot.branches.is_empty());
    assert_eq!(opened.branches.branches.len(), 8);
    assert_eq!(opened.branches.total_branches, 8);

    // Create enough refs to exercise the fixed 250 item first page.
    create_branch_refs(
        directory.path(),
        (7..260).map(|index| format!("many-{index}")),
    );
    let opened = refresh_repository_paged(path.clone(), 3).expect("large branch snapshot");
    assert_eq!(opened.branches.branches.len(), 250);
    let second = list_branches_cursor(
        path,
        opened.branches.next_cursor.expect("branch cursor"),
        250,
    )
    .expect("second branch page");
    assert_eq!(second.branches.len(), 11);
    assert_eq!(second.total_branches, 261);
}

#[test]
fn lists_pages_and_safely_removes_submodules() {
    let child = repository();
    let parent = repository();
    let child_path = child.path().to_string_lossy().into_owned();
    git(
        parent.path(),
        &[
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            &child_path,
            "vendor/library",
        ],
    );
    git(
        parent.path(),
        &[
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            &child_path,
            "vendor/second",
        ],
    );
    let parent_path = parent.path().to_string_lossy().into_owned();
    let first = list_submodules(parent_path.clone(), true, 1).expect("submodule page");
    assert_eq!(first.total_submodules, 2);
    let second = list_submodules_cursor(
        parent_path.clone(),
        first.next_cursor.expect("submodule cursor"),
        1,
    )
    .expect("second submodule page");
    assert_eq!(second.submodules.len(), 1);
    assert!(second.next_cursor.is_none());
    assert_eq!(first.submodules[0].path, "vendor/library");
    assert_eq!(first.submodules[0].state, SubmoduleState::Clean);

    fs::write(
        parent.path().join("vendor/library/local.txt"),
        "untracked\n",
    )
    .expect("dirty submodule fixture");
    assert!(
        preview_remove_submodule(parent_path.clone(), "vendor/library".to_owned()).is_err(),
        "dirty submodules must not be removed"
    );
    fs::remove_file(parent.path().join("vendor/library/local.txt")).expect("clean fixture");
    let preview = preview_remove_submodule(parent_path.clone(), "vendor/library".to_owned())
        .expect("remove preview");
    let removed = remove_submodule(
        parent_path,
        "vendor/library".to_owned(),
        preview.fingerprint,
        "vendor/library".to_owned(),
    )
    .expect("remove submodule");
    assert!(removed.success, "{}", removed.stderr);
    assert!(!parent.path().join("vendor/library").exists());
}

#[test]
fn stores_subtree_connections_only_in_local_git_config() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    let saved = register_subtree(
        path.clone(),
        SubtreeInfo {
            id: "vendor_docs".to_owned(),
            prefix: "vendor/docs".to_owned(),
            repository: "https://example.invalid/docs.git".to_owned(),
            reference: "main".to_owned(),
            squash: true,
        },
    )
    .expect("register subtree");
    assert!(saved.success, "{}", saved.stderr);
    let entries = list_subtrees(path).expect("list subtrees");
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].prefix, "vendor/docs");
    assert!(entries[0].squash);
    assert!(!directory.path().join(".gitsubtrees").exists());
}

#[test]
fn commit_options_support_template_signoff_author_and_amend() {
    let directory = repository();
    let path = directory.path().to_string_lossy().into_owned();
    fs::write(
        directory.path().join("commit-template.txt"),
        "Template subject\n",
    )
    .expect("template");
    git(
        directory.path(),
        &["config", "commit.template", "commit-template.txt"],
    );
    let defaults = load_commit_defaults(path.clone()).expect("commit defaults");
    assert!(defaults.template.contains("Template subject"));
    assert!(
        defaults
            .previous_message
            .as_deref()
            .is_some_and(|message| message.contains("initial"))
    );

    fs::write(directory.path().join("options.txt"), "options\n").expect("options fixture");
    stage_paths(path.clone(), vec!["options.txt".to_owned()]).expect("stage options");
    let committed = create_commit_with_options(
        path.clone(),
        CommitOptions {
            message: Some("options commit".to_owned()),
            amend: false,
            signoff: true,
            signing: CommitSigningMode::DoNotSign,
            author_name: Some("Another Author".to_owned()),
            author_email: Some("author@example.invalid".to_owned()),
            authored_at: Some("2026-09-12T12:00:00+09:00".to_owned()),
            allow_empty: false,
            fixup_target: None,
            squash_target: None,
        },
    )
    .expect("commit options");
    assert!(committed.success, "{}", committed.stderr);
    assert_eq!(
        git_text(directory.path(), &["show", "-s", "--format=%an <%ae>"]),
        "Another Author <author@example.invalid>"
    );
    assert!(
        git_text(directory.path(), &["show", "-s", "--format=%B"])
            .contains("Signed-off-by: GitFront Test <gitfront@example.invalid>")
    );

    let amended = create_commit_with_options(
        path,
        CommitOptions {
            message: Some("amended options commit".to_owned()),
            amend: true,
            signoff: false,
            signing: CommitSigningMode::DoNotSign,
            author_name: None,
            author_email: None,
            authored_at: None,
            allow_empty: false,
            fixup_target: None,
            squash_target: None,
        },
    )
    .expect("amend");
    assert!(amended.success, "{}", amended.stderr);
    assert_eq!(
        git_text(directory.path(), &["show", "-s", "--format=%s"]),
        "amended options commit"
    );

    let fixup_target = git_text(directory.path(), &["rev-parse", "HEAD"]);
    fs::write(directory.path().join("fixup.txt"), "fixup\n").expect("fixup fixture");
    git(directory.path(), &["add", "fixup.txt"]);
    let fixup = create_commit_with_options(
        directory.path().to_string_lossy().into_owned(),
        CommitOptions {
            message: None,
            amend: false,
            signoff: false,
            signing: CommitSigningMode::DoNotSign,
            author_name: None,
            author_email: None,
            authored_at: None,
            allow_empty: false,
            fixup_target: Some(fixup_target),
            squash_target: None,
        },
    )
    .expect("fixup commit");
    assert!(fixup.success, "{}", fixup.stderr);
    assert!(
        git_text(directory.path(), &["show", "-s", "--format=%s"])
            .starts_with("fixup! amended options commit")
    );
}
