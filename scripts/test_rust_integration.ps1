$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot '..\rust\Cargo.toml'
$listOutput = & cargo test --locked --manifest-path $manifestPath --test repository_integration -- --list
if ($LASTEXITCODE -ne 0) {
    Write-Host '::error title=Rust integration test discovery failed::Could not list repository integration tests.'
    exit $LASTEXITCODE
}

$testNames = @(
    $listOutput | ForEach-Object {
        if ($_ -match '^(.+): test$') {
            $Matches[1]
        }
    }
)
if ($testNames.Count -eq 0) {
    Write-Host '::error title=Rust integration test discovery failed::No repository integration tests were found.'
    exit 1
}

foreach ($testName in $testNames) {
    Write-Host "Running repository integration test: $testName"
    & cargo test --locked --manifest-path $manifestPath --test repository_integration $testName -- --exact --nocapture
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) {
        Write-Host "::error title=Rust integration test failed::$testName"
        exit $testExitCode
    }
}

Write-Host "All $($testNames.Count) repository integration tests passed in isolated processes."
