# Windows Printer Sharing Fix

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Version](https://img.shields.io/badge/Version-2.3.1-blue)

A simple but powerful tool to fix common Windows printer sharing problems. Works on Windows 10, 11 (including 24H2+), ARM64, and Windows Server 2025.

---

## What it fixes

Windows updates often break network printing with cryptic errors. This tool fixes them:
- `0x0000011b`, `0x00000709`, `0x00000bc4`, `0x80070035`, `0x00000040`, `0x0000007e`, etc.

---

## 89 Repair Options

### Column 1: Core & Network [01-30]
| # | Feature |
|---|---|
| 01 | Patch Error 0x0000011b (RpcAuthnLevelPrivacy) |
| 02 | Bypass Error 0x00000709 / 0x7c (Point and Print) |
| 03 | Bypass Error 0x00000bc4 (No Printers Found) |
| 04 | Fix Error 0x80070035 (Automate Network Services) |
| 05 | Disable Client-Side Rendering (Error 0x6d1) |
| 06 | Fix Error 0x80070005 (Reset Spooler ACL) |
| 07 | Fix Error 0x00000040 (Network Unavailable) |
| 08 | Fix Error 0x00000002 (CopyFilesPolicy) |
| 09 | Fix Error 0x0000007e (RPC Bitness Mismatch) |
| 10 | Complete Network Reset (DNS, Winsock, NetBIOS) |
| 11 | Force Network Profile to Private |
| 12 | Force Disable Password Protected Sharing |
| 13 | Enable RPC via Named Pipes & TCP |
| 14 | Configure Firewall File & Printer Sharing |
| 15 | SMB 1.0 Legacy Protocol Management (ON/OFF) |
| 16 | Disable SMB Signing (Fix Win 11 NAS Access) |
| 17 | Force Modern SMB2/SMB3 Topology |
| 18 | Prioritize SMB in Network Provider Order |
| 19 | Disable IPv6 Stack |
| 20 | Enable mDNS & LLMNR (Discovery Protocols) |
| 21 | Configure WSD Firewall Rules (Port 3702) |
| 22 | Enable IPP & Mopria Sharing Foundation |
| 23 | Resolve Hyper-V/WSL Virtual Network Conflicts |
| 24 | Install Legacy LPR/LPD Protocols |
| 25 | Remote Network Printer Discovery |
| 26 | WSD to Standard TCP/IP Port Converter |
| 27 | Network Socket Re-init (Selective Purge) |
| 28 | Rescue Network Profile (Auto Watchdog) |
| 29 | Manually Inject Standard TCP/IP Port |
| 30 | Force Initialize WSD Print Device |

### Column 2: Spooler, Drivers & Policies [31-59]
| # | Feature |
|---|---|
| 31 | Hard Reset Print Spooler (Purge Queue) |
| 32 | Re-initialize RPC & DCOM Services |
| 33 | Remote Target Spooler Restart |
| 34 | Configure Spooler Auto-Restart on Crash |
| 35 | Purge Stale Spooler Dependencies |
| 36 | Deploy Spooler Watchdog (5-Min Audit) |
| 37 | Force Purge Print Queue (.shd/.spl) |
| 38 | Spooler Dependency Registry Reset |
| 39 | Driver Management (Print Server Properties) |
| 40 | Disable Print Driver Isolation |
| 41 | Universal Print Class Driver V4 Fix |
| 42 | Toggle PCL vs. PostScript Driver Mode |
| 43 | Orphaned Driver Sweeper (pnputil) |
| 44 | Bypass 'Driver is currently in use' |
| 45 | Ghost USB Port & Copy Eliminator |
| 46 | Force Remove Ghost Printers |
| 47 | Fix Microsoft Edge / UWP Printing |
| 48 | Reinstall Microsoft Print to PDF/XPS |
| 49 | Browser Print Sandbox Fix (Chromium) |
| 50 | Force Permanent Default Printer |
| 51 | Force-Set Default Printer (Reg Bypass) |
| 52 | Fix RDP Printer Terminal Services |
| 53 | Auto-Sanitize Printer Share Name |
| 54 | Downgrade LSA Protection (Legacy Auth) |
| 55 | Bypass Smart App Control (SAC) |
| 56 | Bypass Advanced ServerList Point & Print |
| 57 | Bypass UAC Admin Network TokenFilter |
| 58 | Force NTLMv2 Response Compliance |
| 59 | Manage Windows Protected Print (WPP) |

### Column 3: Diagnostics & Automation [60-89]
| # | Feature |
|---|---|
| 60 | Inject Credentials into Vault Permanently |
| 61 | Purge Stale Credentials from Vault |
| 62 | Bypass Credential Guard (Strict NTLM) |
| 63 | Cross-User Credential Mapping |
| 64 | Pre-execution Registry Backup (Spooler) |
| 65 | Rollback Registry from Backup |
| 66 | Generate System Restore Point (Security) |
| 67 | System File Checker & DISM Restoration |
| 68 | Restart BITS (Background Transfer) |
| 69 | Windows Update & Blocker Management |
| 70 | Launch Native Windows Troubleshooter |
| 71 | Force Printer Online Status |
| 72 | Launch Services.msc |
| 73 | Detect OS Version & Build Architecture |
| 74 | Ping & Port 445/135 Diagnostics |
| 75 | View Execution Logs |
| 76 | Audit Last 20 Print Service Error Logs |
| 77 | System Diagnostics Audit |
| 78 | PrintService Event Log Parser (Top 5) |
| 79 | Generate HTML Diagnostic Report |
| 80 | Detect GPO Intervention (Policy Scan) |
| 81 | PrintBRM (Backup/Restore Migration) |
| 82 | Enable SMB Guest Access & Drop Anonymous Blocks |
| **83** | **EXTREME PATH (WIN 11 24H2/25H2/26H2+ & ARM64)** |
| **84** | **ALLFIX (50 AUTOMATED FIXES)** |
| **85** | **SILENT ALLFIX & REBOOT (ZERO-PROMPT)** |
| 86 | Map Local Port to UNC Path (Bypass 0x00000709) |
| 87 | Remove Injected Local Port (UNC) |
| 88 | Reboot System |
| 89 | EXIT SCRIPT |

---

## ⚠️ Good to Know: Under the Hood

To keep things completely transparent, if you run the automated playbooks (`[83]`, `[84]`, or `[85]`), the script does a few extra things in the background that don't pop up on the screen. This is done to make sure the fixes actually stick:

- **GPO Override (`gpupdate /force`):** It forces a local Group Policy update right before modifying the registry so your domain controller doesn't immediately overwrite the fixes.
- **Scheduled Tasks Injection:** The script deploys background tasks under Windows Task Scheduler for persistent repairs and diagnostics:
  - `PrinterFixPostUpdate` (runs on startup) & `PrinterFixDaily` (runs daily at 10:00 AM): Automatically re-apply critical registry fixes in case Windows Updates reset them.
  - `SpoolerWatchdog` (runs every 5 minutes): Checks and automatically restarts the Print Spooler service if a driver crash stops it.
  > [!NOTE]
  > All registered tasks are configured to bypass laptop AC constraints (they will execute successfully even when unplugged). However, because `SpoolerWatchdog` runs periodically every 5 minutes, it can cause minor battery drain on laptops over time. If you want to maximize battery life, you can easily disable or delete it through the Task Scheduler GUI or by running: `Disable-ScheduledTask -TaskName "SpoolerWatchdog"` in PowerShell (as Administrator).
- **Network & Credential Wipes:** It runs commands like `klist purge`, `ipconfig /flushdns`, and `nbtstat -RR`. If you use Extreme Path `[83]`, it also forcefully wipes stale network credentials from your Windows Vault using `cmdkey`. 
- **Registry Overrides [86/87]:** If you use the UNC Bypass feature and Windows blocks the standard API, the script will forcefully inject or delete the port directly inside `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports`. 
- **Force Kills [37] & [44]:** When you purge the queue or try to bypass a locked driver, the script sends a direct termination signal (`Stop-Process -Force`) to `splwow64`, `PrintIsolationHost`, and `printfilterpipelinesvc`. This drops all active print jobs immediately.
- **Driver Signature & Policy Bypass (KB5089549):** Temporarily sets `VulnerableDriverBlocklistEnable = 0` and `VerifiedAndReputablePolicyState = 0` to bypass driver block restrictions introduced in the post-KB5089549 cumulative update.
- **Strict Name & DNS Aliasing:** Configures `DisableStrictNameChecking = 1` and `DnsOnWire = 1` to ensure you can map/connect to printer shares using DNS CNAMEs or hostname aliases instead of only IPs.
- **NTLM Minimum Security Relaxation:** In Extreme Path `[83]`, sets client/server NTLM requirements to allow legacy authentication handshakes and prevent credential validation errors on Workgroups.

---

## Repository Structure

```text
WindowsPrinterSharingFix/
├── src/
│   └── WindowsPrinterSharingFix.ps1           # Core PowerShell source code (89 features)
├── assets/
│   ├── icon.ico                                # Application icon
│   └── khairudinfahmi_cert.cer                 # Code signing certificate
├── docs/
│   └── documentation.html                      # Offline HTML Documentation
├── build/
│   ├── Compile-ToExe.ps1                       # Build automation script
│   └── installer.iss                           # Inno Setup installer script
├── release/
│   ├── WindowsPrinterSharingFix.exe            # Compiled portable executable
│   └── WindowsPrinterSharingFix_Installer.exe  # Full setup installer
├── .gitignore
├── CHANGELOG.md                                # Version history
├── CONTRIBUTING.md                             # Contribution guidelines
├── LICENSE                                     # GPL-3.0 License
└── README.md                                   # Primary documentation
```

---

## Download & Installation

Pre-compiled binaries are available in the **[Releases](../../releases)** tab:

| File | Description |
|---|---|
| `WindowsPrinterSharingFix.exe` | Portable Executable — Run directly as Administrator |
| `WindowsPrinterSharingFix_Installer.exe` | Full Installer (includes start menu shortcuts & code signing) |

---

## Usage Instructions

### Quick Start (Recommended for Beginners)
1. Download the installer from the **[Releases](../../releases)** tab.
2. Run the application as an **Administrator**.
3. Type `64` → Enter (Execute registry backup).
4. Type `84` → Enter (Execute ALLFIX - 50 automated fixes).
5. Reboot your system.

### Specific Workflow for Windows 11 24H2/25H2/26H2+
1. Type `64` → Enter (Execute registry backup).
2. Type `83` → Enter (Execute Extreme Path fixes).
3. Reboot your system.

### Emergency Mode (Unattended)
- Type `85` → Enter (Silent AllFix: Executes all fixes and forcibly reboots the system without user prompts).

### Help & Documentation
- Type `?` → Display the help guide.
- Type `? 7` → Display detailed documentation for feature 7.
- Type `? all` → Open the complete offline HTML.

---

## Interactive Console Interface

```text
 USER: admin | COMPUTERNAME: OFFICE-PC | OS: WINDOWS 11 PRO 26100 64BIT | Windows Printer Sharing Fix v2.3.1
 =======================================================================================================

 CORE FIXES & NETWORK SERVICES              SPOOLER, DRIVERS & POLICIES              DIAGNOSTICS & AUTOMATION

 [01] Patch Error 0x0000011b                 [31] Hard Reset Print Spooler             [60] Inject Credentials into Vault
 [02] Bypass Error 0x00000709                [32] Re-initialize RPC & DCOM             [61] Purge Stale Credentials
 ...                                         ...                                       ...
 [30] Force Initialize WSD Print Device      [59] Manage Windows Protected Print       [84] ALLFIX (50 AUTOMATED STEPS)
                                                                                        [85] SILENT ALLFIX & REBOOT
 -----------------------------------------------------------------------------------------------------------
 :   NOTE:                                                                              :
 :   [84] ALLFIX (50 Steps) | [83] EXTREME PATH (Win11) | [85] SILENT ALLFIX           :
 :   [?] HELP | [? 7] INFO | [? all] HTML | TIP: If 'Check Printer Name' error, use Option [86] :
 -----------------------------------------------------------------------------------------------------------

Type option: _
```

---

## System Compatibility

| OS | Support Status |
|---|---|
| Windows 10 (All Builds) | Fully Supported |
| Windows 11 21H2 - 23H2 | Fully Supported |
| Windows 11 24H2 / 25H2 / 26H2+ | Supported (Requires Extreme Path `[83]`) |
| Windows 11 ARM64 (Snapdragon) | Supported |
| Windows Server 2012 / 2016 / 2019 / 2022 / 2025 | Fully Supported |
| Windows 7, 8, 8.1 | Partial / Registry Support Only |

---

## Building from Source

### Prerequisites
- PowerShell 5.1+
- [ps2exe](https://www.powershellgallery.com/packages/ps2exe) module (installed automatically by the build script)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (for compiling the installer)

### Compile Portable EXE

```powershell
# From the project root, execute:
.\build\Compile-ToExe.ps1
```

Or compile manually:
```powershell
# Install the ps2exe module (if not present)
Install-Module -Name ps2exe -Force -Scope CurrentUser

# Compile
Invoke-ps2exe -inputFile src\WindowsPrinterSharingFix.ps1 -outputFile release\WindowsPrinterSharingFix.exe `
    -iconFile assets\icon.ico -requireAdmin `
    -title "Windows Printer Sharing Fix" -company "khairudinfahmi"
```

### Compile Installer

```powershell
# Ensure WindowsPrinterSharingFix.exe exists in the release/ directory
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\installer.iss
```

---

## Testing & Verification

You can verify that the background tasks are functioning correctly, test behavior in isolated environments, and check code integrity using the following validation procedures:

### Test 1: SpoolerWatchdog Verification
This task detects if the Print Spooler service stops and restarts it automatically:
```powershell
# 1. Stop the spooler service manually
Stop-Service spooler -Force

# 2. Trigger the watchdog task immediately
Start-ScheduledTask -TaskName "SpoolerWatchdog"

# 3. Check the service status (should be "Running")
Get-Service spooler
```

### Test 2: PrinterFixPostUpdate Verification
This task restores your configuration if registry values are tampered with or reset:
```powershell
# 1. Temporarily write a test value (0) to a sharing registry key
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name "RpcOverNamedPipes" -Value 0

# 2. Trigger the reapply task immediately
Start-ScheduledTask -TaskName "PrinterFixPostUpdate"

# 3. Check the registry value again (should be restored to "1")
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name "RpcOverNamedPipes"
```

### Test 3: Windows Sandbox Isolation Testing
To safely verify the interface rendering and registry modification steps on a clean machine without affecting your physical environment, you can run the tool in an isolated sandbox:
1. Make sure **Windows Sandbox** is enabled on your host machine.
2. Copy `src/WindowsPrinterSharingFix.ps1` (or the compiled standalone `release/WindowsPrinterSharingFix.exe`).
3. Open **Windows Sandbox** from your Start Menu.
4. Paste the file directly onto the Sandbox desktop.
5. Launch an elevated PowerShell console inside the Sandbox and run the script/executable to test interactions.

### Test 4: PowerShell AST Syntax Validation
Before releasing code changes, you can verify that the script is free of compilation errors, unclosed brackets, or invalid syntax using the PowerShell parser:
```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path "src/WindowsPrinterSharingFix.ps1"),
    [ref]$null,
    [ref]$errors
)
if ($errors) {
    Write-Host "[-] Syntax errors detected in script:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
} else {
    Write-Host "[SUCCESS] PowerShell script is syntax-clean (AST validation passed)." -ForegroundColor Green
}
```

---

## Important Notes
- **Elevation Required**: This utility **must be executed as an Administrator** to modify registry keys and manage Windows subsystem services.
- **Backup Mandatory**: Always execute a **Registry Backup (Option `[64]`)** before running any automated fixes.
- **Reboot Required**: A system reboot is strictly necessary to commit registry changes and restart network stacks.
- **Air-Gapped Support**: This tool operates **100% offline**, requiring zero internet connectivity.

---

## Contributing

Contributions, issues, and feature requests are welcome! Please review [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

---

## License

This project is open-source and free to use under the [GPL-3.0 License](LICENSE).
Feel free to modify and distribute, but please ensure credit is attributed to the original author.

---

## Author

**@khairudinfahmi** — 2026
