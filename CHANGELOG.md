# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.1.1] - 2026-05-13

### Fixed
- **F4 Paper Size Injection**: Resolved `System.Byte[]` type mismatch bug in `Inject-F4PaperSize` by refactoring array construction to a flat byte array.
- **NTLMv2 Compatibility**: Upgraded `Fix-NTLMv2` to enforce Value 3 (Strict NTLMv2) for improved Synology NAS and modern print sharing compatibility.

---

## [2.1.0] - 2026-05-10

### Changed
- **Global ID Migration**: All 88 features have been reorganized into a strictly sequential, logical 3-column architecture for improved usability and consistency.
  - **Column 1 [01-30]**: Core Fixes & Network Services (Error codes, DNS, SMB, WSD, IPP, Firewall).
  - **Column 2 [31-60]**: Spooler, Drivers & Policies (Spooler management, V4 drivers, LSA, SAC, UAC).
  - **Column 3 [61-88]**: Diagnostics & Automation (Credentials, Backup, SFC, Troubleshooter, ALLFIX, Exit).
- **Key ID Changes**:
  - `[65]` Registry Backup (was `[13]`)
  - `[84]` Extreme Path (was `[24]`)
  - `[85]` ALLFIX (was `[25]`)
  - `[86]` Silent Nuke (was `[37]`)
  - `[88]` EXIT SCRIPT (was `[31]`)
- **UI Overhaul**: Feature text color standardized to Green for consistency. Special operations `[84]`, `[85]`, `[86]` highlighted in Red for visibility.
- **Console Layout**: Dynamic buffer/window sizing (180 columns) with proportional column widths (`62/55/58`) prevents text wrapping on any console size.
- **Help System**: All 88 help entries remapped to match new sequential IDs. Guide workflow references updated.
- **Termination Logic**: Fixed bypass IDs from old `31/30/37` to correct `88/87/86`.
- **AllFix**: Expanded from 42 to 50 automated repair steps.

### Fixed
- `$colWidth` undefined variable causing PadRight crash in Show-Menu column 3.
- BufferSize not set before WindowSize causing silent console resize failure.
- 18 switch cases referencing non-existent function names (e.g., `Uninstall-KBUpdate` → `Manage-WindowsUpdate`).
- ISS installer source path corrected from `Output/` to `release/`.
- Stale old-ID references in help guide text.
- Windows 11 misidentification bug caused by legacy `ProductName` registry strings (now actively checks Build >= 22000).

---

## [2.0.0] - 2026-05-10

### Added
- 18 new advanced diagnostic and repair modules, expanding total features from 70 to 88.
- **Driver & Windows Update**: Universal Print V4 Fix, PCL/PostScript Toggle, KB Uninstall & Pause, Orphaned Driver Sweeper, Force-Kill Driver Process.
- **Network & Port**: WSD to TCP/IP Converter, Network Socket Re-init, Rescue Network Profile (Watchdog), Ghost USB Port Eliminator.
- **Spooler & Queue**: Hard-Nuke Print Queue (.shd/.spl purge), Spooler Dependency Registry Reset.
- **Credentials**: Cross-User Credential Mapping, Force-Set Default Printer (Registry Bypass).
- **Third-Party Integration**: Auto-Sanitize Printer Share Name, Browser Print Sandbox Fix (Chromium), Auto-Inject F4/Folio Paper Size.
- **Advanced Diagnostics**: GPO Intervention Detection (Policy Scan), PrintService Event Log Parser (Top 5).

### Changed
- AllFix expanded from 42 to 50 automated repair steps with 8 new safe integrations.
- Extreme Path (Win 11 24H2/25H2) enhanced with V4 Driver Fix, Spooler Dependency Reset, and Share Name Sanitization.
- Menu system updated: dynamic row rendering supports variable-length columns.
- Help system expanded: full `? <number>` support for all 88 features.

---

## [1.0.1] - 2026-05-04

### Changed
- UI Enhancement: Highlighted primary operation modes in the CLI menu for better visibility.
- Documentation: Updated OS Support requirements to clarify Legacy OS (Windows 7/8/8.1) as "Partial/Registry Support only".
- Documentation: Replaced all emojis in the HTML manual with professional Lucide icons.
- Documentation: Corrected typo in log and backup directory paths.
- Features: Explicitly mapped error code `0x80070005` (Access Denied) into option descriptor for easier troubleshooting discovery.

---

## [1.0.0] - 2026-05-03
### Added
- 70 comprehensive printer sharing diagnostic and repair options for Windows 10/11/Server environments.
- Native support for Windows 11 24H2, 25H2, 26H2, and ARM64 (Snapdragon) architectures.
- Native support for Windows Server 2019, 2022, and 2025.
- AllFix: 42 automated repair steps executed sequentially via a single command.
- Extreme Path tailored specifically for Windows 11 Build 26000+.
- Silent Nuke mode (zero-interaction, unattended execution with forced auto-restart).
- Interactive contextual help system (`?`, `? <number>`, `? all`).
- Comprehensive offline HTML documentation with built-in search functionality.
- Inno Setup compiler integration with automated code signing certificate generation.
- Build automation script (`Compile-ToExe.ps1`) to seamlessly compile PS1 source into standalone EXE.
- Advanced system diagnostics (Print Spooler state, RPC, Windows Defender Firewall, Network Profile).
- Remote network printer management utilities (Ping test, Port 445/135 Scan, Remote Target Spooler Reset).
- PrintBRM (Printer Backup/Restore Migration) native integration.
- Spooler Watchdog scheduled task implementation for high-availability environments.
- System Restore Point native integration for secure pre-execution rollback.
- Detailed operational logging with HTML export capabilities.
