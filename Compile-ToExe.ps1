<#
.SYNOPSIS
Script untuk mengkonversi WinPrinterFix.ps1 menjadi .exe

.DESCRIPTION
Menggunakan modul PS2EXE yang ada di galeri PowerShell untuk membungkus .ps1
lengkap dengan manifest Administrator sehingga siap deploy dimana saja.
#>

$SourceFile = "C:\Fix Print All\WinPrinterFix.ps1"
$OutputFile = "C:\Fix Print All\WinPrinterFix.exe"

if (-not (Test-Path "C:\Fix Print All")) {
    New-Item -ItemType Directory -Path "C:\Fix Print All" -Force | Out-Null
}

Write-Host "Memeriksa modul PS2EXE..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Modul PS2EXE belum terinstal. Menginstal sekarang..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
}

Write-Host "Modul PS2EXE ditemukan." -ForegroundColor Green
Write-Host "Memulai kompilasi $SourceFile menjadi $OutputFile..." -ForegroundColor Cyan

try {
    Invoke-ps2exe -inputFile $SourceFile -outputFile $OutputFile -iconFile "C:\Fix Print All\khairudinfahmi.ico" -requireAdmin -title "Windows Printer Sharing Fix" -description "Windows Printer Sharing Fix Tool" -version "1.0.0.0" -company "khairudinfahmi" -copyright "2026"
    
    Write-Host "Kompilasi Sukses! File EXE ada di: $OutputFile" -ForegroundColor Green
} catch {
    Write-Host "Kompilasi Gagal: $_" -ForegroundColor Red
}

Write-Host "`nTekan tombol apa saja untuk keluar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
