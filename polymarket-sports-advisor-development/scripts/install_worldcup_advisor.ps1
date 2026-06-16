# Install World Cup Polymarket Advisor (Windows PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File install_worldcup_advisor.ps1

$ErrorActionPreference = "Stop"

$RepoUrl = if ($env:WCPOLY_REPO_URL) { $env:WCPOLY_REPO_URL } else { "https://github.com/KeaneYan/worldcup-polymarket-advisor.git" }
$InstallDir = if ($env:WCPOLY_INSTALL_DIR) { $env:WCPOLY_INSTALL_DIR } else { "$env:USERPROFILE\worldcup-polymarket-advisor" }
$PythonBin = if ($env:PYTHON) { $env:PYTHON } else { "python" }

# Check prerequisites
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required. Install from https://git-scm.com/"
    exit 1
}

if (-not (Get-Command $PythonBin -ErrorAction SilentlyContinue)) {
    Write-Error "$PythonBin is required. Install from https://python.org/"
    exit 1
}

# Clone or update
if (Test-Path "$InstallDir\.git") {
    Write-Host "Updating $InstallDir"
    git -C "$InstallDir" pull --ff-only
} else {
    if (Test-Path $InstallDir) {
        Write-Error "$InstallDir exists but is not a git checkout"
        exit 1
    }
    git clone $RepoUrl $InstallDir
}

Set-Location $InstallDir

# Create venv and install
& $PythonBin -m venv .venv
& .\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
python -m pytest -q

Write-Host ""
Write-Host "Installed World Cup Polymarket Advisor at: $InstallDir"
Write-Host ""
Write-Host "Try:"
Write-Host "  cd $InstallDir"
Write-Host "  .\.venv\Scripts\Activate.ps1"
Write-Host "  Copy-Item data\schedule.example.json data\schedule.json"
Write-Host "  wc-poly-report --mode scanner --hours 24"
