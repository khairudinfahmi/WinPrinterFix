[Setup]
AppName=Windows Printer Sharing Fix
AppVersion=2.1.1
AppPublisher=khairudinfahmi
AppPublisherURL=https://github.com/khairudinfahmi/WinPrinterFix
AppSupportURL=https://github.com/khairudinfahmi/WinPrinterFix/issues
DefaultDirName={autopf}\Windows Printer Sharing Fix
DefaultGroupName=Windows Printer Sharing Fix
OutputDir=..\release
OutputBaseFilename=WindowsPrinterSharingFix_Installer
Compression=lzma
SolidCompression=yes
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\icon.ico
UninstallDisplayName=Windows Printer Sharing Fix
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
DisableWelcomePage=no
VersionInfoCompany=khairudinfahmi
VersionInfoProductName=Windows Printer Sharing Fix
VersionInfoProductVersion=2.1.1.0
VersionInfoVersion=2.1.1.0
VersionInfoDescription=Windows Printer Sharing Fix Setup Installer

[Files]
Source: "..\release\WinPrinterFix.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\dokumentasi.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\khairudinfahmi_cert.cer"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Windows Printer Sharing Fix"; Filename: "{app}\WinPrinterFix.exe"; IconFilename: "{app}\icon.ico"
Name: "{group}\Windows Printer Sharing Fix Documentation"; Filename: "{app}\dokumentasi.html"
Name: "{autodesktop}\Windows Printer Sharing Fix"; Filename: "{app}\WinPrinterFix.exe"; Tasks: desktopicon; IconFilename: "{app}\icon.ico"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{sys}\certutil.exe"; Parameters: "-addstore TrustedPublisher ""{app}\khairudinfahmi_cert.cer"""; Flags: runhidden waituntilterminated; StatusMsg: "Installing publisher certificate..."
Filename: "{sys}\certutil.exe"; Parameters: "-addstore Root ""{app}\khairudinfahmi_cert.cer"""; Flags: runhidden waituntilterminated; StatusMsg: "Installing certificate to Trusted Root..."

[UninstallRun]
Filename: "{sys}\certutil.exe"; Parameters: "-delstore TrustedPublisher ""khairudinfahmi"""; Flags: runhidden; RunOnceId: "DelTrustedPub"
Filename: "{sys}\certutil.exe"; Parameters: "-delstore Root ""khairudinfahmi"""; Flags: runhidden; RunOnceId: "DelRoot"
