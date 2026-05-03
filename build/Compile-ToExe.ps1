<#
.SYNOPSIS
Script untuk mengkonversi WinPrinterFix.ps1 menjadi .exe

.DESCRIPTION
Menggunakan modul PS2EXE yang ada di galeri PowerShell untuk membungkus .ps1
lengkap dengan manifest Administrator sehingga siap deploy dimana saja.

.NOTES
Jalankan script ini dari folder build/ atau dari root project.
Output akan disimpan di folder Output/ pada root project.
#>

# Tentukan root project secara otomatis (parent dari folder build/)
$ProjectRoot = Split-Path $PSScriptRoot -Parent

$SourceFile = Join-Path $ProjectRoot "src\WinPrinterFix.ps1"
$OutputDir  = Join-Path $ProjectRoot "Output"
$OutputFile = Join-Path $OutputDir "WinPrinterFix.exe"
$IconFile   = Join-Path $ProjectRoot "assets\icon.ico"

# Buat folder Output jika belum ada
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Validasi source file
if (-not (Test-Path $SourceFile)) {
    Write-Host "[ERROR] Source file tidak ditemukan: $SourceFile" -ForegroundColor Red
    Write-Host "Pastikan menjalankan script dari dalam folder project WinPrinterFix." -ForegroundColor Yellow
    exit 1
}

Write-Host "Memeriksa modul PS2EXE..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Modul PS2EXE belum terinstal. Menginstal sekarang..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
}

Write-Host "Modul PS2EXE ditemukan." -ForegroundColor Green
Write-Host "Memulai kompilasi $SourceFile menjadi $OutputFile..." -ForegroundColor Cyan

$ps2exeParams = @{
    inputFile   = $SourceFile
    outputFile  = $OutputFile
    requireAdmin = $true
    title       = "Windows Printer Sharing Fix"
    description = "Windows Printer Sharing Fix Tool"
    version     = "1.0.0.0"
    company     = "khairudinfahmi"
    copyright   = "2026 khairudinfahmi"
}

# Tambahkan icon jika ada
if (Test-Path $IconFile) {
    $ps2exeParams.iconFile = $IconFile
}

try {
    Invoke-ps2exe @ps2exeParams
    
    Write-Host "`nKompilasi Sukses!" -ForegroundColor Green
    Write-Host "File EXE ada di: $OutputFile" -ForegroundColor Cyan
} catch {
    Write-Host "Kompilasi Gagal: $_" -ForegroundColor Red
}

Write-Host "`nTekan tombol apa saja untuk keluar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
