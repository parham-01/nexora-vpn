#ifndef AppVer
#define AppVer "1.0.0"
#endif
#ifndef AppExe
#define AppExe "parham_client.exe"
#endif

[Setup]
AppId={{6F0B1E52-6C0D-4B5E-9B0A-3A7E4C1D9A21}
AppName=NEXORA VPN
AppVersion={#AppVer}
AppPublisher=NEXORA
DefaultDirName={autopf}\NEXORA VPN
DefaultGroupName=NEXORA VPN
DisableProgramGroupPage=yes
OutputDir={#OutDir}
OutputBaseFilename=NEXORA-VPN-Windows-Setup-x64
Compression=lzma2/fast
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
WizardStyle=modern
PrivilegesRequired=admin

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NEXORA VPN"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\NEXORA VPN"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,NEXORA VPN}"; Flags: nowait postinstall skipifsilent
