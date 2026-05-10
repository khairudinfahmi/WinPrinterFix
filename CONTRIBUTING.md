# Contributing Guidelines

Thank you for your interest in contributing to the **Windows Printer Sharing Fix** project! 

## How to Contribute

### Reporting Bugs
1. Navigate to the [Issues](https://github.com/khairudinfahmi/WinPrinterFix/issues) tab.
2. Click **New Issue**.
3. Provide a detailed description of the bug:
   - Operating System version/build (e.g., Windows 11 24H2 Build 26100).
   - Exact steps to reproduce the bug.
   - The specific error message encountered.
   - Relevant screenshots or execution logs (`C:\WinPrinterFixLog.txt`).

### Suggesting Enhancements
1. Navigate to the [Issues](https://github.com/khairudinfahmi/WinPrinterFix/issues) tab.
2. Assign the **enhancement** label.
3. Clearly explain the proposed feature and its use case.

### Pull Request Process
1. **Fork** this repository.
2. Create a new feature branch: `git checkout -b feature/your-feature-name`
3. Implement your changes within the `src/` directory.
4. Thoroughly test your changes on Windows 10 and/or Windows 11.
5. Commit your changes: `git commit -m "feat: brief description of changes"`
6. Push to your fork: `git push origin feature/your-feature-name`
7. Submit a **Pull Request** targeting the `main` branch.

## Repository Structure

```text
WinPrinterFix/
├── src/                  # Core PowerShell source code
├── assets/               # Icons and digital certificates
├── docs/                 # HTML offline documentation
├── build/                # Build automation & installer scripts
├── CHANGELOG.md          # Version history
├── CONTRIBUTING.md       # This file
├── LICENSE               # GPL-3.0 License
└── README.md             # Primary documentation
```

## Code Conventions

- **UI Language**: English (User-facing prompts and execution logs).
- **Code Language**: English (Function names, variables, and structural logic).
- **Logging**: use the native `Write-Log` function for all critical operational logging.
- **Error Handling**: Always wrap registry mutations and service state changes within `try/catch` blocks to prevent fatal crashes.
- **Comments**: Maintain clean, descriptive comments for complex logic blocks.

## Commit Conventions

Please adhere to standard Conventional Commits formatting:

```text
feat: description of new feature
fix: description of bug fix
refactor: description of code changes that neither fix a bug nor add a feature
remove: description of removed functionality or files
docs: documentation changes
build: modifications to the build system or external dependencies
```

## Licensing

By contributing to this repository, you agree that your contributions will be licensed under the [GPL-3.0 License](LICENSE).
