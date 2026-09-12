#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RepositoryState {
    Clean,
    Merge,
    Rebase,
    RebaseInteractive,
    RebaseMerge,
    CherryPick,
    Revert,
    Bisect,
    ApplyMailbox,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChangeKind {
    None,
    Added,
    Modified,
    Deleted,
    Renamed,
    TypeChanged,
    Untracked,
    Conflicted,
    Unreadable,
}

#[derive(Clone, Debug)]
pub struct FileChange {
    pub path: String,
    pub old_path: Option<String>,
    pub staged: ChangeKind,
    pub unstaged: ChangeKind,
    pub conflicted: bool,
    pub untracked: bool,
}

#[derive(Clone, Debug)]
pub struct BranchInfo {
    pub name: String,
    pub full_name: String,
    pub oid: Option<String>,
    pub is_head: bool,
    pub is_remote: bool,
    pub upstream: Option<String>,
    pub ahead: i64,
    pub behind: i64,
}

#[derive(Clone, Debug)]
pub struct RemoteInfo {
    pub name: String,
    pub fetch_url: Option<String>,
    pub push_url: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GitignoreTemplate {
    None,
    Flutter,
    Rust,
    Node,
    Python,
    VisualStudio,
}

#[derive(Clone, Debug)]
pub struct RepositoryInitOptions {
    pub target_path: String,
    pub initial_branch: String,
    pub create_readme: bool,
    pub gitignore_template: GitignoreTemplate,
    pub origin_url: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RepositoryInitResult {
    pub path: String,
    pub operation: OperationResult,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct CloneOptions {
    pub url: String,
    pub target: String,
    pub remote_name: String,
    pub branch: Option<String>,
    pub depth: Option<u32>,
    pub single_branch: bool,
    pub no_tags: bool,
    pub recurse_submodules: bool,
    pub shallow_submodules: bool,
    pub blobless: bool,
    pub sparse_directories: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct CloneResult {
    pub path: String,
    pub operation: OperationResult,
    pub warnings: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GitConfigScope {
    System,
    Global,
    Local,
    Worktree,
    Command,
    Unknown,
}

#[derive(Clone, Debug)]
pub struct GitConfigEntry {
    pub key: String,
    pub value: String,
    pub scope: GitConfigScope,
    pub origin: String,
    pub inherited: bool,
    pub sensitive: bool,
}

#[derive(Clone, Debug)]
pub struct GitConfigSnapshot {
    pub entries: Vec<GitConfigEntry>,
}

#[derive(Clone, Debug)]
pub struct RemoteDetails {
    pub name: String,
    pub fetch_urls: Vec<String>,
    pub push_urls: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct SparseCheckoutState {
    pub enabled: bool,
    pub cone_mode: bool,
    pub directories: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct GitCapabilities {
    pub version: String,
    pub supports_repository_setup: bool,
    pub supports_fixed_value_config: bool,
    pub supports_sparse_checkout: bool,
}

#[derive(Clone, Debug)]
pub struct StashEntry {
    pub index: u32,
    pub message: String,
    pub oid: String,
}

#[derive(Clone, Debug)]
pub struct RepositorySnapshot {
    pub repository_path: String,
    pub workdir: String,
    pub name: String,
    pub head_name: Option<String>,
    pub head_oid: Option<String>,
    pub upstream: Option<String>,
    pub ahead: i64,
    pub behind: i64,
    pub state: RepositoryState,
    pub generation: u64,
    pub files: Vec<FileChange>,
    pub branches: Vec<BranchInfo>,
    pub remotes: Vec<RemoteInfo>,
    pub stashes: Vec<StashEntry>,
}

#[derive(Clone, Debug)]
pub struct WorkingTreeSnapshot {
    pub generation: u64,
    pub state: RepositoryState,
    pub files: Vec<FileChange>,
}

#[derive(Clone, Debug)]
pub struct FileChangePage {
    pub files: Vec<FileChange>,
    pub next_cursor: Option<String>,
    pub total_files: u32,
    pub staged_count: u32,
    pub unstaged_count: u32,
    pub conflict_count: u32,
    pub untracked_count: u32,
}

#[derive(Clone, Debug)]
pub struct BranchPage {
    pub branches: Vec<BranchInfo>,
    pub next_cursor: Option<String>,
    pub total_branches: u32,
}

#[derive(Clone, Debug)]
pub struct RepositorySnapshotPage {
    pub snapshot: RepositorySnapshot,
    pub changes: FileChangePage,
    pub branches: BranchPage,
}

#[derive(Clone, Debug)]
pub struct WorkingTreeSnapshotPage {
    pub snapshot: WorkingTreeSnapshot,
    pub changes: FileChangePage,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DiffLineKind {
    Context,
    Addition,
    Deletion,
    Header,
}

#[derive(Clone, Debug)]
pub struct DiffLine {
    pub kind: DiffLineKind,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
    pub content: String,
}

#[derive(Clone, Debug)]
pub struct DiffHunk {
    pub index: u32,
    pub header: String,
    pub old_start: u32,
    pub old_lines: u32,
    pub new_start: u32,
    pub new_lines: u32,
    pub lines: Vec<DiffLine>,
}

#[derive(Clone, Debug)]
pub struct DiffFile {
    pub old_path: Option<String>,
    pub new_path: Option<String>,
    pub status: String,
    pub binary: bool,
    pub too_large: bool,
    pub hunks: Vec<DiffHunk>,
}

#[derive(Clone, Debug)]
pub struct DiffDocument {
    pub fingerprint: String,
    pub staged: bool,
    pub files: Vec<DiffFile>,
}

#[derive(Clone, Debug)]
pub struct GraphLane {
    pub column: u32,
    pub parent_columns: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CommitReferenceKind {
    Head,
    LocalBranch,
    RemoteBranch,
    Tag,
}

#[derive(Clone, Debug)]
pub struct CommitReference {
    pub name: String,
    pub full_name: String,
    pub kind: CommitReferenceKind,
}

#[derive(Clone, Debug)]
pub struct CommitSummary {
    pub oid: String,
    pub short_oid: String,
    pub summary: String,
    pub author_name: String,
    pub author_email: String,
    pub authored_at: i64,
    pub parent_oids: Vec<String>,
    pub references: Vec<CommitReference>,
    pub lane: GraphLane,
}

#[derive(Clone, Debug)]
pub struct CommitPage {
    pub commits: Vec<CommitSummary>,
    pub next_offset: Option<u32>,
}

#[derive(Clone, Debug)]
pub struct CommitCursorPage {
    pub commits: Vec<CommitSummary>,
    pub next_cursor: Option<String>,
    pub total_commits: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CherryPickApplicability {
    Applicable,
    AlreadyApplied,
    Conflicts,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CommitSigningMode {
    UseConfig,
    Sign,
    DoNotSign,
}

#[derive(Clone, Debug)]
pub struct CommitOptions {
    pub message: Option<String>,
    pub amend: bool,
    pub signoff: bool,
    pub signing: CommitSigningMode,
    pub author_name: Option<String>,
    pub author_email: Option<String>,
    pub authored_at: Option<String>,
    pub allow_empty: bool,
    pub fixup_target: Option<String>,
    pub squash_target: Option<String>,
}

#[derive(Clone, Debug)]
pub struct CommitDefaults {
    pub template: String,
    pub cleanup: Option<String>,
    pub signing_enabled: bool,
    pub previous_message: Option<String>,
}

#[derive(Clone, Debug)]
pub struct CommitDetail {
    pub oid: String,
    pub message: String,
    pub author_name: String,
    pub author_email: String,
    pub authored_at: i64,
    pub committer_name: String,
    pub committer_email: String,
    pub committed_at: i64,
    pub parent_oids: Vec<String>,
    pub diff: DiffDocument,
}

#[derive(Clone, Debug)]
pub struct ConflictRegion {
    pub index: u32,
    pub base: String,
    pub ours: String,
    pub theirs: String,
}

#[derive(Clone, Debug)]
pub struct ConflictFile {
    pub path: String,
    pub base_label: String,
    pub ours_label: String,
    pub theirs_label: String,
    pub base: String,
    pub ours: String,
    pub theirs: String,
    pub current: String,
    pub regions: Vec<ConflictRegion>,
    pub binary: bool,
    pub too_large: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RebaseAction {
    Pick,
    Reword,
    Squash,
    Fixup,
    Drop,
}

#[derive(Clone, Debug)]
pub struct RebasePlanItem {
    pub action: RebaseAction,
    pub oid: String,
    pub summary: String,
    pub new_message: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RebasePlan {
    pub upstream: String,
    pub onto: Option<String>,
    pub items: Vec<RebasePlanItem>,
    pub contains_merge_commits: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OperationPhase {
    Started,
    Progress,
    Completed,
    Failed,
}

#[derive(Clone, Debug)]
pub struct OperationEvent {
    pub operation: String,
    pub phase: OperationPhase,
    pub message: String,
    pub progress: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct OperationResult {
    pub success: bool,
    pub exit_code: i32,
    pub summary: String,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Clone, Debug)]
pub struct GitError {
    pub code: String,
    pub message: String,
    pub detail: String,
    pub recoverable: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PullMode {
    Configured,
    Merge,
    Rebase,
    FastForwardOnly,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MergeControl {
    Continue,
    Abort,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RebaseControl {
    Continue,
    Skip,
    Abort,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SequenceControl {
    Continue,
    Skip,
    Abort,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ResetMode {
    Soft,
    Mixed,
    Hard,
}

#[derive(Clone, Debug)]
pub struct ResetCommit {
    pub oid: String,
    pub short_oid: String,
    pub summary: String,
}

#[derive(Clone, Debug)]
pub struct ResetPreview {
    pub current_branch: String,
    pub target_oid: String,
    pub outgoing_commits: Vec<ResetCommit>,
    pub tracked_paths: Vec<String>,
    pub untracked_collisions: Vec<String>,
    pub fingerprint: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExternalEditor {
    VsCode,
    SystemDefault,
    GitMergeTool,
    Custom,
}

#[derive(Clone, Debug)]
pub struct RepositoryWatchEvent {
    pub repository_path: String,
    pub paths: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UpdateState {
    Disabled,
    NotInstalled,
    UpToDate,
    Available,
    Downloaded,
}

#[derive(Clone, Debug)]
pub struct UpdateStatus {
    pub state: UpdateState,
    pub current_version: String,
    pub available_version: Option<String>,
    pub release_notes_markdown: Option<String>,
    pub download_size: Option<u64>,
    pub message: String,
}
