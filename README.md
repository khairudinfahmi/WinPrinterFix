# Windows Printer Sharing Fix

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-GPL_3.0-green)
![Features](https://img.shields.io/badge/Features-88-orange)
![Version](https://img.shields.io/badge/Version-2.1.0-blue)

An automated diagnostic and repair utility designed to resolve **all Windows printer sharing issues**. Features native support for Windows 10, Windows 11 (including 24H2/25H2/26H2 builds), ARM64 (Snapdragon) architectures, and Windows Server 2025.

---

## The Problem

Following routine Windows updates, network printer sharing frequently breaks, throwing critical system errors such as:
- `0x0000011b` — RPC Authentication Failure
- `0x00000709` — Point and Print Restriction / Failure to set default printer
- `0x00000bc4` — No printers were found
- `0x80070035` — The network path was not found
- `0x80070005` — Access Denied (Spooler ACL)
- `0x00000040` — Network Unavailable
- `0x00000002` — CopyFilesPolicy Violation
- `0x0000007e` — RPC Bitness Mismatch (32/64-bit architecture conflict)
- And many more...

This tool resolves **all of these issues automatically** via a centralized interactive console.

---

## Features (88 Repair Options)

### Column 1: Core Fixes & Network Services [01-30]
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

### Column 2: Spooler, Drivers & Policies [31-60]
| # | Feature |
|---|---|
| 31 | Hard Reset Print Spooler (Purge Queue) |
| 32 | Re-initialize RPC & DCOM Services |
| 33 | Remote Target Spooler Restart |
| 34 | Configure Spooler Auto-Restart on Crash |
| 35 | Purge Stale Spooler Dependencies |
| 36 | Deploy Spooler Watchdog (5-Min Audit) |
| 37 | Hard-Nuke Print Queue (.shd/.spl) |
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
| 50 | Auto-Inject F4/Folio Paper Size |
| 51 | Force Permanent Default Printer |
| 52 | Force-Set Default Printer (Reg Bypass) |
| 53 | Fix RDP Printer Terminal Services |
| 54 | Auto-Sanitize Printer Share Name |
| 55 | Downgrade LSA Protection (Legacy Auth) |
| 56 | Bypass Smart App Control (SAC) |
| 57 | Bypass Advanced ServerList Point & Print |
| 58 | Bypass UAC Admin Network TokenFilter |
| 59 | Force NTLMv2 Response Compliance |
| 60 | Manage Windows Protected Print (WPP) |

### Column 3: Diagnostics & Automation [61-88]
| # | Feature |
|---|---|
| 61 | Inject Credentials into Vault Permanently |
| 62 | Purge Stale Credentials from Vault |
| 63 | Bypass Credential Guard (Strict NTLM) |
| 64 | Cross-User Credential Mapping |
| 65 | Pre-execution Registry Backup (Spooler) |
| 66 | Rollback Registry from Backup |
| 67 | Generate System Restore Point (Security) |
| 68 | System File Checker & DISM Restoration |
| 69 | Restart BITS (Background Transfer) |
| 70 | Uninstall & Pause Specific KB Update |
| 71 | Launch Native Windows Troubleshooter |
| 72 | Force Printer Online Status |
| 73 | Launch Services.msc |
| 74 | Detect OS Version & Build Architecture |
| 75 | Ping & Port 445/135 Diagnostics |
| 76 | View Execution Logs |
| 77 | Audit Last 20 Print Service Error Logs |
| 78 | System Diagnostics Audit |
| 79 | PrintService Event Log Parser (Top 5) |
| 80 | Generate HTML Diagnostic Report |
| 81 | Detect GPO Intervention (Policy Scan) |
| 82 | PrintBRM (Backup/Restore Migration) |
| 83 | Enable SMB Guest Access & Drop Anonymous Blocks |
| **84** | **EXTREME PATH (WIN 11 24H2/25H2 & ARM64)** |
| **85** | **ALLFIX (50 AUTOMATED REPAIR SEQUENCES)** |
| **86** | **SILENT NUKE & ALLFIX (ZERO-PROMPT)** |
| 87 | Reboot System |
| 88 | EXIT SCRIPT |

---

## Download & Installation

Pre-compiled binaries are available in the **[Releases](../../releases)** tab:

| File | Description |
|---|---|
| `WinPrinterFix.exe` | Portable Executable — Run directly as Administrator |
| `WindowsPrinterSharingFix_Installer.exe` | Full Installer (includes start menu shortcuts & code signing) |

---

## Usage Instructions

### Quick Start (Recommended for Beginners)
1. Download the installer from the **[Releases](../../releases)** tab.
2. Run the application as an **Administrator**.
3. Type `65` → Enter (Execute registry backup).
4. Type `85` → Enter (Execute ALLFIX - 50 automated repair steps).
5. Reboot your system.

### Specific Workflow for Windows 11 24H2/25H2
1. Type `65` → Enter (Execute registry backup).
2. Type `84` → Enter (Execute Extreme Path fixes).
3. Reboot your system.

### Emergency Mode (Unattended)
- Type `86` → Enter (Silent Nuke: Executes all fixes and forcibly reboots the system without user prompts).

### Help & Documentation
- Type `?` → Display the help guide.
- Type `? 7` → Display detailed documentation for feature 7.
- Type `? all` → Open the complete HTML offline manual.

---

## Interactive Console Interface

```text
 USER: admin | COMPUTERNAME: OFFICE-PC | OS: WINDOWS 11 PRO 26100 64BIT | Windows Printer Sharing Fix
 =======================================================================================================

 CORE FIXES & NETWORK SERVICES              SPOOLER, DRIVERS & POLICIES              DIAGNOSTICS & AUTOMATION

 [01] Patch Error 0x0000011b                 [31] Hard Reset Print Spooler             [61] Inject Credentials into Vault
 [02] Bypass Error 0x00000709                [32] Re-initialize RPC & DCOM             [62] Purge Stale Credentials
 ...                                         ...                                       ...
 [30] Force Initialize WSD Print Device      [60] Manage Windows Protected Print       [85] ALLFIX (50 AUTOMATED STEPS)
                                                                                        [86] SILENT NUKE & ALLFIX
 -----------------------------------------------------------------------------------------------------------
 :   NOTE:                                                                              :
 :   [85] ALLFIX (50 Steps) | [84] EXTREME PATH (Win11) | [86] SILENT NUKE             :
 :   Input [?] for HELP     | [? 7] feature 7 details   | [? all] open HTML            :
 -----------------------------------------------------------------------------------------------------------

Type option: _
```

---

## System Compatibility

| OS | Support Status |
|---|---|
| Windows 10 (All Builds) | Fully Supported |
| Windows 11 21H2 - 23H2 | Fully Supported |
| Windows 11 24H2 / 25H2 / 26H2 | Supported (Requires Extreme Path `[84]`) |
| Windows 11 ARM64 (Snapdragon) | Supported |
| Windows Server 2019 / 2022 / 2025 | Fully Supported |
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
Invoke-ps2exe -inputFile src\WinPrinterFix.ps1 -outputFile release\WinPrinterFix.exe `
    -iconFile assets\icon.ico -requireAdmin `
    -title "Windows Printer Sharing Fix" -company "khairudinfahmi"
```

### Compile Installer

```powershell
# Ensure WinPrinterFix.exe exists in the release/ directory
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\installer.iss
```

---

## Repository Structure

```text
WinPrinterFix/
├── src/
│   └── WinPrinterFix.ps1                      # Core PowerShell source code (88 features)
├── assets/
│   ├── icon.ico                                # Application icon
│   └── khairudinfahmi_cert.cer                 # Code signing certificate
├── docs/
│   └── dokumentasi.html                        # Offline HTML manual
├── build/
│   ├── Compile-ToExe.ps1                       # Build automation script
│   └── installer.iss                           # Inno Setup installer script
├── release/
│   └── WinPrinterFix.exe                       # Compiled portable executable
├── .gitignore
├── CHANGELOG.md                                # Version history
├── CONTRIBUTING.md                             # Contribution guidelines
├── LICENSE                                     # GPL-3.0 License
└── README.md                                   # Primary documentation
```

---

## Important Notes
- **Elevation Required**: This utility **must be executed as an Administrator** to modify registry keys and manage Windows subsystem services.
- **Backup Mandatory**: Always execute a **Registry Backup (Option `[65]`)** before running any automated repair sequences.
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

> Engineered to assist IT administrators and end-users frustrated by persistent Windows printer sharing deployment failures.
