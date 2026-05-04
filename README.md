# Windows Printer Sharing Fix

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-GPL_3.0-green)
![Features](https://img.shields.io/badge/Features-70-orange)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)

An automated diagnostic and repair utility designed to resolve **all Windows printer sharing issues**. Features native support for Windows 10, Windows 11 (including 24H2/25H2/26H2 builds), ARM64 (Snapdragon) architectures, and Windows Server 2025.

---

## The Problem

Following routine Windows updates, network printer sharing frequently breaks, throwing critical system errors such as:
- `0x0000011b` — RPC Authentication Failure
- `0x00000709` — Point and Print Restriction / Failure to set default printer
- `0x00000bc4` — No printers were found
- `0x80070035` — The network path was not found
- `0x0000007e` — RPC Bitness Mismatch (32/64-bit architecture conflict)
- And many more...

This tool resolves **all of these issues automatically** via a centralized interactive console.

---

## Features (70 Repair Options)

### Error Code Fixes
| # | Feature |
|---|---|
| 01 | Patch Error 0x0000011b (RpcAuthnLevelPrivacy) |
| 02 | Bypass Error 0x00000709 / 0x7c (Point and Print Restrictions) |
| 03 | Bypass Error 0x00000bc4 (No Printers Found) |
| 04 | Fix Error 0x80070035 (Network Services Automation) |
| 05 | Disable Client-Side Rendering (Error 0x6d1) |
| 55 | Fix Error 0x00000040 (Network Unavailable) |
| 56 | Fix Error 0x00000002 (CopyFilesPolicy Violation) |
| 57 | Fix Error 0x0000007e (RPC Bitness Mismatch) |

### Network & Sharing Configuration
| # | Feature |
|---|---|
| 06 | Hard Reset Print Spooler Architecture |
| 07 | Enable SMB Guest Authentication |
| 08 | Complete Network Reset (DNS, Winsock, NetBIOS) |
| 09 | Force Network Profile to Private |
| 10 | Disable Password Protected Sharing |
| 11 | Force RPC over Named Pipes & TCP |
| 12 | Configure Windows Firewall for File & Printer Sharing |

### System Utilities
| # | Feature |
|---|---|
| 13 | Pre-execution Registry Backup |
| 14 | Re-initialize RPC & DCOM Services |
| 15 | System File Checker & DISM Restoration |
| 16 | Driver Management (Print Server Properties) |
| 17 | Reset Spooler Directory ACL Permissions |

### Credential & Protocol Management
| # | Feature |
|---|---|
| 18 | SMB 1.0 Legacy Protocol Management (ON/OFF) |
| 19 | Inject Windows Credentials into Vault |
| 20 | Purge Windows Vault Credentials |
| 21 | Launch Native Windows Troubleshooter |
| 22 | Force Printer Online Status |
| 23 | Launch Services.msc |

### Execution & Control Paths
| # | Feature |
|---|---|
| 24 | Extreme Path (Aggressive Win 11 24H2/25H2 & ARM64 fixes) |
| **25** | **ALLFIX - 42 Automated Repair Sequences** |
| 26 | Detect OS Version & Build Architecture |
| 27 | Rollback Registry from Backup |
| 28 | Disable IPv6 Stack |
| 29 | Generate HTML Diagnostic Report |
| 30 | Reboot System |
| 37 | Silent Nuke & AllFix (Zero-Interaction Mode) |

### Remote Diagnostics
| # | Feature |
|---|---|
| 32 | Ping & Port 445/135 Network Diagnostics |
| 33 | Remote Network Printer Discovery |
| 34 | Remote Target Spooler Restart |
| 35 | View Execution Logs |
| 36 | PrintBRM (Printer Migration Utility) |

### Advanced System Tweaks
| # | Feature |
|---|---|
| 39-54 | SMB Signing, WSD, LSA, SAC, IPP, UAC, NTLMv2 Enforcement, etc. |
| 58-70 | WPP, RDP Printer Redirection, Hyper-V Network Fix, LPR/LPD, Print to PDF Restoration, Credential Guard Bypass, BITS Restart |

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
3. Type `13` → Enter (Execute registry backup).
4. Type `25` → Enter (Execute ALLFIX - 42 automated repair steps).
5. Reboot your system.

### Specific Workflow for Windows 11 24H2/25H2
1. Type `13` → Enter (Execute registry backup).
2. Type `24` → Enter (Execute Extreme Path fixes).
3. Reboot your system.

### Emergency Mode (Unattended)
- Type `37` → Enter (Silent Nuke: Executes all fixes and forcibly reboots the system without user prompts).

### Help & Documentation
- Type `?` → Display the help guide.
- Type `? 7` → Display detailed documentation for feature 7.
- Type `? all` → Open the complete HTML offline manual.

---

## Interactive Console Interface

```text
 USER: admin | COMPUTERNAME: OFFICE-PC | OS: WINDOWS 11 PRO 26100 64BIT | Windows Printer Sharing Fix
 ------------------------------------------------------------------------------------------------------------------------

 ERROR CODES & FIXES                                         NETWORK & ADVANCED TWEAKS

 [01] Patch Error 0x0000011b (RpcAuthnLevelPrivacy)          [36] PrintBRM (Backup/Restore)
 [02] Bypass Error 0x00000709 / 0x7c (Point and Print)       [37] SILENT NUKE & ALLFIX (NO PROMPT)
 [03] Bypass Error 0x00000bc4 (No Printers Found)            [38] Force Remove Ghost Printers
 ...                                                         ...
 [25] EXECUTE ALLFIX (42 AUTOMATED REPAIR SEQUENCES)         [70] System Diagnostics

 :   NOTE:                                                                            :
 :   Recommended: [25] EXECUTE ALLFIX (42 AUTOMATED REPAIR SEQUENCES)                 :
 :   Type [?] for HELP | [? 7] feature details | [? all] open HTML manual             :

Type option: _
```

---

## System Compatibility

| OS | Support Status |
|---|---|
| Windows 10 (All Builds) | Fully Supported |
| Windows 11 21H2 - 23H2 | Fully Supported |
| Windows 11 24H2 / 25H2 / 26H2 | Supported (Requires Extreme Path) |
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
Invoke-ps2exe -inputFile src\WinPrinterFix.ps1 -outputFile Output\WinPrinterFix.exe `
    -iconFile assets\icon.ico -requireAdmin `
    -title "Windows Printer Sharing Fix" -company "khairudinfahmi"
```

### Compile Installer

```powershell
# Ensure WinPrinterFix.exe exists in the Output/ directory
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\installer.iss
```

---

## Repository Structure

```text
WinPrinterFix/
├── src/
│   └── WinPrinterFix.ps1                      # Core PowerShell source code (70 features)
├── assets/
│   ├── icon.ico                                # Application icon
│   └── khairudinfahmi_cert.cer                 # Code signing certificate
├── docs/
│   └── dokumentasi.html                        # Offline HTML manual
├── build/
│   ├── Compile-ToExe.ps1                       # Build automation script
│   └── installer.iss                           # Inno Setup installer script
├── .gitignore
├── CHANGELOG.md                                # Version history
├── CONTRIBUTING.md                             # Contribution guidelines
├── LICENSE                                     # GPL-3.0 License
└── README.md                                   # Primary documentation
```

---

## Important Notes
- **Elevation Required**: This utility **must be executed as an Administrator** to modify registry keys and manage Windows subsystem services.
- **Backup Mandatory**: Always execute a **Registry Backup (Option 13)** before running any automated repair sequences.
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
