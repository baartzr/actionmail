; InboxIQ Installer Script
; This script requires Inno Setup 6.2 or later
; Download from: https://jrsoftware.org/isdl.php

#define MyAppName "ActionMail"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Seagreen"
#define MyAppURL "https://www.inboxiq.com/"
#define MyAppExeName "actionmail.exe"
#define MyAppId "A1B2C3D4-E5F6-4321-9876-543210FEDCBA"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; LicenseFile=..\LICENSE
; Uncomment the line above and create a LICENSE file if you want to show a license agreement during installation
; Uncomment the following line to run in non administrative install mode (install for current user only.)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\build\installer
OutputBaseFilename=ActionMail-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; Check: not IsAdminInstallMode

[Files]
; Main executable
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Flutter runtime and plugin DLLs
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; Data folder (contains ICU data and other resources)
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Custom code for checking prerequisites
function InitializeSetup(): Boolean;
var
  ErrorCode: Integer;
  WebView2Installed: Boolean;
begin
  Result := True;
  
  // Check if WebView2 Runtime is installed (required for webview)
  WebView2Installed := RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
                       RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}');
  
  if not WebView2Installed then
  begin
    if MsgBox('This application requires Microsoft Edge WebView2 Runtime to be installed.' + #13#10 + #13#10 +
              'Would you like to download and install it now?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      ShellExec('open', 'https://go.microsoft.com/fwlink/p/?LinkId=2124703', '', '', SW_SHOW, ewNoWait, ErrorCode);
      MsgBox('Please install WebView2 Runtime and then run this installer again.', mbInformation, MB_OK);
      Result := False;
    end
    else
    begin
      MsgBox('Installation cancelled. The application may not work correctly without WebView2 Runtime.', mbInformation, MB_OK);
      Result := False;
    end;
  end;
end;

