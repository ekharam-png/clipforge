# ClipForge update helper for Windows (Windows PowerShell 5.1 or later).
#
# Started by the app, detached, just before it closes. It waits until the
# app has gone, then swaps two folders that sit side by side:
#
#     <InstallDir>             -> <InstallDir>.update-old
#     <NewDir> (the new app)   -> <InstallDir>
#
# and starts the app again. A folder rename either happens completely or
# not at all, so there is never a half-replaced app:
#   - if the old folder cannot be moved (a file in it is still in use),
#     nothing has changed: the old app is started again;
#   - if the new folder cannot be moved in, the old one is moved back and
#     started again.
# The result is written to -ResultFile as one line of JSON
# ({"status":"updated"|"failed"|"broken","message":"...","version":"..."}),
# which the app reads on its next start.
#
# It only ever touches <InstallDir>, <InstallDir>.update-old and <NewDir>,
# and it removes an .update-old folder only when that folder carries the
# updater's marker file (.clipforge-update-marker).
# Projects and media (Documents\ClipForge) are somewhere else and are never
# touched.
#
# Tested by the "Windows app" job of the build workflow with a pretend app
# folder (tool/ci/windows_swap_test.py).

param(
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$NewDir,
  [int]$WaitPid = 0,
  [string]$ExeName = 'clipforge.exe',
  [string]$ResultFile = '',
  [string]$Version = '',
  [int]$WaitSeconds = 60,
  [int]$Retries = 30,
  [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$InstallDir = $InstallDir.TrimEnd('\', '/')
$NewDir = $NewDir.TrimEnd('\', '/')
$OldDir = "$InstallDir.update-old"
# The file that says "the updater made this folder" (the app writes it into
# the unpacked update; see lib/core/update/update_install.dart).
$Marker = '.clipforge-update-marker'

function Write-Marker([string]$Dir) {
  try {
    [System.IO.File]::WriteAllText((Join-Path $Dir $Marker), '{"by":"ClipForge updater"}', (New-Object System.Text.UTF8Encoding($false)))
  } catch { }
}

function Write-Result([string]$Status, [string]$Message) {
  if (-not $ResultFile) { return }
  try {
    $o = [ordered]@{
      status  = $Status
      message = $Message
      version = $Version
      time    = (Get-Date).ToUniversalTime().ToString('o')
    }
    $json = $o | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($ResultFile, $json, (New-Object System.Text.UTF8Encoding($false)))
  } catch { }
}

function Start-App([string]$Dir) {
  if ($NoRestart) { return }
  $exe = Join-Path $Dir $ExeName
  if (Test-Path -LiteralPath $exe -PathType Leaf) {
    try { Start-Process -FilePath $exe -WorkingDirectory $Dir | Out-Null } catch { }
  }
}

function Move-Folder([string]$From, [string]$To, [int]$Tries) {
  for ($i = 0; $i -lt $Tries; $i++) {
    try {
      [System.IO.Directory]::Move($From, $To)
      return $true
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  return $false
}

# 1. Wait until the app has closed (its files are locked while it runs).
if ($WaitPid -gt 0) {
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  while ((Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
    Start-Sleep -Milliseconds 250
  }
}

# 2. Nothing to do without both folders.
if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
  Write-Result 'failed' 'The ClipForge folder was not found.'
  exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $NewDir $ExeName) -PathType Leaf)) {
  Write-Result 'failed' 'The downloaded update is not complete.'
  Start-App $InstallDir
  exit 2
}
if (Test-Path -LiteralPath $OldDir) {
  # Only a folder this updater made (it carries the marker) is removed.
  if (-not (Test-Path -LiteralPath (Join-Path $OldDir $Marker) -PathType Leaf)) {
    Write-Result 'failed' "A folder called '$(Split-Path -Leaf $OldDir)' that ClipForge did not make is in the way. Move or rename it, then try again."
    Start-App $InstallDir
    exit 2
  }
  try {
    Remove-Item -LiteralPath $OldDir -Recurse -Force
  } catch {
    Write-Result 'failed' 'An older copy of ClipForge next to the app could not be removed.'
    Start-App $InstallDir
    exit 2
  }
}

# 3. The old app steps aside. If this fails nothing has changed.
if (-not (Move-Folder $InstallDir $OldDir $Retries)) {
  Write-Result 'failed' 'A file of ClipForge is still in use (is ClipForge or its Claude helper running from this folder?).'
  Start-App $InstallDir
  exit 3
}

# The folder that stepped aside is ours to remove later.
Write-Marker $OldDir

# 4. The new app takes its place; on failure the old one comes back.
if (-not (Move-Folder $NewDir $InstallDir 6)) {
  if (Move-Folder $OldDir $InstallDir 20) {
    Write-Result 'failed' 'The new version could not be put in place; ClipForge is unchanged.'
    Start-App $InstallDir
    exit 4
  }
  # Should not happen (the folder was moved a moment ago): the old app is
  # complete and still works from where it is.
  Write-Result 'broken' "The update could not be finished. ClipForge still works from: $OldDir"
  Start-App $OldDir
  exit 5
}

Write-Result 'updated' ''
Start-App $InstallDir

# 5. Tidy up (the app also removes a leftover on its next start).
for ($i = 0; $i -lt 10; $i++) {
  try {
    Remove-Item -LiteralPath $OldDir -Recurse -Force
    break
  } catch {
    Start-Sleep -Milliseconds 500
  }
}
exit 0
