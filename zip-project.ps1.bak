# PowerShell script to zip the project, excluding long-path/large dirs and transient artifacts
# Usage: Run from project root in PowerShell
#   powershell -ExecutionPolicy Bypass -File .\zip-project.ps1 -OutFile inboxiq.zip

param(
  [string]$OutFile = "inboxiq.zip"
)

$ErrorActionPreference = 'Stop'

# Whitelisted top-level paths to include (prevents long build paths entirely)
$includePaths = @(
  'analysis_options.yaml',
  'pubspec.yaml',
  'pubspec.lock',
  'README.md',
  'CONTRIBUTING.md',
  'firebase.json',
  'firebase.json.bak',
  'firebase - Copy.json',
  'GOOGLE_SIGNIN_SETUP.md',
  'GOOGLE_SIGNIN_TROUBLESHOOTING.md',
  'GOOGLE_TOKEN_TROUBLESHOOTING.md',
  'TESTING_GUIDE.md',
  'ML_TAGGING_SYSTEM_DOCUMENTATION.md',
  'DEBUG_SCREEN_RERUN_TAGGING_ENHANCEMENT.md',
  'DEBUG_TAGGING.md',
  'TAG_CORRECTION_JSON_FIX.md',
  'TAGGING_DEBUG_SCREEN_DOCUMENTATION.md',
  'SOCIAL_MEDIA_TAGGING_ENHANCEMENT.md',
  'YAHOO_INTEGRATION_ROADMAP.md',
  'BILLS_TAGGING_FIX.md',
  # Platform projects (include entire trees minus build outputs)
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
  'web',
  'lib',
  'assets',
  'test',
  '.github',
  '.gitignore',
  'functions/src',
  'functions/package.json',
  'functions/tsconfig.json',
  'functions/tsconfig.dev.json'
)

# Resolve project root as a string path
$rootPath = (Get-Location).Path

# Build list of files to include from whitelisted paths only
$files = @()
foreach ($p in $includePaths) {
  $full = Join-Path -Path $rootPath -ChildPath $p
  if (Test-Path $full -PathType Leaf) {
    $files += Get-Item $full
  } elseif (Test-Path $full -PathType Container) {
    # Exclude common build/transient subdirs when walking containers
    $files += Get-ChildItem $full -Recurse -File -Force |
      Where-Object {
        $rel = $_.FullName.Substring($rootPath.Length).TrimStart(@('/','\')) -replace '\\','/'
        -not (
          $rel -like '*/build/*' -or
          $rel -like '*/.dart_tool/*' -or
          $rel -like '*/.gradle/*' -or
          $rel -like '*/Pods/*' -or
          $rel -like '*/Flutter/ephemeral/*' -or
          $rel -like '*/node_modules/*' -or
          $rel -like '*/outputs/*' -or
          $rel -like '*/intermediates/*' -or
          $rel -like '*/.git/*'
        )
      }
  }
}

# Ensure output path is outside excluded dirs
if (Test-Path $OutFile) { Remove-Item $OutFile -Force }

# Create zip using .NET to avoid long path issues (requires longPathsEnabled in registry/Group Policy on older Windows)
# Load both System.IO.Compression (for ZipArchiveMode) and FileSystem (for ZipFile helpers)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Resolve output zip path (support absolute OutFile)
if ([System.IO.Path]::IsPathRooted($OutFile)) {
  $zipPath = $OutFile
} else {
  $zipPath = Join-Path -Path $rootPath -ChildPath $OutFile
}

# Ensure output directory exists
$zipDir = Split-Path -Path $zipPath -Parent
if ($zipDir -and -not (Test-Path $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }

# Create archive
[System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create).Dispose()
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Update)

try {
  foreach ($f in $files) {
      $entryName = $f.FullName.Substring($rootPath.Length).TrimStart(@('/','\')) -replace '\\','/'
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
}
finally {
  $archive.Dispose()
}

Write-Host "Created archive: $zipPath" -ForegroundColor Green
