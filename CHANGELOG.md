# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.2.8] - 2026-05-17

### Added
- Added wusa.exe fallback for update uninstalls (Option [69]). If DISM fails, it will try wusa automatically.

### Changed
- Reorganized and aligned the 89-option menu for a cleaner look.
- Sanitized the source code (removed all comments and internal tags).
- Improved error messages for the update uninstaller.

---

## [2.2.7] - 2026-05-17

### Added
- **Remove Injected Port (Option [87])**: Added `Remove-LocalPortUNC` function to safely delete custom ports created by the Titanium Bypass (Option [86]). Includes a Registry Purge fallback if standard removal is blocked by Windows security policies.
- **Titanium Bypass Polish**: Optimized `Map-LocalPortUNC` with improved diagnostic logging and direct registry injection verification.

### Changed
- **Global ID Re-indexing**: Reorganized features into an 89-option architecture.
  - `[87]` Remove Injected Local Port (UNC)
  - `[88]` Reboot System
  - `[89]` EXIT SCRIPT
- **UI Enhancement**: Standardized "Ultimate Bypass" nomenclature across all diagnostic modules for better clarity.

---

## [2.2.6] - 2026-05-17

### Added
- **Registry Bypass for Local Ports**: Significantly enhanced `Map-LocalPortUNC` (Option [86]) with a fallback mechanism. If the standard Windows API for port creation is blocked by RPC security policies, the tool now injects the UNC path directly into the registry and restarts the spooler to force availability.

### Changed
- **Standardized Error Codes**: Expanded all hex error codes to their full 10-character format (e.g., 0x0000011b, 0x00000709) across the entire UI, console logs, and documentation for maximum clarity and enterprise compliance.
- **Professional Language Polish**: Replaced "stiff" or AI-centric terminology (e.g., "mutated", "transmitted", "numerals") with natural, professional technical language ("updated", "issued", "numbers") to ensure a polished user experience.
- **Function Standardization**: Renamed core repair functions to include their corresponding error codes (e.g., Fix-11b -> Fix-RpcAuthn0x0000011b) for better developer traceability and maintenance.
- **Code Refactoring**: Cleaned up internal documentation and removed redundant debug comments to improve script readability and performance.
- **Improved Spooler Management**: Optimized the spooler refresh logic to ensure a cleaner state transition between service stop and start operations.

---

## [2.2.5] - 2026-05-17

### Added
- **Ultimate Bypass (Option [86])**: Added `Map-LocalPortUNC` function. This allows users to map a local port directly to a UNC path (`\\TargetIP\ShareName`), effectively bypassing persistent RPC "Check printer name" or "0x709" errors when standard sharing protocols fail.
- **Enhanced PrintNightmare Bypasses**: Expanded `Fix-AdvancedPointAndPrint` (Option [56]) with critical registry overrides (`RestrictDriverInstallationToAdministrators = 0`, `NoWarningNoElevationOnInstall = 1`, etc.). This enables silent driver downloads from host machines even under strict modern security policies.
- **AllFix Sequence Markers**: Added visual menu-mapping hints (e.g., `(Menu 64)`) to each step in the `AllFix-Core` sequence, allowing users to trace which individual fix corresponds to each automated step.

### Fixed
- **Spooler Resilience**: Added explicit `Set-Service spooler -StartupType Automatic` during the Spooler Hard Reset (Option [31]) to ensure the service persists after a reboot.
- **SMB Mutual Auth**: Added `RequireMutualAuthentication = 0` to `Fix-SMBSigning` (Option [16]) to ensure smooth NTLM fallback for workgroup environments.
- **Network Discovery Hardening**: Integrated `nlasvc` (Network List Service) and `Dnscache` into `Fix-NetworkServices` (Option [04]) to ensure reliable profile detection.
- **Directory ACL**: Expanded `Reset-SpoolerPerm` (Option [06]) to grant "Everyone" FullControl on the spooler directory, resolving persistent permission-based sharing blocks.
- **UI & Feature Expansion**: Updated the toolkit to **88 options**. Reindexed "Reboot" and "Exit" to options [87] and [88] respectively.

---

## [2.2.3] - 2026-05-16

### Fixed
- **GPO Synchronization**: Moved `gpupdate /force` to the beginning of the `AllFix-Core` and `Extreme-25H2` sequences. This prevents domain-joined machines from reverting registry fixes immediately after script execution.
- **Sequence Integrity**: Standardized the `AllFix-Core` sequence to a consistent 50-step repair flow, correcting duplicate numbering and inconsistent step labels.
- **Error 0x00000709 (HKCU Permissions)**: Added `Fix-HKCU-PrinterKeyPerms` to grant FullControl to the printer registry key. This resolves "Access Denied" errors when writing to the Device key during printer assignment.
- **Print Migration (Home Edition Compatibility)**: Added validation for `PrintBrm.exe` existence. The tool now correctly identifies when the utility is missing (common in Windows Home editions) and provides a clear informative message instead of a CLI error.
- **Code Optimization**: Removed the legacy `Fix-709` dead code function, fully transitioning to the multi-layered `Fix-709-Deep` implementation.

### Added
- **KB5089549 Driver Bypass**: Implemented `Fix-CrossSignedDriverPolicy` to disable the new cross-signed driver enforcement (Audit Mode) introduced in the May 2026 patch.
- **Post-Update Automation**: Integrated `Set-PostPatchTuesdayTask`, which deploys a scheduled task (`PrinterFixPostUpdate`) to automatically re-apply critical registry fixes after Windows Updates or reboots.
- **Enhanced KB List**: Updated `Manage-WindowsUpdate` with a curated list of known printer-breaking KBs from 2025-2026.

## [2.2.2] - 2026-05-16

### Added
- **Deep Fix 0x00000709**: Integrated a new multi-layered repair logic (Option [02]) targeting persistent 0x00000709 errors. Includes RPC Named Pipe enforcement, Kerberos disabling (`ForceKerberosForRpc=0`), and HKCU device key sanitation.
- **Automated Deep Fix**: Integrated `Fix-709-Deep` into the `AllFix-Core` [84] and `Extreme-25H2` [83] sequences.

## [2.2.1] - 2026-05-16

### Fixed
- **PrintBRM Migration**: Improved the launch logic for `PrintBrm.exe` (Option [81]) to open in a persistent CMD window with the help manual (`/?`) automatically displayed.
- **DISM Capture**: Enhanced DISM uninstallation modules to correctly capture and report exit codes (0/3010) for verification.
- **Windows Update Compliance**: Added robust registry keys (`PauseFeatureUpdatesStartTime`, `PauseUpdatesExpiryTime`) to ensure Windows 11 respects update pauses.
- **WUSA Compatibility**: Removed silent flags from `wusa.exe` uninstalls to resolve security-driven interface blocks on modern builds.
- **UI Alignment**: Standardized console headers for better readability in 80-column terminals.

## [2.2.0] - 2026-05-15

### Changed
- **Feature Optimization**: Removed the non-essential "Auto-Inject F4/Folio Paper Size" feature (previously Option [50]) to streamline the toolkit.
- **Global ID Re-indexing**: Reorganized all features into a strictly sequential 87-option architecture (down from 88). 
- **UX Improvement**: Renamed "Case 2" troubleshooting to "STILL DENIED? (Persistent)" for better user clarity. Added strategic tips for manual credential injection (Option [60]) when automated fixes are blocked by modern Windows 11 security policies.
- **AllFix Sequence**: Adjusted automated repair sequence from 50 to 49 steps.

### Fixed
- **Redundant Code**: Purged legacy F4 injection logic and registry manipulation to reduce script footprint and potential security surface.

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
