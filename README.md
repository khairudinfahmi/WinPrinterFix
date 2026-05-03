# Windows Printer Sharing Fix

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-GPL_3.0-green)
![Features](https://img.shields.io/badge/Features-70-orange)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)

Tool perbaikan otomatis untuk mengatasi **semua masalah sharing printer** di Windows. Mendukung Windows 10, Windows 11 (termasuk 24H2/25H2/26H2), ARM64 (Snapdragon), dan Windows Server 2025.

---

## Kenapa Butuh Tool Ini?

Setelah update Windows, printer sharing sering error dengan kode seperti:
- `0x0000011b` — RPC Authentication gagal
- `0x00000709` — Gagal set default printer / Point and Print diblokir
- `0x00000bc4` — Printer tidak ditemukan
- `0x80070035` — Network path not found
- `0x0000007e` — RPC gagal (beda arsitektur 32/64 bit)
- Dan banyak lagi...

Tool ini memperbaiki **semuanya secara otomatis** dalam satu klik.

---

## Fitur (70 Opsi Perbaikan)

### Error Code Fixes
| # | Fitur |
|---|---|
| 01 | Fix Error 0x0000011b (RpcAuthnLevelPrivacy) |
| 02 | Bypass Error 0x00000709 / 0x7c (Point and Print) |
| 03 | Bypass Error 0x00000bc4 (No Printers Found) |
| 04 | Fix Error 0x80070035 (Network Services) |
| 05 | Matikan Client-Side Rendering (Error 0x6d1) |
| 55 | Fix Error 0x00000040 (Network Unavailable) |
| 56 | Fix Error 0x00000002 (CopyFilesPolicy) |
| 57 | Fix Error 0x0000007e (RPC Bitness Mismatch) |

### Perbaikan Jaringan & Sharing
| # | Fitur |
|---|---|
| 06 | Hard Reset Print Spooler |
| 07 | Buka Akses SMB Guest |
| 08 | Reset Total Network (DNS, Winsock, NetBIOS) |
| 09 | Set Jaringan ke Private |
| 10 | Matikan Password Protected Sharing |
| 11 | Aktifkan RPC via Named Pipes & TCP |
| 12 | Buka Windows Firewall File & Printer Sharing |

### Tools Sistem
| # | Fitur |
|---|---|
| 13 | Backup Registry Sebelum Oprek |
| 14 | Pancing Ulang RPC & DCOM Services |
| 15 | SFC Scannow & DISM |
| 16 | Manajemen Driver (Print Server Properties) |
| 17 | Reset Hak Akses Folder Spooler |

### Kredensial & Manajemen
| # | Fitur |
|---|---|
| 18 | Manajemen Protokol SMB 1.0 (ON/OFF) |
| 19 | Suntik Kredensial Windows ke Vault |
| 20 | Hapus Kredensial dari Windows Vault |
| 21 | Windows Troubleshooter |
| 22 | Paksa Printer Jadi Online |
| 23 | Buka Services.msc |

### Eksekusi & Kontrol
| # | Fitur |
|---|---|
| 24 | Jalur Extreme (Win 11 24H2/25H2 & ARM64) |
| **25** | **ALLFIX - 42 Langkah Perbaikan Otomatis** |
| 26 | Deteksi Versi & Build Windows |
| 27 | Rollback Registry dari Backup |
| 28 | Matikan IPv6 |
| 29 | Generate Laporan Diagnostik HTML |
| 30 | Restart PC |
| 37 | Silent Nuke & AllFix (Tanpa Interaksi) |

### Remote & Diagnostik
| # | Fitur |
|---|---|
| 32 | Test Ping & Port 445/135 |
| 33 | Scan Printer Jarak Jauh |
| 34 | Restart Spooler PC Target |
| 35 | Buka Log Perbaikan |
| 36 | PrintBRM (Backup/Restore Printer) |

### Advanced Tweaks
| # | Fitur |
|---|---|
| 39-54 | SMB Signing, WSD, LSA, SAC, IPP, UAC, NTLMv2, dll |
| 58-70 | WPP, RDP Printer, Hyper-V Fix, LPR/LPD, Print to PDF, Credential Guard, BITS, Restore Point, Diagnostik |

---

## Download

File siap pakai tersedia di tab **[Releases](../../releases)** pada repository ini:

| File | Keterangan |
|---|---|
| `WinPrinterFix.exe` | Portable — langsung jalankan sebagai Admin |
| `WindowsPrinterSharingFix_Installer.exe` | Installer lengkap (dengan shortcut & sertifikat) |

---

## Cara Pakai

### Langkah Cepat (Pemula)
1. Buka tab **[Releases](../../releases)** dan download file instalernya.
2. Jalankan aplikasinya sebagai **Administrator**
3. Ketik `13` → Enter (Backup registry dulu)
4. Ketik `25` → Enter (Jalankan AllFix - 42 langkah otomatis)
5. Restart PC

### Langkah Untuk Windows 11 24H2/25H2
1. Ketik `13` → Backup registry
2. Ketik `24` → Jalur Extreme
3. Restart PC

### Darurat (Tanpa Interaksi)
- Ketik `37` → Silent Nuke (PC akan otomatis restart!)

### Bantuan
- Ketik `?` → Tampilkan panduan
- Ketik `? 7` → Penjelasan detail fitur nomor 7
- Ketik `? all` → Buka dokumentasi HTML lengkap

---

## Menu Tampilan

```
 USER: admin | COMPUTERNAME: PC-KANTOR | OS: WINDOWS 11 PRO 26100 64BIT | Windows Printer Sharing Fix
 ------------------------------------------------------------------------------------------------------------------------

 ERROR CODES & FIXES                                         NETWORK & ADVANCED TWEAKS

 [01] Fix Error 0x0000011b (RpcAuthnLevelPrivacy)            [36] PrintBRM (Backup/Restore)
 [02] Bypass Error 0x00000709 / 0x7c (Point and Print)       [37] SILENT NUKE & ALLFIX (NO PROMPT)
 [03] Bypass Error 0x00000bc4 (No Printers Found)            [38] Hapus Paksa Printer Bermasalah
 ...                                                         ...
 [25] EKSEKUSI ALLFIX (42 LANGKAH SEKALIGUS)                 [70] Diagnostik Sistem

 :   NOTE:                                                                            :
 :   Rekomen Pilih: [25] EKSEKUSI ALLFIX (42 LANGKAH SEKALIGUS - Obat Manjur!)        :
 :   Ketik [?] untuk HELP | [? 7] detail fitur 7 | [? all] buka dokumentasi          :

Type option: _
```

---

## Kompatibilitas

| OS | Status |
|---|---|
| Windows 10 (semua build) | Didukung |
| Windows 11 21H2 - 23H2 | Didukung |
| Windows 11 24H2 / 25H2 / 26H2 | Didukung (Jalur Extreme) |
| Windows 11 ARM64 (Snapdragon) | Didukung |
| Windows Server 2019 / 2022 / 2025 | Didukung |

---

## Build dari Source

### Prasyarat
- Windows 10/11
- PowerShell 5.1+
- Modul [ps2exe](https://www.powershellgallery.com/packages/ps2exe) (otomatis diinstall)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (untuk build installer)

### Compile ke EXE

```powershell
# Dari root project, jalankan:
.\build\Compile-ToExe.ps1
```

Atau compile manual:
```powershell
# Install modul ps2exe (jika belum)
Install-Module -Name ps2exe -Force -Scope CurrentUser

# Compile
Invoke-ps2exe -inputFile src\WinPrinterFix.ps1 -outputFile Output\WinPrinterFix.exe `
    -iconFile assets\icon.ico -requireAdmin `
    -title "Windows Printer Sharing Fix" -company "khairudinfahmi"
```

### Build Installer

```powershell
# Pastikan WinPrinterFix.exe sudah ada di Output/
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\installer.iss
```

---

## Struktur Project

```
WinPrinterFix/
├── src/
│   └── WinPrinterFix.ps1                      # Source code utama (70 fitur)
├── assets/
│   ├── icon.ico                                # Icon aplikasi
│   └── khairudinfahmi_cert.cer                 # Sertifikat code signing
├── docs/
│   └── dokumentasi.html                        # Dokumentasi offline (HTML)
├── build/
│   ├── Compile-ToExe.ps1                       # Script otomasi compile ke EXE
│   └── installer.iss                           # Script Inno Setup installer
├── .gitignore
├── CHANGELOG.md                                # Riwayat perubahan
├── CONTRIBUTING.md                             # Panduan kontribusi
├── LICENSE                                     # Lisensi GPL-3.0
└── README.md                                   # Dokumentasi ini
```

---

## Catatan Penting
- Tool ini **harus dijalankan sebagai Administrator** karena perlu mengubah registry dan mengelola Windows services.
- **Selalu backup registry** (opsi 13) sebelum menjalankan perbaikan.
- Setelah perbaikan, **restart PC** agar perubahan registry aktif.
- Tool ini bekerja **100% offline**, tidak ada koneksi internet yang diperlukan.

---

## Kontribusi

Kontribusi sangat diterima! Silakan baca [CONTRIBUTING.md](CONTRIBUTING.md) untuk panduan lengkap.

---

## License

This project is open-source and free to use under the [GPL-3.0 License](LICENSE).
Feel free to modify and distribute, but please give credit to the original author.

---

## Author

**@khairudinfahmi** — 2026

> Tool ini dibuat untuk membantu teknisi IT dan pengguna biasa yang frustrasi dengan masalah sharing printer di Windows.
