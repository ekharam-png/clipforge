; ClipForge installer for Windows (Inno Setup 6), 1.14.1.
;
; A per-user install: no administrator rights, into
; %LOCALAPPDATA%\Programs\ClipForge, with a Start-menu shortcut and an
; uninstaller. There is no folder for the user to name, move or keep open,
; and the app's own updater keeps working there (the folder is the user's;
; the update scripts leave unins*.exe / unins*.dat alone).
;
; Built by the "Windows app" job of .github/workflows/video-editor-build.yml
; from the same folder that goes into the zip:
;
;   ISCC.exe /DAppVersion=1.14.1 /DSourceDir=<...>\dist\ClipForge ^
;            /DOutputDir=<...>\dist /DOutputName=ClipForge-1.14.1-build123-windows-setup ^
;            windows\installer\clipforge.iss
;
; Projects and media live in Documents\ClipForge and are never touched by
; the installer or the uninstaller.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef OutputName
  #define OutputName "ClipForge-Setup"
#endif

[Setup]
; Never change this id: it is how a newer installer finds the older install.
AppId={{7C1F4E0B-5B7A-4E63-9C5D-2F6A8D3B41C7}
AppName=ClipForge
AppVersion={#AppVersion}
AppVerName=ClipForge {#AppVersion}
AppPublisher=ClipForge
DefaultDirName={localappdata}\Programs\ClipForge
DefaultGroupName=ClipForge
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\clipforge.exe
UninstallDisplayName=ClipForge
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Installing over an older version: files the new one no longer has go
; (the app's own updater does the same by mirroring).
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ClipForge"; Filename: "{app}\clipforge.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\ClipForge"; Filename: "{app}\clipforge.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\clipforge.exe"; Description: "{cm:LaunchProgram,ClipForge}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; What the app's own updater put there after the install (the uninstaller
; only knows the files it installed itself). Named one by one: nothing
; else that may be in the folder is removed.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\clipforge.exe"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\Release notes.txt"
Type: files; Name: "{app}\Connect Claude to ClipForge.html"
Type: files; Name: "{app}\.clipforge-update-marker"
Type: dirifempty; Name: "{app}"
