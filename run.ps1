<#
.SYNOPSIS
Launcher for the Tiny SLM backend + Qt HUD.

.DESCRIPTION
Runs the Python backend WebSocket server (ws://localhost:8765) using your GLOBAL Python.
Optionally launches the GUI if a built JarvisHUD.exe is found (or builds it if requested).

Examples:
  .\run.ps1
  .\run.ps1 -InstallDeps
  .\run.ps1 -BuildGui -GuiConfig Release
  .\run.ps1 -BackendOnly
  .\run.ps1 -ForegroundBackend
#>

[CmdletBinding()]
param(
  [switch]$InstallDeps,
  [switch]$BuildGui,
  [ValidateSet("Release", "Debug")]
  [string]$GuiConfig = "Release",
  [switch]$BackendOnly,
  [switch]$NoGui,
  [switch]$ForegroundBackend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Quote-PSLiteral([string]$s) {
  return "'" + ($s -replace "'", "''") + "'"
}

function Write-Info([string]$msg) { Write-Host "[run] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "[run] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg) { Write-Host "[run] $msg" -ForegroundColor Red }

$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Get-Location).Path
}

$BackendDir = Join-Path $Root "backend"
$GuiDir = Join-Path $Root "gui"
$ServerPy = Join-Path $BackendDir "server.py"
$ReqTxt = Join-Path $BackendDir "requirements.txt"

if (!(Test-Path -LiteralPath $ServerPy)) {
  throw "Missing backend entrypoint: $ServerPy"
}

if ($BackendOnly) { $NoGui = $true }

# Resolve Python (prefer python.exe, fallback to py.exe).
$PythonExe = $null
$PythonPrefix = @()
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $pythonCmd) {
  $PythonExe = $pythonCmd.Source
} else {
  $pyCmd = Get-Command py -ErrorAction SilentlyContinue
  if ($null -ne $pyCmd) {
    $PythonExe = $pyCmd.Source
    $PythonPrefix = @("-3")
  }
}

if ($null -eq $PythonExe) {
  throw "Python not found. Install Python 3.10+ (or ensure 'python' / 'py' is on PATH)."
}

function Invoke-Python([string[]]$Args) {
  & $PythonExe @PythonPrefix @Args
  return $LASTEXITCODE
}

if ((Invoke-Python @("-c", "import sys; raise SystemExit(0) if sys.version_info >= (3,10) else 1")) -ne 0) {
  throw "Python 3.10+ is required."
}

function Test-PythonDeps {
  $code = Invoke-Python @("-c", "import torch, numpy, websockets")
  return ($code -eq 0)
}

function Ensure-PythonDeps {
  if (Test-PythonDeps) { return }

  if (-not $InstallDeps) {
    Write-Err "Missing Python deps (torch/numpy/websockets)."
    Write-Host "Install with:" -ForegroundColor Yellow
    Write-Host "  python -m pip install -r backend\\requirements.txt" -ForegroundColor Yellow
    exit 1
  }

  if (!(Test-Path -LiteralPath $ReqTxt)) {
    throw "Missing requirements file: $ReqTxt"
  }

  Write-Info "Installing Python deps from backend/requirements.txt (global Python)..."
  $code = Invoke-Python @("-m", "pip", "install", "-r", $ReqTxt)
  if ($code -ne 0) { throw "pip install failed (exit code $code)." }
}

Ensure-PythonDeps

function Start-BackendInNewWindow {
  $shellExe = $null
  $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($null -ne $pwshCmd) {
    $shellExe = $pwshCmd.Source
  } else {
    $shellExe = (Get-Command powershell -ErrorAction Stop).Source
  }

  $py = Quote-PSLiteral $PythonExe
  $server = Quote-PSLiteral $ServerPy
  $wd = Quote-PSLiteral $BackendDir

  $prefix = ""
  if ($PythonPrefix.Count -gt 0) {
    $prefix = ($PythonPrefix | ForEach-Object { Quote-PSLiteral $_ }) -join " "
  }

  $cmd = "Set-Location -LiteralPath $wd; & $py $prefix $server"
  Write-Info "Starting backend in a new window..."
  Start-Process -FilePath $shellExe -ArgumentList @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd) | Out-Null
}

function Start-GuiIfPresent {
  param([string]$Config)

  $candidates = @(
    (Join-Path $GuiDir ("build\" + $Config + "\JarvisHUD.exe")),
    (Join-Path $GuiDir "build\JarvisHUD.exe")
  )

  $exe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $exe) {
    $found = Get-ChildItem -Path $GuiDir -Recurse -Filter "JarvisHUD.exe" -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($null -ne $found) { $exe = $found.FullName }
  }

  if ([string]::IsNullOrWhiteSpace($exe) -or !(Test-Path -LiteralPath $exe)) {
    Write-Warn "GUI executable not found. Build it with Qt 6 (see README.md)."
    return
  }

  Write-Info "Launching GUI: $exe"
  Start-Process -FilePath $exe | Out-Null
}

function Build-Gui {
  param([string]$Config)

  $cmake = Get-Command cmake -ErrorAction SilentlyContinue
  if ($null -eq $cmake) {
    Write-Warn "cmake not found; skipping GUI build."
    return
  }

  $buildDir = Join-Path $GuiDir "build"
  Write-Info "Configuring GUI (cmake)..."
  & $cmake.Source -S $GuiDir -B $buildDir
  if ($LASTEXITCODE -ne 0) { throw "CMake configure failed." }

  Write-Info "Building GUI ($Config)..."
  & $cmake.Source --build $buildDir --config $Config
  if ($LASTEXITCODE -ne 0) { throw "CMake build failed." }
}

if ($BuildGui -and -not $NoGui) {
  Build-Gui -Config $GuiConfig
}

Write-Info "Backend WebSocket: ws://localhost:8765"

if ($ForegroundBackend) {
  if (-not $NoGui) {
    Start-GuiIfPresent -Config $GuiConfig
  }
  Write-Info "Starting backend in this window (Ctrl+C to stop)..."
  Push-Location -LiteralPath $BackendDir
  try {
    & $PythonExe @PythonPrefix $ServerPy
  } finally {
    Pop-Location
  }
} else {
  Start-BackendInNewWindow
  Start-Sleep -Milliseconds 350
  if (-not $NoGui) {
    Start-GuiIfPresent -Config $GuiConfig
  }
  Write-Info "Done. Close the backend window to stop the server."
}
