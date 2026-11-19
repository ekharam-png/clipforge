@echo off
rem ClipForge update helper for Windows, plain cmd and robocopy (1.14.1).
rem
rem The app uses this when PowerShell could not be started (it is blocked
rem on some PCs). It does the same steps as clipforge-update.ps1 - read
rem that file's header - with less detail in its messages:
rem
rem   wait for the app to close; check the program file is free;
rem   safety copy   INSTALL to INSTALL.update-old   (robocopy /MIR)
rem   new files     NEW to INSTALL                   (robocopy /MIR)
rem   check; on failure mirror the safety copy back;
rem   start the app; remove NEW and the safety copy (marker rule).
rem
rem (A value that is set but empty counts as not given.)
rem All values come from the environment, so no path is quoted on a
rem command line: CF_UPD_INSTALL, CF_UPD_NEW, CF_UPD_PID, CF_UPD_EXE,
rem CF_UPD_RESULT, CF_UPD_LOG, CF_UPD_VERSION, CF_UPD_TOKEN, CF_UPD_MODE
rem (update / move), CF_UPD_REMOVE_LIST, and for tests CF_UPD_NORESTART,
rem CF_UPD_WAIT (seconds), CF_UPD_RETRIES.
rem
rem Exit codes as in the PowerShell script: 0, 2, 3, 4, 5, 6, 7.
rem Written without delayed expansion and without ( ) blocks, so that a
rem path with ! or ) in it is safe. Plain ASCII; the app writes it with
rem CRLF line ends. Tested by tool/ci/windows_swap_test.py.
setlocal DisableDelayedExpansion
chcp 65001 >nul 2>&1

if "%CF_UPD_EXE%"=="" set "CF_UPD_EXE=clipforge.exe"
if "%CF_UPD_WAIT%"=="" set "CF_UPD_WAIT=60"
if "%CF_UPD_RETRIES%"=="" set "CF_UPD_RETRIES=30"
if "%CF_UPD_LOG%"=="" set "CF_UPD_LOG=nul"
if "%CF_UPD_RESULT%"=="" set "CF_UPD_RESULT=nul"
if /i not "%CF_UPD_MODE%"=="move" set "CF_UPD_MODE=update"
set "MARK=.clipforge-update-marker"
set "VERFILE=data\clipforge-version.json"
set "ROBO=%SystemRoot%\System32\robocopy.exe"
rem /XF: neither copied nor removed - the marker, and the uninstaller that
rem the Windows installer puts into the folder.
set "ROPT=/MIR /R:2 /W:1 /XF %MARK% unins*.exe unins*.dat unins*.msg /NP /NFL /NDL /NJH /NJS"
set "OLD=%CF_UPD_INSTALL%.update-old"
set "BACK=%CF_UPD_INSTALL%"
if /i "%CF_UPD_MODE%"=="move" set "BACK=%CF_UPD_NEW%"
set "CREATED=0"

rem The app waits for this line before it closes.
set "MSG=started token=%CF_UPD_TOKEN% mode=%CF_UPD_MODE%"
call :log
set "MSG=args: install=[%CF_UPD_INSTALL%] new=[%CF_UPD_NEW%] waitPid=%CF_UPD_PID% exe=%CF_UPD_EXE% version=%CF_UPD_VERSION%"
call :log

rem Only one script does an update: when the app started a second one
rem because the first was slow to report in, the later one stops here.
if "%CF_UPD_TOKEN%"=="" goto nolock
if "%CF_UPD_RESULT%"=="nul" goto nolock
md "%CF_UPD_RESULT%.%CF_UPD_TOKEN%.lock" 2>nul || goto second
:nolock

rem 1. Wait until the app has closed.
set /a N=0
:waitpid
if "%CF_UPD_PID%"=="" goto waited
if "%CF_UPD_PID%"=="0" goto waited
tasklist /FI "PID eq %CF_UPD_PID%" /NH 2>nul | find " %CF_UPD_PID% " >nul
if errorlevel 1 goto closed
set /a N+=1
if %N% GEQ %CF_UPD_WAIT% goto stillrunning
ping -n 2 127.0.0.1 >nul
goto waitpid
:closed
set "MSG=the app (pid %CF_UPD_PID%) has closed"
call :log
:waited

