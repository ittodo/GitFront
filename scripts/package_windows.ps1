param(
    [string]$Version = "0.1.0",
    [string]$GitHubRepository = "",
    [string]$OutputDirectory = "artifacts\releases"
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$releaseDirectory = Join-Path $projectRoot "build\windows\x64\runner\Release"
$artifactDirectory = Join-Path $projectRoot $OutputDirectory
$helperPath = Join-Path $projectRoot "rust\target\release\gitfront_sequence_editor.exe"

if ($GitHubRepository) {
    $env:GITFRONT_UPDATE_REPOSITORY = $GitHubRepository
} else {
    Remove-Item Env:GITFRONT_UPDATE_REPOSITORY -ErrorAction SilentlyContinue
}

Push-Location $projectRoot
try {
    flutter build windows --release --build-name $Version
    cargo build --release --manifest-path rust\Cargo.toml --bin gitfront_sequence_editor
    Copy-Item -LiteralPath $helperPath -Destination $releaseDirectory -Force

    New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    $arguments = @(
        "pack",
        "--packId", "dev.gitfront.preview",
        "--packVersion", $Version,
        "--packDir", $releaseDirectory,
        "--mainExe", "gitfront_preview.exe",
        "--packTitle", "GitFront Preview",
        "--packAuthors", "GitFront contributors",
        "--icon", "windows\runner\resources\app_icon.ico",
        "--releaseNotes", "release-notes.md",
        "--shortcuts", "StartMenuRoot",
        "--outputDir", $artifactDirectory
    )
    if ($env:GITFRONT_SIGN_TEMPLATE) {
        $arguments += @("--signTemplate", $env:GITFRONT_SIGN_TEMPLATE)
    }
    & vpk @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "VeloPack failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "Windows packages: $artifactDirectory"
