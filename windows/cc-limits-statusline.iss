; Inno Setup script for cc-limits-statusline — builds a single setup.exe.
;
; The .exe only bundles files and invokes the PowerShell helpers, which hold all
; the real logic (install-steps.ps1 / uninstall-steps.ps1). Compile with:
;
;     iscc windows\cc-limits-statusline.iss
;
; -> Output\cc-limits-statusline-setup.exe
;
; Per-user install (no admin needed). AppVersion must stay in sync with
; .claude-plugin/plugin.json, .claude-plugin/marketplace.json and CHANGELOG.md.

#define MyAppName "cc-limits-statusline"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Danil Chernyshev"
#define MyAppURL "https://github.com/danilchernyshev/cc-limits-statusline"

[Setup]
AppId={{B7E4F2A0-9C3D-4A1E-8F6B-2D5C7E9A1B30}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=cc-limits-statusline-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; The statusline + its config example live at the repo root (one level up).
Source: "..\statusline.sh";        DestDir: "{app}"; Flags: ignoreversion
Source: "..\config.example.conf";  DestDir: "{app}"; Flags: ignoreversion
; The installer logic.
Source: "install-steps.ps1";       DestDir: "{app}"; Flags: ignoreversion
Source: "uninstall-steps.ps1";     DestDir: "{app}"; Flags: ignoreversion

[Run]
; Auto-installs jq + Git for Windows (via winget), copies the script, and wires
; up settings.json. May take a few minutes the first time while winget runs.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-steps.ps1"""; \
  StatusMsg: "Installing dependencies and wiring up the statusline (first run may take a few minutes)…"; \
  Flags: waituntilterminated

[UninstallRun]
; Undo the settings.json wiring and remove the installed script before the
; bundled files themselves are deleted.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-steps.ps1"""; \
  Flags: waituntilterminated runhidden
