# ClipForge update helper for Windows (Windows PowerShell 5.1 or later).
#
# Started by the app, outside its process tree, just before it closes. It
# waits until the app has gone and then replaces the CONTENTS of the app
# folder (1.14.1; before that it renamed the folder, which fails whenever
# anything holds the folder itself: an Explorer window, a terminal, a
# scanner - and that is what happened on real PCs):
#
#   1. a safety copy:  <InstallDir>  ->  <InstallDir>.update-old   (robocopy /MIR)
#   2. the new files:  <NewDir>      ->  <InstallDir>              (robocopy /MIR)
#   3. a check (the program and data\clipforge-version.json are the new ones)
#   4. on failure the safety copy is mirrored back
#   5. the app is started; <NewDir> and the safety copy are removed.
#
# Nothing is renamed, so a window or a terminal that is open IN the folder
# does not matter. Before step 1 every file in the folder is tried for
# writing: a file that another program holds is named in the result and
# nothing is changed at all.
#
# Every step is written to -LogFile (update-log.txt, shared with the app),
# and the outcome to -ResultFile as one line of JSON
# ({"status":"updated"|"failed"|"broken","message":"...","version":"..."}),
# which the app reads on its next start.
#
# Values come as parameters or, when a parameter is not given, from the
# environment (CF_UPD_INSTALL, CF_UPD_NEW, CF_UPD_PID, CF_UPD_EXE,
# CF_UPD_RESULT, CF_UPD_LOG, CF_UPD_VERSION, CF_UPD_TOKEN, CF_UPD_MODE,
# CF_UPD_REMOVE_LIST): the app uses the environment, so no path is ever
# quoted on a command line.
#
# -Mode move ("tidy up"): <NewDir> is the folder the app runs from and
# <InstallDir> the folder it should live in (it may not exist yet). On
# failure the app is started again from <NewDir>. -RemoveListFile names
# older ClipForge folders (one path per line) that are removed after a
# successful move - only folders next to <InstallDir> that hold the program.
#
# It only ever touches <InstallDir>, <InstallDir>.update-old, <NewDir> and
# the folders of the remove list. <NewDir> (in an update) and an
# .update-old folder are removed only when they carry the updater's marker
# file (.clipforge-update-marker). Projects and media (Documents\ClipForge) are
# somewhere else and are never touched.
#
# Exit codes: 0 done, 2 nothing to do / refused, 3 a file is in use or no
# safety copy (nothing changed), 4 put back, 5 broken, 6 the app did not
# close, 7 another script does this update, 9 unexpected error. The same in clipforge-update.cmd, the plain
# cmd / robocopy version that the app uses when PowerShell does not start.
#
# Tested by the "Windows app" job of the build workflow with a pretend app
# folder (tool/ci/windows_swap_test.py).

param(
  [string]$InstallDir = '',
  [string]$NewDir = '',
  [int]$WaitPid = -1,
  [string]$ExeName = '',
  [string]$ResultFile = '',
  [string]$LogFile = '',
  [string]$Version = '',
  [string]$Token = '',
  [string]$Mode = '',
  [string]$RemoveListFile = '',
  [int]$WaitSeconds = 60,
  [int]$Retries = 30,
  [switch]$NoRestart,
  [switch]$SkipLockCheck
)

$ErrorActionPreference = 'Stop'

function From-Env([string]$Value, [string]$Name) {
  if ($Value) { return $Value }
  $e = [Environment]::GetEnvironmentVariable($Name)
  if ($e) { return $e }
  return ''
}

$InstallDir = From-Env $InstallDir 'CF_UPD_INSTALL'
$NewDir = From-Env $NewDir 'CF_UPD_NEW'
$ExeName = From-Env $ExeName 'CF_UPD_EXE'
$ResultFile = From-Env $ResultFile 'CF_UPD_RESULT'
$LogFile = From-Env $LogFile 'CF_UPD_LOG'
$Version = From-Env $Version 'CF_UPD_VERSION'
$Token = From-Env $Token 'CF_UPD_TOKEN'
$Mode = From-Env $Mode 'CF_UPD_MODE'
$RemoveListFile = From-Env $RemoveListFile 'CF_UPD_REMOVE_LIST'
if ($WaitPid -lt 0) {
  $WaitPid = 0
  $e = [Environment]::GetEnvironmentVariable('CF_UPD_PID')
  if ($e -match '^\d+$') { $WaitPid = [int]$e }
}
if (-not $ExeName) { $ExeName = 'clipforge.exe' }
if ($Mode -ne 'move') { $Mode = 'update' }

