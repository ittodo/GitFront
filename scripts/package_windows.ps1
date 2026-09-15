param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = "0.0.3",
    [string]$GitHubRepository = "",
    [string]$OutputDirectory = "artifacts\releases"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDirectory = Join-Path $projectRoot "build\windows\x64\runner\Release"
$artifactDirectory = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
}
$helperPath = Join-Path $projectRoot "rust\target\release\gitfront_sequence_editor.exe"
$mainExecutable = Join-Path $releaseDirectory "gitfront_preview.exe"

function Assert-ProjectChildPath {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $projectRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay inside the GitFront project: $fullPath"
    }
    return $fullPath
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [Parameter(Mandatory)] [string]$Label
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

$releaseDirectory = Assert-ProjectChildPath $releaseDirectory "Release directory"
$artifactDirectory = Assert-ProjectChildPath $artifactDirectory "Artifact directory"

$pubspecMatch = Select-String -LiteralPath (Join-Path $projectRoot "pubspec.yaml") `
    -Pattern '^version:\s*(\d+\.\d+\.\d+)\s*$' | Select-Object -First 1
$cargoMatch = Select-String -LiteralPath (Join-Path $projectRoot "rust\Cargo.toml") `
    -Pattern '^version\s*=\s*"(\d+\.\d+\.\d+)"\s*$' | Select-Object -First 1
if (-not $pubspecMatch -or $pubspecMatch.Matches[0].Groups[1].Value -ne $Version) {
    throw "pubspec.yaml version must match release version $Version"
}
if (-not $cargoMatch -or $cargoMatch.Matches[0].Groups[1].Value -ne $Version) {
    throw "rust/Cargo.toml version must match release version $Version"
}

if ($GitHubRepository) {
    $env:GITFRONT_UPDATE_REPOSITORY = $GitHubRepository
} else {
    Remove-Item Env:GITFRONT_UPDATE_REPOSITORY -ErrorAction SilentlyContinue
}

Push-Location $projectRoot
try {
    if (Test-Path -LiteralPath $releaseDirectory) {
        Remove-Item -LiteralPath $releaseDirectory -Recurse -Force
    }

    Invoke-CheckedCommand "flutter" @(
        "build", "windows", "--release", "--build-name", $Version
    ) "Flutter release build"
    if (-not (Test-Path -LiteralPath $mainExecutable -PathType Leaf)) {
        throw "Flutter did not create $mainExecutable"
    }

    Invoke-CheckedCommand "cargo" @(
        "build", "--release", "--locked", "--manifest-path", "rust\Cargo.toml",
        "--bin", "gitfront_sequence_editor"
    ) "Rust rebase helper build"
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw "Cargo did not create $helperPath"
    }
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
    Invoke-CheckedCommand "vpk" $arguments "VeloPack packaging"

    $expectedArtifacts = @(
        (Join-Path $artifactDirectory "dev.gitfront.preview-$Version-full.nupkg"),
        (Join-Path $artifactDirectory "dev.gitfront.preview-win-Portable.zip"),
        (Join-Path $artifactDirectory "dev.gitfront.preview-win-Setup.exe"),
        (Join-Path $artifactDirectory "releases.win.json")
    )
    foreach ($artifact in $expectedArtifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "VeloPack did not create expected artifact: $artifact"
        }
    }
} finally {
    Pop-Location
}

Write-Host "Windows packages: $artifactDirectory"