rem 2. Nothing to do without both folders.
if "%CF_UPD_INSTALL%"=="" goto nofolders
if "%CF_UPD_NEW%"=="" goto nofolders
if "%CF_UPD_INSTALL:~3%"=="" goto nofolders
if /i "%CF_UPD_INSTALL%"=="%CF_UPD_NEW%" goto nofolders
if not exist "%CF_UPD_NEW%\%CF_UPD_EXE%" goto incomplete
if exist "%CF_UPD_INSTALL%\" goto haveinstall
if /i not "%CF_UPD_MODE%"=="move" goto noinstall
if exist "%CF_UPD_INSTALL%" goto noinstall
set "CREATED=1"
goto copynew

:haveinstall
if /i "%CF_UPD_MODE%"=="move" if not exist "%CF_UPD_INSTALL%\%CF_UPD_EXE%" goto notclipforge
if not exist "%OLD%" goto lockcheck
rem Only a folder this updater made (it carries the marker) is removed.
if not exist "%OLD%\%MARK%" goto foreignold
rd /s /q "%OLD%" >nul 2>&1
if exist "%OLD%" goto oldstuck

rem 3. Is the program file still held? Nothing has changed yet.
:lockcheck
set /a N=0
:lockloop
if not exist "%CF_UPD_INSTALL%\%CF_UPD_EXE%" goto backup
2>nul (>>"%CF_UPD_INSTALL%\%CF_UPD_EXE%" (call )) && goto backup
set /a N+=1
if %N% GEQ %CF_UPD_RETRIES% goto inuse
ping -n 2 127.0.0.1 >nul
goto lockloop

rem 4. The safety copy. The marker goes in first: the folder is ours.
:backup
set "MSG=the program file is not in use"
call :log
md "%OLD%" >nul 2>&1
>"%OLD%\%MARK%" echo {"by":"ClipForge updater"}
"%ROBO%" "%CF_UPD_INSTALL%" "%OLD%" %ROPT% >>"%CF_UPD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
>"%OLD%\%MARK%" echo {"by":"ClipForge updater"}
set "MSG=robocopy (safety copy) exit code %RC%"
call :log
if %RC% GEQ 8 goto nobackup

rem 5. The new files go in; a busy file is tried again.
:copynew
set /a N=0
:copyloop
"%ROBO%" "%CF_UPD_NEW%" "%CF_UPD_INSTALL%" %ROPT% /IS /IT >>"%CF_UPD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
set "MSG=robocopy (new version) exit code %RC%"
call :log
if %RC% LSS 8 goto verify
set /a N+=1
if %N% GEQ 6 goto putback
ping -n 3 127.0.0.1 >nul
goto copyloop

rem 6. The check.
:verify
if not exist "%CF_UPD_INSTALL%\%CF_UPD_EXE%" goto putback
if not exist "%CF_UPD_NEW%\%VERFILE%" goto done
fc /b "%CF_UPD_NEW%\%VERFILE%" "%CF_UPD_INSTALL%\%VERFILE%" >nul 2>&1
if errorlevel 1 goto putback
set "MSG=check: the version file is the new one"
call :log
goto done

rem 7. Back to how it was.
:putback
set "MSG=the new version is not in place; putting things back"
call :log
if "%CREATED%"=="1" goto dropcreated
set /a N=0
:backloop
"%ROBO%" "%OLD%" "%CF_UPD_INSTALL%" %ROPT% >>"%CF_UPD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
set "MSG=robocopy (putting the old version back) exit code %RC%"
call :log
if %RC% LSS 8 goto restored
set /a N+=1
if %N% GEQ 3 goto broken
ping -n 3 127.0.0.1 >nul
goto backloop

:restored
rd /s /q "%OLD%" >nul 2>&1
call :result failed "The new version could not be put in place (a file may be in use; update-log.txt has the details). ClipForge is unchanged."
set "DIR=%BACK%"
call :startapp
exit 4

:dropcreated
rd /s /q "%CF_UPD_INSTALL%" >nul 2>&1
call :result failed "ClipForge could not be moved. It still runs from where it was."
set "DIR=%BACK%"
call :startapp
exit 4

