[Setup]
AppName=Windows Printer Sharing Fix
AppVersion=1.0
AppPublisher=khairudinfahmi
DefaultDirName={autopf}\Windows Printer Sharing Fix
DefaultGroupName=Windows Printer Sharing Fix
OutputDir=.\Output
OutputBaseFilename=WindowsPrinterSharingFix_Installer
Compression=lzma
SolidCompression=yes
SetupIconFile=khairudinfahmi.ico
UninstallDisplayIcon={app}\khairudinfahmi.ico
UninstallDisplayName=Windows Printer Sharing Fix
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
DisableWelcomePage=no
VersionInfoCompany=khairudinfahmi
VersionInfoProductName=Windows Printer Sharing Fix
VersionInfoProductVersion=1.0.0.0
VersionInfoVersion=1.0.0.0
VersionInfoDescription=Windows Printer Sharing Fix Setup Installer

[Files]
Source: "WinPrinterFix.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "khairudinfahmi.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "dokumentasi.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "khairudinfahmi_cert.cer"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Windows Printer Sharing Fix"; Filename: "{app}\WinPrinterFix.exe"; IconFilename: "{app}\khairudinfahmi.ico"
Name: "{group}\Dokumentasi Windows Printer Sharing Fix"; Filename: "{app}\dokumentasi.html"
Name: "{autodesktop}\Windows Printer Sharing Fix"; Filename: "{app}\WinPrinterFix.exe"; Tasks: desktopicon; IconFilename: "{app}\khairudinfahmi.ico"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "certutil.exe"; Parameters: "-addstore Root ""{app}\khairudinfahmi_cert.cer"""; Flags: runhidden waituntilterminated; StatusMsg: "Menginstall sertifikat publisher..."

[UninstallRun]
Filename: "certutil.exe"; Parameters: "-delstore Root khairudinfahmi"; Flags: runhidden
