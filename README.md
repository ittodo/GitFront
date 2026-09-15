# GitFront Preview

GitFront is a Windows-first desktop Git client with a Flutter interface and a Rust Git core. The current name and package identity are preview values used throughout the `0.0.x` releases and will be reviewed before `0.1.0`.

See the [current feature list](docs/features.md) for the implemented workflows, partial support, performance behavior, and explicit exclusions.

## Included workflows

- Initialize, open, and clone repositories in persistent application tabs, including practical clone and cone-mode sparse checkout options.
- Inspect staged, unstaged, untracked, and conflicted files with 250-item paging and bulk stage/unstage.
- View unified or side-by-side diffs and stage, unstage, or discard individual files and hunks.
- Commit staged changes with drafts, amend/sign-off/signing/author options while preserving Git hooks.
- Browse a cursor-cached topological commit graph, switch between current/ref/all scopes, filter by text or path, and inspect containing branches and commit diffs.
- Create, switch, rename, and delete local branches.
- Manage remotes, fetch, pull, push, select an upstream, and push with `--force-with-lease`.
- Inspect and edit repository or global Git configuration with inherited-value origins and sensitive-value masking.
- Merge, rebase, interactive rebase, and manage stashes.
- Lazily inspect and manage submodules, and run registered subtree add/pull/push/split workflows with squash controls through GitFront's pinned official helper.
- Resolve text conflicts in a three-way editor or open files with VS Code, the system default app, a configured Git mergetool, or a custom executable.
- Restore recent repositories, open tabs, active tab, panel sizing, theme, language, and external-editor preferences.
- Check and apply VeloPack updates from GitHub Releases in packaged builds.

Remote branch deletion, worktree management, Git LFS management UI, blame, and forge-specific pull request features are intentionally outside this preview.

## Development prerequisites

- Windows 10 or 11 x64
- Flutter 3.41.2 or newer with Windows desktop support
- Rust 1.92.0 and the `x86_64-pc-windows-msvc` target
- Git for Windows 2.31 or newer available as `git` (older versions keep basic workflows but disable unsupported setup features)
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

## Settings storage

- Packaged release builds store settings in the system Documents folder at `GitFront\settings.json`.
- Debug and profile builds use `GitFront\develop\settings.json` so development does not change release preferences.
- The first release using this layout migrates the previous `%APPDATA%\dev.gitfront\gitfront_preview\shared_preferences.json` file after the new file has been written and verified.

## Windows packaging

Install VeloPack's `vpk` tool and run:

```powershell
dotnet tool install --global vpk
./scripts/package_windows.ps1 -Version 0.0.3
```

To enable GitHub Releases update checks in the packaged build, provide the repository URL:

```powershell
./scripts/package_windows.ps1 `
  -Version 0.0.3 `
  -GitHubRepository "https://github.com/owner/repository"
```

The script produces a per-user installer and portable package under `artifacts/releases`. Set `GITFRONT_SIGN_TEMPLATE` to a VeloPack signing command containing `{{file}}` when a code-signing certificate becomes available. Development builds omit the update feed and report updates as disabled.

Preview versions advance from `0.0.1` through `0.0.99`, followed by `0.1.0`. Flutter, Rust, VeloPack, and Git tags use the same three-part version without a separate `+build` suffix.