:broken
set "OLDJ=%OLD:\=\\%"
set "NEWJ=%CF_UPD_NEW:\=\\%"
set "MSG=result: broken"
call :log
if /i "%CF_UPD_MODE%"=="move" goto brokenmove
>"%CF_UPD_RESULT%" echo {"status":"broken","message":"The update could not be finished. ClipForge still works from: %OLDJ%","version":"%CF_UPD_VERSION%","mode":"%CF_UPD_MODE%"}
set "DIR=%OLD%"
call :startapp
exit 5
:brokenmove
>"%CF_UPD_RESULT%" echo {"status":"broken","message":"The move could not be finished. ClipForge still works from: %NEWJ%","version":"%CF_UPD_VERSION%","mode":"%CF_UPD_MODE%"}
set "DIR=%CF_UPD_NEW%"
call :startapp
exit 5

rem 8. Done: start the app, tidy up.
:done
call :result updated ""
set "DIR=%CF_UPD_INSTALL%"
call :startapp
if /i "%CF_UPD_MODE%"=="move" rd /s /q "%CF_UPD_NEW%" >nul 2>&1
if exist "%CF_UPD_NEW%\%MARK%" rd /s /q "%CF_UPD_NEW%" >nul 2>&1
if "%CREATED%"=="0" rd /s /q "%OLD%" >nul 2>&1
if /i not "%CF_UPD_MODE%"=="move" goto finished
if "%CF_UPD_REMOVE_LIST%"=="" goto finished
if not exist "%CF_UPD_REMOVE_LIST%" goto finished
rem Older ClipForge folders named by the app: next to the new place,
rem holding the program, nothing else.
for %%I in ("%CF_UPD_INSTALL%") do set "PARENT=%%~dpI"
for /f "usebackq delims=" %%L in ("%CF_UPD_REMOVE_LIST%") do if /i "%%~dpL"=="%PARENT%" if /i not "%%~fL"=="%CF_UPD_INSTALL%" if /i not "%%~fL"=="%CF_UPD_NEW%" if exist "%%~fL\%CF_UPD_EXE%" rd /s /q "%%~fL" >nul 2>&1
del "%CF_UPD_REMOVE_LIST%" >nul 2>&1
:finished
set "MSG=done"
call :log
exit 0

:second
set "MSG=another script is already doing this update: stopping"
call :log
exit 7

:stillrunning
call :result failed "ClipForge did not close, so nothing was changed."
exit 6

:nofolders
call :result failed "The update was started without its folders."
exit 2

:incomplete
call :result failed "The downloaded update is not complete."
set "DIR=%BACK%"
call :startapp
exit 2

:noinstall
call :result failed "The ClipForge folder was not found."
set "DIR=%BACK%"
call :startapp
exit 2

:notclipforge
call :result failed "The folder for ClipForge exists and is not a ClipForge folder. Nothing was changed."
set "DIR=%BACK%"
call :startapp
exit 2

:foreignold
call :result failed "A folder ending in .update-old that ClipForge did not make is in the way. Move or rename it, then try again."
set "DIR=%BACK%"
call :startapp
exit 2

:oldstuck
call :result failed "An older copy of ClipForge next to the app could not be removed."
set "DIR=%BACK%"
call :startapp
exit 2

:inuse
call :result failed "The program file in the ClipForge folder is in use (is ClipForge still running?). Nothing was changed."
set "DIR=%BACK%"
call :startapp
exit 3

:nobackup
rd /s /q "%OLD%" >nul 2>&1
call :result failed "A safety copy of the current version could not be made (is the disk full?). Nothing was changed."
set "DIR=%BACK%"
call :startapp
exit 3

rem --- helpers -------------------------------------------------------------

rem Appends MSG to the log, with the time.
:log
setlocal EnableDelayedExpansion
>>"!CF_UPD_LOG!" echo !DATE! !TIME! script(cmd): !MSG!
endlocal
goto :eof

rem call :result STATUS "MESSAGE"   (fixed text only, no quotes in it)
:result
set "MSG=result: %~1 %~2"
call :log
>"%CF_UPD_RESULT%" echo {"status":"%~1","message":"%~2","version":"%CF_UPD_VERSION%","mode":"%CF_UPD_MODE%"}
goto :eof

rem Starts the app in DIR (not when CF_UPD_NORESTART is set).
:startapp
if "%CF_UPD_NORESTART%"=="1" goto :eof
if not exist "%DIR%\%CF_UPD_EXE%" goto :eof
set "MSG=starting the app in [%DIR%]"
call :log
start "" /D "%DIR%" "%DIR%\%CF_UPD_EXE%"
goto :eof