$InstallDir = $InstallDir.TrimEnd('\', '/')
$NewDir = $NewDir.TrimEnd('\', '/')
$OldDir = "$InstallDir.update-old"
# Where the app is started again when nothing could be done.
$BackDir = $InstallDir
if ($Mode -eq 'move') { $BackDir = $NewDir }
# The file that says "the updater made this folder" (the app writes it into
# the unpacked update; see lib/core/update/update_install.dart).
$Marker = '.clipforge-update-marker'
$VersionFile = 'data\clipforge-version.json'
$Robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Log([string]$Text) {
  if (-not $LogFile) { return }
  try {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' script(ps): ' + $Text + "`r`n"
    [System.IO.File]::AppendAllText($LogFile, $line, $Utf8)
  } catch { }
}

function Write-Marker([string]$Dir) {
  try {
    [System.IO.File]::WriteAllText((Join-Path $Dir $Marker), '{"by":"ClipForge updater"}', $Utf8)
  } catch { }
}

function Write-Result([string]$Status, [string]$Message) {
  Log "result: $Status $Message"
  if (-not $ResultFile) { return }
  try {
    $o = [ordered]@{
      status  = $Status
      message = $Message
      version = $Version
      mode    = $Mode
      time    = (Get-Date).ToUniversalTime().ToString('o')
    }
    $json = $o | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($ResultFile, $json, $Utf8)
  } catch {
    Log "the result file could not be written: $($_.Exception.Message)"
  }
}

function Start-App([string]$Dir) {
  if ($NoRestart) { return }
  $exe = Join-Path $Dir $ExeName
  if (Test-Path -LiteralPath $exe -PathType Leaf) {
    # The app does not inherit this run's values.
    try { Get-ChildItem Env:CF_UPD_* | Remove-Item -ErrorAction SilentlyContinue } catch { }
    try {
      Start-Process -FilePath $exe -WorkingDirectory $Dir | Out-Null
      Log "started the app: $exe"
    } catch {
      Log "the app could not be started ($exe): $($_.Exception.Message)"
    }
  } else {
    Log "no app to start in: $Dir"
  }
}

# robocopy /MIR; returns its exit code (below 8: fine).
function Mirror([string]$From, [string]$To, [string]$What, [switch]$All) {
  # /XF: files that are neither copied nor removed - the marker, and the
  # uninstaller the Windows installer puts into the folder (the update
  # does not have it, and a mirror would otherwise delete it).
  $opts = @('/MIR', '/R:2', '/W:1', '/XF', $Marker, 'unins*.exe', 'unins*.dat', 'unins*.msg',
    '/NP', '/NFL', '/NDL', '/NJH', '/NJS')
  # /IS /IT: also files that look the same (size and time) are copied.
  if ($All) { $opts += @('/IS', '/IT') }
  $out = @()
  $code = 16
  try {
    $out = @(& $Robocopy $From $To $opts)
    $code = $LASTEXITCODE
  } catch {
    Log "robocopy ($What) could not be run: $($_.Exception.Message)"
  }
  Log "robocopy ($What) exit code $code"
  $script:RobocopyNote = ''
  if ($code -ge 8) {
    $n = 0
    foreach ($l in $out) {
      $t = "$l".Trim()
      if (-not $t) { continue }
      if ($n -lt 20) { Log "  robocopy: $t" }
      if (-not $script:RobocopyNote -and $t -match 'ERROR') { $script:RobocopyNote = $t }
      $n++
    }
  }
  return $code
}

# The first file under $Dir that another program holds so that it cannot
# be written; $null when there is none.
function Find-LockedFile([string]$Dir) {
  $files = @()
  try {
    $files = [System.IO.Directory]::GetFiles($Dir, '*', [System.IO.SearchOption]::AllDirectories)
  } catch {
    return $null
  }
  foreach ($f in $files) {
    try {
      $s = [System.IO.File]::Open($f, 'Open', 'ReadWrite', 'ReadWrite')
      $s.Close()
    } catch {
      $e = $_.Exception.GetBaseException()
      if ($e -is [System.IO.FileNotFoundException]) { continue }
      if ($e -is [System.IO.DirectoryNotFoundException]) { continue }
      # A read-only file, or no permission: robocopy deals with it or says so.
      if ($e -is [System.UnauthorizedAccessException]) { continue }
      if ($e -is [System.IO.IOException]) { return $f }
    }
  }
  return $null
}

function Remove-Folder([string]$Dir, [string]$What) {
  if (-not (Test-Path -LiteralPath $Dir)) { return $true }
  for ($i = 0; $i -lt 10; $i++) {
    try {
      Remove-Item -LiteralPath $Dir -Recurse -Force
      Log "removed ${What}: $Dir"
      return $true
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  Log "could not remove $What (left where it is): $Dir"
  return $false
}

function Same-File([string]$A, [string]$B) {
  try {
    $x = [System.IO.File]::ReadAllBytes($A)
    $y = [System.IO.File]::ReadAllBytes($B)
    if ($x.Length -ne $y.Length) { return $false }
    for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    return $true
  } catch {
    return $false
  }
}

# Null when <InstallDir> now holds the new version, else what is wrong.
function Check-Installed {
  $exe = Join-Path $InstallDir $ExeName
  $newExe = Join-Path $NewDir $ExeName
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return "$ExeName is missing after the copy" }
  try {
    if ((Get-Item -LiteralPath $exe).Length -ne (Get-Item -LiteralPath $newExe).Length) {
      return "$ExeName is not the new one after the copy"
    }
  } catch {
    return "$ExeName could not be looked at after the copy"
  }
  $want = Join-Path $NewDir $VersionFile
  if (Test-Path -LiteralPath $want -PathType Leaf) {
    if (-not (Same-File $want (Join-Path $InstallDir $VersionFile))) {
      return 'the version file is not the new one after the copy'
    }
    Log 'check: the program and the version file are the new ones'
  } else {
    Log 'check: the program is the new one (the update has no version file)'
  }
  return $null
}

function Run-Update {
  # The app waits for this line before it closes.
  Log "started token=$Token pid=$PID mode=$Mode"
  $policy = ''
  try { $policy = "$(Get-ExecutionPolicy)" } catch { }
  Log "args: install=[$InstallDir] new=[$NewDir] waitPid=$WaitPid exe=$ExeName version=$Version result=[$ResultFile] retries=$Retries policy=$policy"

  # Only one script does an update: when the app started a second one
  # because the first was slow to report in, the later one stops here.
  if ($ResultFile -and $Token) {
    try {
      New-Item -ItemType Directory -Path "$ResultFile.$Token.lock" | Out-Null
    } catch {
      Log 'another script is already doing this update: stopping'
      return 7
    }
  }

  # 1. Wait until the app has closed (its files are locked while it runs).
  if ($WaitPid -gt 0) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
      Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) {
      # The app is still there: it is not replaced under its feet and not
      # started a second time.
      Write-Result 'failed' 'ClipForge did not close, so nothing was changed.'
      return 6
    }
    Log "the app (pid $WaitPid) has closed"
  }

  # 2. Nothing to do without both folders.
  if (-not $InstallDir -or -not $NewDir -or $InstallDir.Length -le 3 -or
      ($InstallDir -ieq $NewDir)) {
    Write-Result 'failed' 'The update was started without its folders.'
    return 2
  }
  if (-not (Test-Path -LiteralPath (Join-Path $NewDir $ExeName) -PathType Leaf)) {
    Write-Result 'failed' 'The downloaded update is not complete.'
    Start-App $BackDir
    return 2
  }
  $created = $false
  if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
    if ($Mode -ne 'move' -or (Test-Path -LiteralPath $InstallDir)) {
      Write-Result 'failed' 'The ClipForge folder was not found.'
      if ($Mode -eq 'move') { Start-App $BackDir }
      return 2
    }
    $created = $true
  } elseif ($Mode -eq 'move' -and -not (Test-Path -LiteralPath (Join-Path $InstallDir $ExeName) -PathType Leaf)) {
    # Only an older ClipForge is ever replaced by a move.
    Write-Result 'failed' "The folder '$(Split-Path -Leaf $InstallDir)' exists and is not a ClipForge folder. Nothing was changed."
    Start-App $BackDir
    return 2
  }
  if (Test-Path -LiteralPath $OldDir) {
    # Only a folder this updater made (it carries the marker) is removed.
    if (-not (Test-Path -LiteralPath (Join-Path $OldDir $Marker) -PathType Leaf)) {
      Write-Result 'failed' "A folder called '$(Split-Path -Leaf $OldDir)' that ClipForge did not make is in the way. Move or rename it, then try again."
      Start-App $BackDir
      return 2
    }
    if (-not (Remove-Folder $OldDir 'an older safety copy')) {
      Write-Result 'failed' 'An older copy of ClipForge next to the app could not be removed.'
      Start-App $BackDir
      return 2
    }
  }

  if (-not $created) {
    # 3. Is a file of the app still held by a program? Nothing has changed
    #    yet, and nothing will while one is.
    if (-not $SkipLockCheck) {
      $locked = $null
      for ($i = 0; $i -lt $Retries; $i++) {
        $locked = Find-LockedFile $InstallDir
        if (-not $locked) { break }
        if ($i -eq 0) { Log "in use, waiting: $locked" }
        Start-Sleep -Milliseconds 1000
      }
      if ($locked) {
        $name = $locked.Substring($InstallDir.Length).TrimStart('\')
        Log "still in use: $locked"
        Write-Result 'failed' "The file '$name' in the ClipForge folder is in use by another program (is ClipForge, or a program started from this folder, still running?). Nothing was changed."
        Start-App $BackDir
        return 3
      }
      Log 'no file of the app is in use'
    }

    # 4. The safety copy. The marker goes in first: the folder is ours.
    try {
      New-Item -ItemType Directory -Force -Path $OldDir | Out-Null
    } catch {
      Log "the safety copy folder could not be made: $($_.Exception.Message)"
    }
    Write-Marker $OldDir
    $code = Mirror $InstallDir $OldDir 'safety copy'
    Write-Marker $OldDir
    if ($code -ge 8) {
      Remove-Folder $OldDir 'the unfinished safety copy' | Out-Null
      Write-Result 'failed' 'A safety copy of the current version could not be made (is the disk full?). Nothing was changed.'
      Start-App $BackDir
      return 3
    }
  }

  # 5. The new files go in; a file that is busy for a moment is tried again.
  $problem = $null
  $code = 16
  for ($i = 0; $i -lt 6; $i++) {
    $code = Mirror $NewDir $InstallDir 'new version' -All
    if ($code -lt 8) { break }
    Start-Sleep -Milliseconds 2000
  }
  if ($code -ge 8) {
    $problem = "robocopy ended with $code"
    $busy = Find-LockedFile $InstallDir
    if ($busy) {
      $problem = "the file '$($busy.Substring($InstallDir.Length).TrimStart('\'))' is in use by another program"
    } elseif ($script:RobocopyNote) {
      $problem = $script:RobocopyNote
    }
  } else {
    # 6. The check.
    $problem = Check-Installed
  }

  if ($problem) {
    Log "the new version is not in place: $problem"
    # 7. Back to how it was.
    if ($created) {
      Remove-Folder $InstallDir 'the unfinished new folder' | Out-Null
      Write-Result 'failed' "ClipForge could not be moved ($problem). It still runs from where it was."
      Start-App $BackDir
      return 4
    }
    $back = 16
    for ($i = 0; $i -lt 3; $i++) {
      $back = Mirror $OldDir $InstallDir 'putting the old version back'
      if ($back -lt 8) { break }
      Start-Sleep -Milliseconds 2000
    }
    if ($back -lt 8) {
      Remove-Folder $OldDir 'the safety copy' | Out-Null
      Write-Result 'failed' "The new version could not be put in place ($problem); ClipForge is unchanged."
      Start-App $BackDir
      return 4
    }
    # The safety copy is complete and works from where it is.
    if ($Mode -eq 'move') {
      Write-Result 'broken' "The move could not be finished ($problem). ClipForge still works from: $NewDir"
      Start-App $NewDir
    } else {
      Write-Result 'broken' "The update could not be finished ($problem). ClipForge still works from: $OldDir"
      Start-App $OldDir
    }
    return 5
  }

  Write-Result 'updated' ''
  Start-App $InstallDir

  # 8. Tidy up (the app also removes a leftover on its next start).
  # (move: <NewDir> is the folder the app itself asked to be moved out of)
  if ($Mode -eq 'move' -or (Test-Path -LiteralPath (Join-Path $NewDir $Marker) -PathType Leaf)) {
    Remove-Folder $NewDir 'the unpacked update' | Out-Null
  } else {
    Log "left alone (no marker): $NewDir"
  }
  if (-not $created) { Remove-Folder $OldDir 'the safety copy' | Out-Null }

  # Older ClipForge folders named by the app (move only): next to the new
  # place, holding the program, nothing else.
  if ($Mode -eq 'move' -and $RemoveListFile -and (Test-Path -LiteralPath $RemoveListFile -PathType Leaf)) {
    $parent = [System.IO.Path]::GetDirectoryName($InstallDir)
    foreach ($line in [System.IO.File]::ReadAllLines($RemoveListFile, $Utf8)) {
      $dir = $line.Trim().TrimEnd('\', '/')
      if (-not $dir) { continue }
      $ok = ($dir -ine $InstallDir) -and ($dir -ine $NewDir) -and
        ([System.IO.Path]::GetDirectoryName($dir) -ieq $parent) -and
        (Test-Path -LiteralPath (Join-Path $dir $ExeName) -PathType Leaf)
      if ($ok) {
        Remove-Folder $dir 'an older ClipForge folder' | Out-Null
      } else {
        Log "not removed (not an older ClipForge folder next to the app): $dir"
      }
    }
    try { Remove-Item -LiteralPath $RemoveListFile -Force } catch { }
  }
  Log 'done'
  return 0
}

$code = 9
try {
  # (the last value: nothing else a step may have written counts)
  $code = @(Run-Update)[-1]
} catch {
  Log "unexpected error: $($_.Exception.Message)"
  Write-Result 'failed' "The update stopped with an error ($($_.Exception.Message))."
  $code = 9
}
exit $code
