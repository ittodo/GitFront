# git-subtree

GitFront includes a locally patched copy of Git's `git-subtree` helper.

- Upstream: https://github.com/git/git
- Source commit: `2f9980cfebad39326546e4db1f614bdaf783f51b`
- Source path: `contrib/subtree/git-subtree.sh`
- License: GNU General Public License version 2 (`COPYING` in this directory)

The GitFront patch removes the helper's requirement that Git's exec directory
must be the first PATH entry and sources `git-sh-setup` from the explicitly
validated `GIT_EXEC_PATH`. This allows the helper to run reliably from a
desktop application without changing the user's global PATH.
