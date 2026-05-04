# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-05-04

### Changed
- UI Enhancement: Explicitly highlighted options `[24]` (Red), `[25]` (Yellow), and `[37] SILENT NUKE` (Magenta) in the main CLI menu for better visibility.
- UI Enhancement: Updated the footer "NOTE:" section to explicitly reference the 3 primary operation modes: `[25] ALLFIX`, `[24] EXTREME PATH`, and `[37] SILENT NUKE`.
- Documentation: Updated OS Support requirements to clarify Legacy OS (Windows 7/8/8.1) as "Partial/Registry Support only".
- Documentation: Replaced all emojis in the HTML manual with professional Lucide icons.
- Documentation: Corrected typo in log and backup directory paths (`WinPrinterFixLog.txt` instead of `PrinterFixlog.txt`).
- Features: Explicitly mapped error code `0x80070005` (Access Denied) into Option `[17]` descriptor for easier troubleshooting discovery.

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
