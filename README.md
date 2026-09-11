# GitFront Preview

GitFront is a Windows-first desktop Git client with a Flutter interface and a Rust Git core. The current name and package identity are preview values and must be replaced before the first public release.

## Included workflows

- Open and clone repositories in persistent application tabs.
- Inspect staged, unstaged, untracked, and conflicted files.
- View unified or side-by-side diffs and stage, unstage, or discard individual files and hunks.
- Commit staged changes while preserving Git hooks and signing configuration.
- Browse a paginated topological commit graph and inspect commit diffs.
- Create, switch, rename, and delete local branches.
- Fetch, pull, push, set an upstream, and push with `--force-with-lease`.
- Merge, rebase, interactive rebase, and manage stashes.
- Resolve text conflicts in a three-way editor or open files with VS Code, the system default app, a configured Git mergetool, or a custom executable.
- Restore recent repositories, open tabs, active tab, panel sizing, theme, language, and external-editor preferences.
- Check and apply VeloPack updates from GitHub Releases in packaged builds.

Remote branch deletion, submodule/worktree management, Git LFS management UI, blame, and forge-specific pull request features are intentionally outside this preview.

## Development prerequisites

- Windows 10 or 11 x64
- Flutter 3.41.2 or newer with Windows desktop support
- Rust 1.92.0 and the `x86_64-pc-windows-msvc` target
- Git for Windows available as `git`
- Windows Developer Mode enabled, which Flutter needs to create plugin symlinks

Initialize generated bindings after changing a public Rust API:

```powershell
flutter_rust_bridge_codegen generate
```

Run checks and start the application:

```powershell
flutter pub get
flutter analyze
flutter test
Push-Location rust
cargo test
Pop-Location
flutter run -d windows
```

## Architecture

- `lib/` contains the Riverpod application state, Korean/English presentation, three-panel workspace, diff viewer, and conflict/rebase dialogs.
- `rust/src/api/` contains typed repository models, libgit2 reads, guarded Git CLI operations, file watching, and VeloPack updates.
- `rust/src/bin/gitfront_sequence_editor.rs` is the packaged helper used by interactive rebase.
- `windows/runner/main.cpp` invokes the VeloPack bootstrap before Flutter creates its window.

The Rust layer uses `git2` for structured local reads. Mutating and network operations invoke the user's system Git without a shell so credential helpers, SSH configuration, hooks, and signing behavior remain compatible with the command-line installation.

## Windows packaging

Install VeloPack's `vpk` tool and run:

```powershell
dotnet tool install --global vpk
./scripts/package_windows.ps1 -Version 0.1.0
```

To enable GitHub Releases update checks in the packaged build, provide the repository URL:

```powershell
./scripts/package_windows.ps1 `
  -Version 0.1.0 `
  -GitHubRepository "https://github.com/owner/repository"
```

The script produces a per-user installer and portable package under `artifacts/releases`. Set `GITFRONT_SIGN_TEMPLATE` to a VeloPack signing command containing `{{file}}` when a code-signing certificate becomes available. Development builds omit the update feed and report updates as disabled.
