#define MyAppName "Bobux"
#define MyAppPublisher "Pavel"
#define MyAppVersion "0.1.0"
#define LauncherExe "BobuxLauncher.exe"
#define LauncherBuildDir "..\..\launcher_export\windows"

[Setup]
AppId={{8F7E41A7-9E2D-4A91-BC33-9F9B8D6C2A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\BobuxLauncher
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist\installer
OutputBaseFilename=BobuxSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\icon.ico
UninstallDisplayIcon={app}\{#LauncherExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#LauncherBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\Bobux"; Filename: "{app}\{#LauncherExe}"; WorkingDir: "{app}"
Name: "{group}\Bobux"; Filename: "{app}\{#LauncherExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#LauncherExe}"; Description: "Launch Bobux"; Flags: nowait postinstall skipifsilent
