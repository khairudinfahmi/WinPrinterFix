# Panduan Kontribusi

Terima kasih telah tertarik untuk berkontribusi pada **Windows Printer Sharing Fix**!

## Cara Berkontribusi

### Melaporkan Bug
1. Buka tab [Issues](https://github.com/khairudinfahmi/WinPrinterFix/issues)
2. Klik **New Issue**
3. Jelaskan bug dengan detail:
   - Versi Windows yang digunakan (misal: Windows 11 24H2 Build 26100)
   - Langkah untuk mereproduksi bug
   - Error message yang muncul
   - Screenshot jika memungkinkan

### Mengusulkan Fitur Baru
1. Buka tab [Issues](https://github.com/khairudinfahmi/WinPrinterFix/issues)
2. Beri label **enhancement**
3. Jelaskan fitur yang diinginkan dan alasannya

### Pull Request
1. **Fork** repository ini
2. Buat branch baru: `git checkout -b fitur/nama-fitur`
3. Lakukan perubahan pada file di folder `src/`
4. Test perubahan di Windows 10 dan/atau Windows 11
5. Commit: `git commit -m "Tambah: deskripsi singkat perubahan"`
6. Push: `git push origin fitur/nama-fitur`
7. Buat **Pull Request** ke branch `main`

## Struktur Project

```
WinPrinterFix/
├── src/                  # Source code PowerShell
├── assets/               # Icon dan sertifikat
├── docs/                 # Dokumentasi HTML
├── build/                # Script compile & installer
├── CHANGELOG.md          # Riwayat perubahan
├── CONTRIBUTING.md       # File ini
├── LICENSE               # Lisensi GPL-3.0
└── README.md             # Dokumentasi utama
```

## Konvensi Kode

- **Bahasa UI**: Indonesia (pesan untuk user)
- **Bahasa kode**: Campuran Indonesia-Inggris (nama fungsi dalam Inggris/campuran)
- **Logging**: Gunakan fungsi `Write-Log` untuk semua operasi penting
- **Error handling**: Selalu wrap operasi registry/service dengan `try/catch`
- **Komentar**: Tulis komentar untuk logika yang kompleks

## Konvensi Commit

```
Tambah: deskripsi fitur baru
Perbaiki: deskripsi bug fix
Ubah: deskripsi perubahan
Hapus: deskripsi item yang dihapus
Docs: perubahan dokumentasi
Build: perubahan build script
```

## Lisensi

Dengan berkontribusi, Anda setuju bahwa kontribusi Anda akan dilisensikan di bawah [GPL-3.0 License](LICENSE).
