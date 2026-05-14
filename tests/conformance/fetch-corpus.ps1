# Fetch the BurntSushi/toml-test corpora at the pinned tag.
# 1.0.0 corpus -> tests/conformance/corpus/         (flat tests/{valid,invalid} from the tag)
# 1.1.0 corpus -> tests/conformance/corpus-1.1.0/   (filtered via tests/files-toml-1.1.0 manifest)
# Run from the project root: powershell tests/conformance/fetch-corpus.ps1
#
# Upstream layout notes (verified 2026-05-11):
#   toml-test does NOT use spec-versioned directory subtrees. Instead, the tests
#   live in a single flat tree at tests/{valid,invalid}/*.toml and the spec
#   association is declared by manifest files at tests/files-toml-1.0.0 and
#   tests/files-toml-1.1.0 (each is a newline-delimited list of relative paths).
#   This holds across v1.5.0, v1.6.0, v2.0.0, v2.1.0, and v2.2.0.
#
#   Pinning v1.5.0 here preserves the existing corpus/ contents byte-for-byte so
#   the pre-Phase-2 conformance baseline (132 valid_pass / 258 invalid_pass) is
#   unchanged. The 1.1.0 corpus is derived from the v1.5.0 files-toml-1.1.0
#   manifest, which differs from the 1.0.0 manifest by ~15 files (some
#   1.0.0-invalid cases become valid in 1.1.0; new 1.1.0 features add valid
#   tests).

$ErrorActionPreference = "Stop"

$pinnedTag = "v1.5.0"
$tmpClone = Join-Path $PSScriptRoot "_clone_tmp"
$corpus10 = Join-Path $PSScriptRoot "corpus"
$corpus11 = Join-Path $PSScriptRoot "corpus-1.1.0"

# Note: an "access denied" failure here usually means the CommandBox dev server is still running and holding an open handle into the corpus tree. Stop the server before re-running.
# We clear *contents* rather than the directory itself, because Windows sometimes keeps a stale handle on a directory after its CFML reader exits, while still letting the contents be deleted and re-populated.
function Clear-DirContents {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return }
    Get-ChildItem -Path $Path -Force | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force
    }
}

if (Test-Path $tmpClone) { Remove-Item -Path $tmpClone -Recurse -Force }
Clear-DirContents -Path $corpus10
Clear-DirContents -Path $corpus11

Write-Host "Cloning toml-test at $pinnedTag"
git clone --depth 1 --branch $pinnedTag https://github.com/toml-lang/toml-test.git $tmpClone
if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE) for tag $pinnedTag - check network or whether the tag still exists upstream" }

$testsDir = Join-Path $tmpClone "tests"
$validSrc = Join-Path $testsDir "valid"
$invalidSrc = Join-Path $testsDir "invalid"
$manifest10 = Join-Path $testsDir "files-toml-1.0.0"
$manifest11 = Join-Path $testsDir "files-toml-1.1.0"

if (-not (Test-Path $validSrc)) {
    throw "Expected tests/valid/ not found in cloned corpus at tag $pinnedTag"
}
if (-not (Test-Path $invalidSrc)) {
    throw "Expected tests/invalid/ not found in cloned corpus at tag $pinnedTag"
}

# Manifest-driven copy helper. Each manifest is a newline-delimited list of
# relative paths under tests/{valid,invalid}/ (some are .toml, some are .json
# expectations). We copy each listed file to the destination corpus dir,
# preserving the relative subpath.
function Copy-ManifestEntries {
    param(
        [string] $ManifestPath,
        [string] $DestRoot,
        [string] $TestsRoot
    )
    $entries = Get-Content -Path $ManifestPath
    foreach ($entry in $entries) {
        $trimmed = $entry.Trim()
        if ($trimmed.Length -eq 0) { continue }
        $relPath = $trimmed -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $srcFile = Join-Path $TestsRoot $relPath
        if (-not (Test-Path $srcFile)) {
            Write-Host "  skip (missing source): $trimmed"
            continue
        }
        $dstFile = Join-Path $DestRoot $relPath
        $dstDir = Split-Path -Parent $dstFile
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -Path $srcFile -Destination $dstFile -Force
    }
}

# 1.0.0 corpus: filtered via tests/files-toml-1.0.0 so 1.1.0-only tests do not
# pollute the 1.0.0 runner output.
if (-not (Test-Path $manifest10)) {
    throw "1.0.0 manifest not present at $manifest10 in tag $pinnedTag"
}
if (-not (Test-Path $corpus10)) { New-Item -ItemType Directory -Path $corpus10 | Out-Null }
if (-not (Test-Path (Join-Path $corpus10 "valid")))   { New-Item -ItemType Directory -Path (Join-Path $corpus10 "valid")   | Out-Null }
if (-not (Test-Path (Join-Path $corpus10 "invalid"))) { New-Item -ItemType Directory -Path (Join-Path $corpus10 "invalid") | Out-Null }
Copy-ManifestEntries -ManifestPath $manifest10 -DestRoot $corpus10 -TestsRoot $testsDir

# 1.1.0 corpus: filtered via tests/files-toml-1.1.0.
if (-not (Test-Path $manifest11)) {
    Write-Host "WARNING: 1.1.0 manifest not present at $manifest11; skipping 1.1.0 corpus."
} else {
    if (-not (Test-Path $corpus11)) { New-Item -ItemType Directory -Path $corpus11 | Out-Null }
    if (-not (Test-Path (Join-Path $corpus11 "valid")))   { New-Item -ItemType Directory -Path (Join-Path $corpus11 "valid")   | Out-Null }
    if (-not (Test-Path (Join-Path $corpus11 "invalid"))) { New-Item -ItemType Directory -Path (Join-Path $corpus11 "invalid") | Out-Null }
    Copy-ManifestEntries -ManifestPath $manifest11 -DestRoot $corpus11 -TestsRoot $testsDir
}

Remove-Item -Path $tmpClone -Recurse -Force

$valid10 = (Get-ChildItem -Path (Join-Path $corpus10 "valid")   -Filter "*.toml" -Recurse).Count
$invalid10 = (Get-ChildItem -Path (Join-Path $corpus10 "invalid") -Filter "*.toml" -Recurse).Count
Write-Host "1.0.0 corpus: $valid10 valid, $invalid10 invalid"
if (Test-Path $corpus11) {
    $valid11 = (Get-ChildItem -Path (Join-Path $corpus11 "valid")   -Filter "*.toml" -Recurse).Count
    $invalid11 = (Get-ChildItem -Path (Join-Path $corpus11 "invalid") -Filter "*.toml" -Recurse).Count
    Write-Host "1.1.0 corpus: $valid11 valid, $invalid11 invalid"
}
