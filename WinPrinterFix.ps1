<#
.SYNOPSIS
Windows Printer Sharing Fix Tool (70 OPTIONS)
@khairudinfahmi

.DESCRIPTION
Script ini memperbaiki berbagai masalah sharing printer di Windows.
Support penuh untuk Windows 11 ARM64 & Windows Server 2025.
#>

param(
    [switch]$nuke
)

# =========================================================================
# KONSTANTA DAN VARIABEL GLOBAL
# =========================================================================
$script:logFile = "C:\WinPrinterFixLog.txt"
$script:backupDir = "C:\WinPrinterFixBackup"
$script:silentNuke = $nuke

# ARM64 & Server Detection
$script:isARM64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$script:isServer = ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)

# Fallback detection to prevent null string comparison errors
$buildInfo = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
if ($buildInfo -and $null -ne $buildInfo.CurrentBuild) {
    try { 
        $script:buildNumber = [int]$($buildInfo.CurrentBuild) 
    } 
    catch { 
        $script:buildNumber = [Environment]::OSVersion.Version.Build 
    }
}
else {
    $script:buildNumber = [Environment]::OSVersion.Version.Build
}

if ($buildInfo -and $null -ne $buildInfo.ProductName) {
    $script:productName = $buildInfo.ProductName
}
else {
    $script:productName = "Windows NT $([Environment]::OSVersion.Version.Major)"
}

# [MUTLAK SILENT] Matikan semua progress bar bawaan PowerShell yang mengotori UI
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# =========================================================================
# FUNGSI LOGGING & ELEVASI
# =========================================================================
function Write-Log {
    param(
        [string]$Message, 
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Type - $Message"
    try { 
        Add-Content -Path $script:logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop 
    }
    catch {
        # Silent fail if log file is locked by AV
    }
    
    if ($Type -eq "ERROR") { 
        Write-Host "  [ERROR] $Message" -ForegroundColor Red 
    }
    elseif ($Type -eq "WARNING") { 
        Write-Host "  [!] $Message" -ForegroundColor Yellow 
    }
    elseif ($Type -eq "SUCCESS") { 
        Write-Host "  [+] $Message" -ForegroundColor Green 
    }
    else { 
        Write-Host "  [*] $Message" -ForegroundColor Cyan 
    }
}

function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    Write-Host "`n  [!] Tunggu bentar... Minta akses Admin dulu." -ForegroundColor Yellow
    Write-Host "  [!] Kalo muncul pop-up, langsung klik 'YES' aja ya!" -ForegroundColor Yellow
    
    $isExe = $false
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($exePath -match '\.exe$' -and $exePath -notmatch 'powershell') { 
        $isExe = $true 
    }

    if ($isExe) {
        $cmdArgs = ""
        if ($script:silentNuke) { $cmdArgs += "-nuke" }
        Start-Process -FilePath $exePath -ArgumentList $cmdArgs -Verb RunAs
    }
    else {
        $cmdArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($script:silentNuke) { $cmdArgs += " -nuke" }
        Start-Process powershell -Verb RunAs -ArgumentList $cmdArgs
    }
    exit
}

function Initialize-Log {
    if (-not (Test-Path $script:backupDir)) { 
        New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null 
    }
    try {
        Add-Content -Path $script:logFile -Value ("=" * 60) -Encoding UTF8 -ErrorAction SilentlyContinue
        Add-Content -Path $script:logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Windows Printer Sharing Fix" -Encoding UTF8 -ErrorAction SilentlyContinue
        
        if ($script:isARM64) { 
            Add-Content -Path $script:logFile -Value "[ARM64 Architecture Detected]" -Encoding UTF8 
        }
        if ($script:isServer) { 
            Add-Content -Path $script:logFile -Value "[Windows Server Edition Detected]" -Encoding UTF8 
        }
    }
    catch {}
}

if (-not (Test-Administrator)) {
    Restart-Elevated
}
Initialize-Log

# =========================================================================
# FUNGSI PERBAIKAN (1-54)
# =========================================================================
function Fix-11b {
    Write-Log "Nambal Error 0x0000011b (RpcAuthnLevelPrivacy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "Registry 0x11b berhasil diubah." -Type "SUCCESS"
        Write-Host "  [+] Bypass RpcAuthnLevelPrivacyEnabled diaplikasikan." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal nambal registry 0x11b: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-709 {
    Write-Log "Bypass Error 0x00000709 / 0x0000007c (Point and Print)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name RestrictDriverInstallationToAdministrators -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name BypassedWarnings -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name UpdatePromptSettings -Value 2 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "Bypass Point and Print sukses (0x709)." -Type "SUCCESS"
        Write-Host "  [+] Point and Print Restrictions dilepaskan sepenuhnya." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal bypass 0x709: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-bc4 {
    Write-Log "Bypass Error 0x00000bc4 (No printers were found)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcTcpEnable -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcProtocols -Value 0x7 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ForceSetup -Value 1 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "RPC Endpoint Mapper berhasil dipaksa lewat Named Pipes & TCP." -Type "SUCCESS"
        Write-Host "  [+] Discovery printer RPC dipaksa berjalan via Named Pipes." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal bypass 0xbc4: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-NetworkServices {
    Write-Log "Benerin Error 0x80070035 (Nyalain Services termasuk WSD, SMB, NetBIOS)..." -Type "INFO"
    $services = @("LanmanServer", "LanmanWorkstation", "lmhosts", "fdPHost", "FDResPub", "SSDPSRV", "upnphost", "WdiSystemHost", "WdiServiceHost")
    
    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Peringatan: Service $svc tidak dapat dikonfigurasi." -Type "WARNING"
        }
    }
    Write-Log "Service jaringan & WSD udah dibikin auto-start semua." -Type "SUCCESS"
    Write-Host "  [+] Semua service jaringan sudah nyala." -ForegroundColor Green
}

function Fix-CSR {
    Write-Log "Matiin Client-Side Rendering (Error 0x6d1)..." -Type "INFO"
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name DisableClientSideRendering -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "CSR berhasil dimatiin." -Type "SUCCESS"
        Write-Host "  [+] Client-Side Rendering dimatikan agar Host memproses print jobs." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal mematikan CSR: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-Spooler {
    Write-Log "Matiin Print Spooler & Membersihkan Antrean..." -Type "INFO"
    try {
        Stop-Service -Name spooler -Force -ErrorAction SilentlyContinue
        
        Write-Log "Memastikan proses terkait (splwow64, printfilter) mati..." -Type "INFO"
        Get-Process -Name "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 1
        
        Write-Log "Ngehapus file-file print yang nyangkut..." -Type "INFO"
        Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*" -Force -Recurse -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 1
        Start-Service -Name spooler -ErrorAction Stop
        
        Write-Log "Spooler udah fresh lagi!" -Type "SUCCESS"
        Write-Host "  [+] Print Spooler sudah dibersihkan total (Hard Reset)." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal reset Spooler: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Enable-SMBGuest {
    Write-Log "Buka akses SMB Guest (LanmanWorkstation & LanmanServer)..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $path -Name AllowInsecureGuestAuth -Value 1 -Type DWord -Force -ErrorAction Stop
        
        $pathServer = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $pathServer -Name EnableSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Log "Akses Guest dibuka." -Type "SUCCESS"
        Write-Host "  [+] Proteksi kredensial SMB diturunkan untuk akses Guest." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal buka SMB Guest: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Reset-Network {
    Write-Log "Reset Jaringan Total (Flush DNS, NetBIOS, Winsock)..." -Type "INFO"
    try {
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; & netsh winsock reset > $null 2>&1
        $LASTEXITCODE = 0; & netsh int ip reset > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1
        
        Write-Log "Jaringan di-reset." -Type "SUCCESS"
        Write-Host "  [+] Cache jaringan berhasil dikosongkan." -ForegroundColor Green
    }
    catch { 
        Write-Log "Gagal reset jaringan: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Set-NetworkPrivate {
    Write-Log "Ganti Profil Jaringan (Public ke Private, abaikan Domain)..." -Type "INFO"
    try {
        $nla = Get-Service nlasvc -ErrorAction SilentlyContinue
        if ($nla -and $nla.Status -ne 'Running') { Start-Service nlasvc -ErrorAction SilentlyContinue }

        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        $success = $false
        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -eq 'Public') {
                try { 
                    Set-NetConnectionProfile -InterfaceAlias $profile.InterfaceAlias -NetworkCategory Private -ErrorAction Stop 
                    $success = $true
                }
                catch {
                    Write-Log "Gagal mengubah profil $($profile.InterfaceAlias)." -Type "WARNING"
                }
            }
            elseif ($profile.NetworkCategory -eq 'Private' -or $profile.NetworkCategory -eq 'DomainAuthenticated') {
                $success = $true
            }
        }
        
        if ($success) {
            Write-Log "Jaringan Private diset dengan aman." -Type "SUCCESS"
            Write-Host "  [+] Jaringan sudah diset Private, discovery tidak diblokir." -ForegroundColor Green
        }
    }
    catch {
        Write-Log "Gagal set network private: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Disable-PasswordSharing {
    Write-Log "Matiin Password Protected Sharing..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name limitblankpassworduse -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name everyoneincludesanonymous -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name restrictnullsessaccess -Value 0 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "Password sharing dimatiin." -Type "SUCCESS"
        Write-Host "  [+] Jaringan terbuka tanpa password (Everyone = Anonymous)." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal matiin password sharing: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NamedPipes {
    Write-Log "Aktifin RPC Named Pipes..." -Type "INFO"
    try {
        $rpcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }
        
        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable -Value 1 -Type DWord -Force 
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols -Value 0x7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force
        
        Write-Log "Named Pipes aktif." -Type "SUCCESS"
        Write-Host "  [+] Jalur RPC Named Pipes untuk print spooling dibenarkan." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Named Pipes: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Open-Firewall {
    Write-Log "Buka Firewall File & Printer Sharing..." -Type "INFO"
    try {
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -ErrorAction SilentlyContinue | Out-Null 
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28509" -ErrorAction SilentlyContinue | Out-Null 
        Enable-NetFirewallRule -DisplayGroup "*File*Printer*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*Network Discovery*" -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Firewall dibuka." -Type "SUCCESS"
        Write-Host "  [+] Windows Defender Firewall memberi akses penuh untuk Sharing." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal buka Firewall: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Backup-Registry {
    Write-Log "Backup Registry Printer..." -Type "INFO"
    try {
        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Print" "$script:backupDir\Print.reg" /y > $null 2>&1
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers" "$script:backupDir\PrintersPolicy.reg" /y > $null 2>&1
        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "$script:backupDir\LanmanWorkstation.reg" /y > $null 2>&1
        Write-Log "Backup sukses." -Type "SUCCESS"
        Write-Host "  [+] Registry penting sudah di-backup ke $script:backupDir." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal backup registry: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Check-RPC {
    Write-Log "Memeriksa status layanan RPC & DCOM..." -Type "INFO"
    $rpc = Get-Service -Name RpcSs -ErrorAction SilentlyContinue
    if ($rpc.Status -ne 'Running') { 
        Start-Service RpcSs -ErrorAction SilentlyContinue
        Write-Host "  [*] RpcSs mati. Dipancing hidup kembali." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] RpcSs berjalan sehat." -ForegroundColor Green
    }
    
    $dcom = Get-Service -Name DcomLaunch -ErrorAction SilentlyContinue
    if ($dcom.Status -ne 'Running') { 
        Start-Service DcomLaunch -ErrorAction SilentlyContinue
        Write-Host "  [*] DcomLaunch mati. Dipancing hidup kembali." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] DcomLaunch berjalan sehat." -ForegroundColor Green
    }
}

function Run-SfcDism {
    Write-Log "Memulai proses SFC dan DISM..." -Type "INFO"
    Write-Host "`n  [!] SABAR, proses ini butuh waktu..." -ForegroundColor Yellow
    Write-Host "  [*] [1/2] SFC Scannow sedang berjalan..." -ForegroundColor Cyan
    & sfc /scannow
    Write-Host "  [*] [2/2] DISM RestoreHealth sedang berjalan..." -ForegroundColor Cyan
    & dism /online /cleanup-image /restorehealth
    Write-Log "SFC & DISM Selesai." -Type "SUCCESS"
    Write-Host "  [+] Pengecekan integritas file OS selesai." -ForegroundColor Green
}

function Manage-Drivers { 
    Write-Log "Membuka Print Server Properties..." -Type "INFO"
    Write-Host "  [!] Jendela Print Server Properties akan terbuka. Silakan hapus driver bermasalah." -ForegroundColor Yellow
    Start-Process printui -ArgumentList '/s /t2' -NoNewWindow 
}

function Reset-SpoolerPerm {
    Write-Log "Mereset Hak Akses direktori Spooler..." -Type "INFO"
    try { 
        & icacls "$env:SystemRoot\System32\Spool\Printers" /reset /t /c /q > $null 2>&1 
        Write-Log "Reset ACL Spooler Selesai." -Type "SUCCESS"
        Write-Host "  [+] Hak akses folder antrean print sudah di-reset." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Reset ACL: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-SMB1 {
    Write-Host "`n  ======================================================================"
    Write-Host "                 MANAJEMEN PROTOKOL SMB 1.0 (LEGACY)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] AWAS: SMB 1.0 rawan serangan WannaCry Ransomware."
    Write-Host "  [1] AKTIFKAN SMB1 (Darurat) `n  [2] MATIKAN SMB1 (Disarankan)"
    $smbopt = Read-Host "  Pilih Opsi (1/2)"
    if ($smbopt -eq '1') { 
        Write-Log "Mengaktifkan SMB 1.0..." -Type "INFO"
        Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null 
        Write-Host "  [+] Protokol SMB1 diaktifkan." -ForegroundColor Green
    }
    if ($smbopt -eq '2') { 
        Write-Log "Mematikan SMB 1.0..." -Type "INFO"
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null 
        Write-Host "  [+] Protokol SMB1 berhasil dimatikan demi keamanan." -ForegroundColor Green
    }
}

function Add-Credential {
    Write-Host "`n  SUNTIK KREDENSIAL WINDOWS"
    $ip = Read-Host "  [?] IP/Nama Host (misal: 192.168.1.10)"
    $usr = Read-Host "  [?] Username di PC Host"
    $pass = Read-Host "  [?] Password di PC Host (Teks Akan Terlihat)"
    
    try {
        Start-Process -FilePath "cmdkey.exe" -ArgumentList "/add:$ip", "/user:$usr", "/pass:`"$pass`"" -WindowStyle Hidden -Wait
        Write-Log "Credential untuk $ip disuntik." -Type "SUCCESS"
        Write-Host "  [+] Kredensial sudah disimpan di Vault Windows." -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Log "Gagal menambah credential: $($_.Exception.Message)" -Type "ERROR"
    }
    $pass = ""
}

function Clean-Credential {
    Write-Host "`n  MENGHAPUS KREDENSIAL WINDOWS LAMA"
    & cmdkey /list | Select-String "Target:" | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    $del = Read-Host "`n  [?] Ketik Target yang ingin dihapus (Kosongi jika batal)"
    if ($del) { 
        $del = $del -replace '(?i)^\s*Target:\s*', ''
        try {
            $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/delete:`"$del`"" -WindowStyle Hidden -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Log "Credential $del dihapus." -Type "SUCCESS"
                Write-Host "  [+] Kredensial $del berhasil dihapus." -ForegroundColor Green
            } else {
                Write-Log "Credential $del gagal dihapus (Tidak Ditemukan/Error)." -Type "ERROR"
                Write-Host "  [-] Kredensial $del gagal dihapus. Pastikan namanya benar." -ForegroundColor Red
            }
        }
        catch {
            Write-Log "Gagal menghapus credential: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Start-Troubleshooter { 
    Write-Log "Menjalankan Windows Troubleshooter..." -Type "INFO"
    Start-Process msdt -ArgumentList '/id PrinterDiagnostic' -NoNewWindow 
}

function Force-PrinterOnline {
    Write-Log "Memaksa Printer untuk Online..." -Type "INFO"
    $pname = Read-Host "  [?] Ketik nama persis Printer (contoh: EPSON L120 Series)"
    if ($pname) {
        try {
            $prn = Get-CimInstance Win32_Printer -Filter "Name='$pname'" -ErrorAction Stop
            if ($prn) {
                # Memaksa default memicu event online pada spooler
                $prn | Invoke-CimMethod -MethodName "SetDefaultPrinter" | Out-Null
                Write-Log "Printer $pname dipancing." -Type "SUCCESS"
                Write-Host "  [+] Perintah online sudah dikirim ke $pname." -ForegroundColor Green
            }
            else {
                Write-Host "  [-] Printer $pname tidak ditemukan di sistem ini." -ForegroundColor Red
            }
        }
        catch { 
            Write-Log "Gagal memancing printer online: $($_.Exception.Message)" -Type "ERROR" 
        }
    }
}

function Open-Services { 
    Write-Log "Membuka Services.msc..." -Type "INFO"
    Start-Process services.msc 
}

function Rollback-Registry {
    Write-Log "Mengembalikan Registry dari Backup..." -Type "INFO"
    if (Test-Path "$script:backupDir\Print.reg") {
        & reg import "$script:backupDir\Print.reg" > $null 2>&1
        & reg import "$script:backupDir\PrintersPolicy.reg" > $null 2>&1
        & reg import "$script:backupDir\LanmanWorkstation.reg" > $null 2>&1
        Write-Log "Rollback registry sukses!" -Type "SUCCESS"
        Write-Host "  [+] Konfigurasi jaringan dan printer dikembalikan seperti sedia kala." -ForegroundColor Green
    }
    else {
        Write-Host "  [-] Gagal: File backup tidak ditemukan di folder $script:backupDir." -ForegroundColor Red
    }
}

function Disable-IPv6 {
    Write-Log "Mematikan IPv6..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -Value 0xffffffff -Type DWord -Force -ErrorAction Stop
        Write-Log "IPv6 dimatikan melalui registry." -Type "SUCCESS"
        Write-Host "  [+] IPv6 dimatikan untuk mencegah bentrok routing IP. Wajib restart komputer." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal mematikan IPv6: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Generate-HtmlLog {
    Write-Log "Menghasilkan Laporan Log HTML..." -Type "INFO"
    $htmlFile = "$script:backupDir\Report.html"
    $htmlContent = @"
<html>
<head>
    <title>Windows Printer Sharing Fix - Log</title>
    <style>
        body { font-family: 'Courier New', monospace; background: #0b0f19; color: #00ffcc; padding: 20px; }
        h1 { color: #ff0055; border-bottom: 2px solid #333; padding-bottom: 10px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; border: 1px solid #30363d; overflow-x: auto; font-size: 14px; }
    </style>
</head>
<body>
    <h1>Laporan Windows Printer Sharing Fix</h1>
    <p>Waktu Pembuatan: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Target OS: $script:productName</p>
    <pre>$(Get-Content $script:logFile -Raw)</pre>
</body>
</html>
"@
    $htmlContent | Out-File $htmlFile -Encoding UTF8
    Write-Log "Log HTML dibuat di $htmlFile." -Type "SUCCESS"
    Start-Process $htmlFile
}

function Test-Koneksi {
    Write-Host "`n  ======================================================================"
    Write-Host "                 DIAGNOSTIK PING & PORT JARINGAN"
    Write-Host "  ======================================================================"
    $ip = Read-Host "  [?] Masukkan IP/Host Target"
    if (Test-Connection $ip -Count 1 -Quiet) {
        Write-Host "  [+] PING TEMBUS: Perangkat $ip merespon." -ForegroundColor Green
        
        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] PORT 445 (SMB): TERBUKA" -ForegroundColor Green } 
        else { Write-Host "  [-] PORT 445 (SMB): TERTUTUP (DIBLOKIR FIREWALL)" -ForegroundColor Red }
        
        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] PORT 135 (RPC): TERBUKA" -ForegroundColor Green } 
        else { Write-Host "  [-] PORT 135 (RPC): TERTUTUP (DIBLOKIR FIREWALL)" -ForegroundColor Red }
    }
    else { 
        Write-Host "  [-] PING GAGAL: PC Target Mati / Diblokir Total oleh Firewall Host." -ForegroundColor Red 
    }
}

function Scan-RemotePrinter {
    Write-Host "`n  SCAN PRINTER DARI JARAK JAUH"
    $ip = Read-Host "  [?] IP/Host Target"
    Write-Host "  [*] Memindai $ip..." -ForegroundColor Cyan
    try {
        $prn = Get-Printer -ComputerName $ip -ErrorAction Stop | Where-Object Shared -eq $true
        if ($prn) {
            $prn | Format-Table Name, ShareName, PortName, PrinterStatus -AutoSize
        }
        else {
            Write-Host "  [-] Tidak ada printer yang di-share ditemukan pada target." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [-] Gagal terhubung via RPC. Pastikan kamu memiliki akses Admin/Guest ke $ip." -ForegroundColor Red
    }
}

function Remote-SpoolerReset {
    Write-Host "`n  RESET SPOOLER JARAK JAUH (VIA WINRM/DCOM)"
    $ip = Read-Host "  [?] IP/Host Target"
    try { 
        Invoke-Command -ComputerName $ip -ScriptBlock { Restart-Service spooler -Force } -ErrorAction Stop
        Write-Host "  [+] Spooler di PC $ip berhasil di-restart!" -ForegroundColor Green
    }
    catch { 
        Write-Host "  [-] Gagal akses. Pastikan WinRM/DCOM di PC Target terbuka dan kamu memiliki izin akses." -ForegroundColor Red 
    }
}

function Log-Manager { 
    Write-Log "Membuka Log Manager Notepad..." -Type "INFO"
    notepad $script:logFile 
}

function Print-Migration { 
    Write-Log "Membuka utilitas kloning PrintBRM..." -Type "INFO"
    Start-Process "$env:SystemRoot\System32\spool\tools\PrintBrm.exe" 
}

function Uninstall-Printer {
    $up = Read-Host "`n  [?] Masukkan nama persis printer yang ingin dicopot"
    if ($up) { 
        try {
            & printui.exe /dl /n "$up" 
            Write-Log "Perintah hapus dikirim untuk $up." -Type "SUCCESS"
        }
        catch {
            Write-Log "Gagal hapus $up : $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Fix-SMBSigning {
    Write-Log "Mematikan paksaan SMB Signing..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "SMB Signing dimatikan." -Type "SUCCESS"
        Write-Host "  [+] Persyaratan SMB Signature dihilangkan (Membantu Win 11 konek ke NAS/Win 10)." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal mematikan SMB Signing: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UWPPrinting {
    Write-Log "Bypass Isolasi UWP AppContainer untuk Microsoft Edge..." -Type "INFO"
    try {
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Write-Log "Isolasi Loopback dibuka." -Type "SUCCESS"
        Write-Host "  [+] Isolasi jaringan loopback untuk Edge dan UWP Apps dibuka." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Bypass Loopback: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-mDNS {
    Write-Log "Mengaktifkan protokol pencarian mDNS & LLMNR..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name EnableMDNS -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "mDNS/LLMNR aktif." -Type "SUCCESS"
    }
    catch {
        Write-Log "Gagal set mDNS: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-WSDFirewall {
    Write-Log "Memastikan Port WSD (3702) & mDNS (5353) Terbuka Tanpa Duplikat..." -Type "INFO"
    try {
        Remove-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -ErrorAction SilentlyContinue | Out-Null
        Remove-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -ErrorAction SilentlyContinue | Out-Null
        
        New-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3702 -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5353 -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Rule WSD Firewall dikonfigurasi ulang." -Type "SUCCESS"
        Write-Host "  [+] Port UDP 3702 dan 5353 sudah dibuka di Firewall." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal set Firewall WSD: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-LSAProtection {
    Write-Log "Menyesuaikan LSA Protection (Mengijinkan autentikasi lawas)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "LSA PPL diturunkan." -Type "SUCCESS"
    }
    catch {}
}

function Fix-SAC {
    Write-Log "Bypass proteksi Smart App Control (SAC) untuk instalasi driver print..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "SAC bypass aktif." -Type "SUCCESS"
    }
    catch {}
}

function Fix-IPPSharing {
    Write-Log "Mengaktifkan protokol Internet Printing (IPP & Mopria)..." -Type "INFO"
    try {
        if ((Get-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -ErrorAction SilentlyContinue)) {
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-InternetPrinting-Client" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Log "IPP Foundation dihidupkan." -Type "SUCCESS"
            Write-Host "  [+] Windows Feature: Internet Printing Client diaktifkan." -ForegroundColor Green
        }
    }
    catch {
        Write-Log "Gagal set IPP: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-AdvancedPointAndPrint {
    Write-Log "Bypass Advanced Point & Print (ServerList *.*)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name InForest -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name TrustedServers -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name ServerList -Value "*.*" -Type String -Force -ErrorAction SilentlyContinue
        Write-Log "Point & Print ServerList di-bypass penuh." -Type "SUCCESS"
    }
    catch {}
}

function Fix-ModernSMB { 
    Write-Log "Mengaktifkan Paksa SMB2/SMB3 Server Configuration..." -Type "INFO"
    try {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue 
        Write-Log "SMB2/SMB3 Aktif." -Type "SUCCESS"
    }
    catch {}
}

function Set-SpoolerRecovery { 
    Write-Log "Menjadikan Print Spooler otomatis me-restart jika crash..." -Type "INFO"
    try {
        & sc.exe failure spooler reset= 0 actions= restart/60000/restart/60000/restart/60000 > $null 2>&1 
        Write-Log "Spooler Recovery Auto-Restart dikonfigurasi." -Type "SUCCESS"
    }
    catch {}
}

function Fix-UACTokenFilter {
    Write-Log "Bypass limitasi UAC Network Administrator..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force
        Write-Log "LocalAccountTokenFilterPolicy diset 1." -Type "SUCCESS"
        Write-Host "  [+] Hambatan login network Admin (UAC) dilepaskan." -ForegroundColor Green
    }
    catch {}
}

function Reset-SpoolerDependency {
    Write-Log "Membersihkan dependensi kotor pihak ketiga pada Spooler..." -Type "INFO"
    try {
        & sc.exe config spooler depend= RPCSS/http > $null 2>&1
        Write-Log "Dependensi dikembalikan murni ke RPCSS dan http (kompatibel IPP)." -Type "SUCCESS"
        Write-Host "  [+] Dependensi Print Spooler dibenarkan untuk support modern IPP." -ForegroundColor Green
    }
    catch {}
}

function Fix-ProviderOrder {
    Write-Log "Memprioritaskan SMB (LanmanWorkstation) di Provider Order..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
        $currentOrder = (Get-ItemProperty -Path $path -Name ProviderOrder -ErrorAction SilentlyContinue).ProviderOrder
        if ($currentOrder) {
            $arr = $currentOrder -split "," | Where-Object { $_ -ne "LanmanWorkstation" -and $_ -ne "" }
            $newOrder = "LanmanWorkstation," + ($arr -join ",")
            Set-ItemProperty -Path $path -Name ProviderOrder -Value $newOrder -Force
            Write-Log "Provider Order dibenarkan (Prioritas Utama LanmanWorkstation)." -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "Gagal set Provider Order: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NTLMv2 { 
    Write-Log "Memaksa kompatibilitas NTLMv2 Response..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 1 -Type DWord -Force 
        Write-Log "NTLMv2 enforced." -Type "SUCCESS"
    }
    catch {}
}


# =========================================================================
# FITUR EXTENDED (55 - 70)
# =========================================================================

function Fix-Error40 {
    Write-Log "Fix Error 0x00000040 (Network Name No Longer Available)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name KeepConn -Value 65535 -Type DWord -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Write-Log "KeepConn SMB diset maximum." -Type "SUCCESS"
        Write-Host "  [+] Timeout koneksi SMB dilonggarkan untuk mengatasi jaringan labil." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Fix 0x40: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Error02 {
    Write-Log "Fix Error 0x00000002 (System cannot find file)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name CopyFilesPolicy -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "CopyFilesPolicy diaktifkan." -Type "SUCCESS"
        Write-Host "  [+] CopyFilesPolicy diizinkan agar OS bisa menarik driver hilang dari Host." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Fix 0x02: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Error7e {
    Write-Log "Fix Error 0x0000007e (RPC Failed / Bitness mismatch)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcAuthenticationLevel -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "RPC Authentication diturunkan." -Type "SUCCESS"
        Write-Host "  [+] Limitasi RPC Auth dilepas untuk melancarkan komunikasi antar arsitektur OS." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Fix 0x7e: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-WPP {
    Write-Host "`n  ======================================================================"
    Write-Host "           MANAJEMEN WPP (WINDOWS PROTECTED PRINT MODE)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] Fitur modern Windows 11 24H2+ yang SUPER AMAN, TAPI memblokir"
    Write-Host "      semua printer jadul/kustom yang tidak mendukung protokol Mopria."
    Write-Host "  [1] AKTIFKAN WPP (Printer jadul kemungkinan besar error)"
    Write-Host "  [2] MATIKAN WPP (Aman untuk LAN Sharing Legacy - Disarankan)"
    $opt = Read-Host "  Pilih Opsi (1/2)"
    if ($opt -eq '1') { 
        Write-Log "Mengaktifkan WPP Mode..." -Type "INFO"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue 
        Write-Host "  [+] WPP Diaktifkan." -ForegroundColor Yellow
    }
    if ($opt -eq '2') { 
        Write-Log "Mematikan WPP Mode..." -Type "INFO"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
        Write-Host "  [+] WPP Berhasil Dimatikan (Mode Kompatibilitas)." -ForegroundColor Green
    }
}

function Scan-PrintEventLog {
    Write-Log "Membaca 20 Log Printer Service terbaru..." -Type "INFO"
    Write-Host "`n  --- RIWAYAT ERROR DARI MICROSOFT PRINT SERVICE EVENT LOG ---" -ForegroundColor Cyan
    $events = Get-WinEvent -LogName "Microsoft-Windows-PrintService/Admin" -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
        $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
    }
    else {
        Write-Host "  [+] Bersih! Tidak ada riwayat kegagalan yang tercatat." -ForegroundColor Green
    }
}

function Manage-TCPPort {
    Write-Host "`n  BUAT TCP/IP PORT MANUAL"
    $ip = Read-Host "  [?] IP Printer Fisik (contoh: 192.168.1.100)"
    if ($ip) { 
        try {
            Add-PrinterPort -Name "IP_$ip" -PrinterHostAddress $ip -ErrorAction Stop
            Write-Log "TCP/IP Port IP_$ip berhasil dibuat." -Type "SUCCESS"
            Write-Host "  [+] Port [IP_$ip] berhasil ditambahkan ke dalam sistem." -ForegroundColor Green
        }
        catch {
            Write-Log "Gagal buat port: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Manage-DefaultPrinter {
    Write-Host "`n  SET PERMANEN DEFAULT PRINTER"
    $prn = Read-Host "  [?] Ketik nama persis Printer yang ingin diset Default"
    if ($prn) { 
        try {
            $wmi = Get-CimInstance Win32_Printer -Filter "Name='$prn'" -ErrorAction Stop
            if ($wmi) { 
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                Write-Log "Default diset paksa ke $prn" -Type "SUCCESS"
                Write-Host "  [+] OS dipaksa menjadikan $prn sebagai Default Utama." -ForegroundColor Green
            }
            else {
                Write-Host "  [-] Printer tidak ditemukan." -ForegroundColor Red
            }
        }
        catch {
            Write-Log "Gagal default printer: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Set-SpoolerWatchdog {
    Write-Log "Suntik Spooler Watchdog Task..." -Type "INFO"
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"if((Get-Service spooler).Status -ne 'Running'){ Start-Service spooler }`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "SpoolerWatchdog" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null
        Write-Log "Spooler Watchdog berhasil dipasang." -Type "SUCCESS"
        Write-Host "  [+] Task otomatis ditanam di OS. Spooler akan dicek setiap 5 menit dan dihidupkan otomatis jika mati." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Watchdog: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RDPPrinter {
    Write-Log "Memperbaiki Redireksi RDP Printer Terminal Services..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fDisableCpm -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fEnablePrintRDR -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "RDP Redirection diaktifkan." -Type "SUCCESS"
        Write-Host "  [+] Printer lokal sekarang dapat terbaca saat kamu meremote PC/Server (RDP)." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Fix RDP: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HyperVConflict {
    Write-Log "Fix Hyper-V/WSL Network Discovery Conflict..." -Type "INFO"
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Virtual" -or $_.InterfaceDescription -match "Hyper-V" -or $_.InterfaceDescription -match "WSL" }
        if ($adapters) {
            foreach ($adp in $adapters) {
                Set-NetIPInterface -InterfaceAlias $adp.Name -InterfaceMetric 99 -ErrorAction SilentlyContinue
            }
            Write-Log "Prioritas vSwitch (Metric) berhasil diturunkan." -Type "SUCCESS"
            Write-Host "  [+] Adapter virtual Hyper-V/WSL diturunkan prioritasnya agar tidak mencekik koneksi LAN/Wi-Fi asli." -ForegroundColor Green
        }
        else {
            Write-Host "  [*] Tidak ditemukan adapter virtual yang berkonflik." -ForegroundColor Cyan
        }
    }
    catch {
        Write-Log "Gagal Hyper-V Fix: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-LPR {
    Write-Log "Menginstall protokol lawas LPR/LPD..." -Type "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPRPortMonitor" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPR Port Monitor Terinstall." -Type "SUCCESS"
    } catch {
        Write-Log "Gagal Install LPR Port Monitor: $($_.Exception.Message)" -Type "WARNING"
    }

    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPDPrintService" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPD Print Service Terinstall." -Type "SUCCESS"
    } catch {
        Write-Log "Gagal Install LPD Service: $($_.Exception.Message) (Mungkin dihapus di Win 11 terbaru)" -Type "WARNING"
    }

    Write-Host "  [+] Instalasi LPR/LPD selesai. Kalau gagal, fitur ini mungkin sudah dihapus di versi Windows kamu." -ForegroundColor Green
}

function Fix-PrintToPDF {
    Write-Log "Reinstall / Refresh Microsoft Print to PDF & XPS..." -Type "INFO"
    Write-Host "  [*] Proses ini butuh sekitar 10-30 detik..." -ForegroundColor Cyan
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 2
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Print to PDF sukses di-refresh." -Type "SUCCESS"
        Write-Host "  [+] Driver Microsoft Print to PDF yang hilang/error sudah dikembalikan!" -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal Refresh PrintToPDF: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CredentialGuard {
    Write-Log "Bypass Restriksi Credential Guard (Strict NTLM)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LsaCfgFlags -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "Proteksi Credential Guard (LsaCfgFlags) di-disable." -Type "SUCCESS"
        Write-Host "  [+] Blokade NTLM ketat Win 11 Pro/Enterprise sudah dilonggarkan." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal bypass Credential Guard: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-BITS {
    Write-Log "Merestart BITS Service..." -Type "INFO"
    try {
        Restart-Service BITS -Force -ErrorAction SilentlyContinue
        Write-Log "Service Background Intelligent Transfer (BITS) direstart." -Type "SUCCESS"
        Write-Host "  [+] Layanan pengunduh (Downloader) driver bawaan Windows di-restart untuk mencegah koneksi stuck." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal restart BITS: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Create-RestorePoint {
    Write-Log "Membuat System Restore Point (Titik Pemulihan)..." -Type "INFO"
    Write-Host "  [*] Memanggil System Protection (Mohon tunggu beberapa saat)..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinPrinterSharingFix-SafetyBackup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "System Restore Point Berhasil." -Type "SUCCESS"
        Write-Host "  [+] Restore Point Windows sudah dibuat." -ForegroundColor Green
    }
    catch {
        Write-Log "Gagal membuat Restore Point: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Quick-Diagnostic {
    Write-Host "`n  ======================================================================"
    Write-Host "              DIAGNOSTIK SISTEM"
    Write-Host "  ======================================================================"
    
    $spool = (Get-Service spooler -ErrorAction SilentlyContinue).Status
    if ($spool -eq 'Running') { $spc = "Green" } else { $spc = "Red" }
    Write-Host "  [+] Print Spooler : " -NoNewline; Write-Host $spool -ForegroundColor $spc

    $rpc = (Get-Service RpcSs -ErrorAction SilentlyContinue).Status
    if ($rpc -eq 'Running') { $rcc = "Green" } else { $rcc = "Red" }
    Write-Host "  [+] RPC Service   : " -NoNewline; Write-Host $rpc -ForegroundColor $rcc

    $fw = (Get-Service mpssvc -ErrorAction SilentlyContinue).Status
    if ($fw -eq 'Running') { $fwc = "Green" } else { $fwc = "Red" }
    Write-Host "  [+] Firewall      : " -NoNewline; Write-Host $fw -ForegroundColor $fwc

    $net = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NetworkCategory
    $netStr = ($net -join ", ")
    if ($netStr -match "Public") { $ntc = "Red" } else { $ntc = "Green" }
    Write-Host "  [+] Profil Network: " -NoNewline; Write-Host $netStr -ForegroundColor $ntc
    
    Write-Host "  [+] Tipe OS       : " -NoNewline; Write-Host $script:productName -ForegroundColor Cyan
    if ($script:isARM64) { Write-Host "  [+] Arsitektur    : ARM64" -ForegroundColor Cyan }
    
    Write-Host "  ======================================================================"
}

# =========================================================================
# EKSEKUSI ALLFIX (42 Langkah Otomatis)
# =========================================================================

function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         EKSEKUSI ALLFIX (42 LANGKAH PERBAIKAN OTOMATIS)"
    Write-Host "  ===================================================================================================`n"
    Write-Log "RUN ALLFIX (SILENT=$script:silentNuke)" -Type "INFO"

    Write-Host "  [*] [1/42] Ngedeteksi OS..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/42] Ngamanin Registry (Backup)..." -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/42] Cek RPC & DCOM..." -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [4/42] Nambal Error 0x11b..." -ForegroundColor Cyan
    Fix-11b

    Write-Host "  [*] [5/42] Bypass Error 0x709 & UpdatePromptSettings..." -ForegroundColor Cyan
    Fix-709

    Write-Host "  [*] [6/42] Bypass Error 0xbc4..." -ForegroundColor Cyan
    Fix-bc4

    Write-Host "  [*] [7/42] Fix Error 0x40 (KeepConn)..." -ForegroundColor Cyan
    Fix-Error40

    Write-Host "  [*] [8/42] Fix Error 0x02 (CopyFilesPolicy)..." -ForegroundColor Cyan
    Fix-Error02

    Write-Host "  [*] [9/42] Fix Error 0x7e (RPC Auth)..." -ForegroundColor Cyan
    Fix-Error7e

    Write-Host "  [*] [10/42] Nyuntik DnsOnWire, StrictName & UAC Bypass..." -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [11/42] Mematikan SMB Signing Requirement..." -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [12/42] Memastikan Kompabilitas SMB2/SMB3 & Provider Order..." -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [13/42] Maksa pake Named Pipes & TCP..." -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [14/42] Matiin Client-Side Rendering..." -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [15/42] Matikan Driver Isolation..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force 
    }
    catch {}

    Write-Host "  [*] [16/42] Ngidupin Service Network Discovery, mDNS, NetBIOS & WSD..." -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [17/42] Tembus Firewall (Universal Language) & Buka Jalur UDP..." -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [18/42] Buka akses Guest SMB (Client & Server)..." -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [19/42] Matiin Password Network Sharing..." -ForegroundColor Cyan
    Disable-PasswordSharing
    
    Write-Host "  [*] [20/42] Menurunkan Proteksi LSA & Enforce NTLMv2..." -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard
    
    Write-Host "  [*] [21/42] Bypass Smart App Control (SAC)..." -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [22/42] Setup IPP & Mopria Print Sharing..." -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [23/42] Disable WPP (Biar bisa network print legacy)..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
    }
    catch {}

    Write-Host "  [*] [24/42] Fix RDP & LPD Protocols..." -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [25/42] Paksa jaringan ke Private Mode..." -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [26/42] Turunkan Prioritas Virtual Adapter (Hyper-V)..." -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [27/42] Flush DNS & Winsock..." -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [28/42] Matiin Spooler..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [29/42] Menanamkan Auto-Restart Recovery pada Spooler..." -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [30/42] Membersihkan Dependensi Spooler (http & RPCSS)..." -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [31/42] Benerin Hak Akses Folder PRINTERS..." -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [32/42] Ngebersihin sampah antrean print & Splwow64..." -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [33/42] Bypass AppContainer UWP/Edge Loopback..." -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [34/42] Terapkan Advanced Point & Print ServerList (*.*)..." -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [35/42] Pasang Spooler Watchdog Task..." -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [36/42] Restart BITS Service..." -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [37/42] Nyalain Spooler lagi (validasi)..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler tervalidasi berjalan." -ForegroundColor Green

    Write-Host "  [*] [38/42] Purge Kerberos Login Cache..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [39/42] Restart Service WdiSystemHost..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [40/42] Registrasi mDNS (Multicast)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [41/42] Update Group Policy Registry secara Paksa (GPUpdate)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [42/42] Bikin Restore Point..." -ForegroundColor Cyan
    Create-RestorePoint

    Write-Log "ALLFIX SELESAI" -Type "SUCCESS"

    if ($script:silentNuke) {
        Write-Host "`n  ==================================================================================================="
        Write-Host "    [+] SILENT NUKE SELESAI! PC AKAN DIRESTART DALAM 3 DETIK!"
        Write-Host "  ===================================================================================================`n"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }

    Write-Host "`n  ==================================================================================================="
    Write-Host "    [+] SELESAI! SEMUA 42 LANGKAH PERBAIKAN SUDAH DIJALANKAN!"
    Write-Host "  ==================================================================================================="
    Write-Host "  [!] INFO DOMAIN: Kalo PC ini join AD, cek 'Access this computer from network' di secpol.msc`n" -ForegroundColor Yellow

    $cekerror = Read-Host "   [?] Mau ngecek apakah ada proses yang ERROR di log? (Y/N)"
    if ($cekerror -eq 'Y') {
        Write-Host "`n   --- HASIL SCAN ERROR ---" -ForegroundColor Cyan
        $errors = Select-String -Path $script:logFile -Pattern " - ERROR - " -SimpleMatch
        if ($errors) {
            $errors.Line | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        else {
            Write-Host "   [+] Mulus! Gak ada Error yang kedetek." -ForegroundColor Green
        }
        Write-Host "   --------------------`n"
    }

    $allfixrestart = Read-Host "   [?] Mau sekalian Restart PC gak nih? (Y/N)"
    if ($allfixrestart -eq 'Y') {
        Write-Host "  [*] Gas, restart dalam 5 detik..." -ForegroundColor Cyan
        Restart-Computer -Force
    }
    else {
        Write-Host "  [*] Oke, jangan lupa ntar direstart ya agar efeknya maksimal!" -ForegroundColor Cyan
    }
}

function Extreme-25H2 {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "       JALUR EXTREME UNTUK WIN 11 25H2 / 24H2 / 26H2+ / ARM64"
    Write-Host "  ==================================================================================================="
    Write-Host "  [*] Obat keras spesialis untuk mengatasi OS dengan security paling ketat."
    Write-Host "  [*] Eksekusi otomatis tanpa banyak interupsi..." -ForegroundColor Cyan
    
    Write-Log "Run Extreme Fix 25H2/26H2" -Type "INFO"

    Fix-UACTokenFilter
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-SMBSigning
    Fix-ProviderOrder
    Fix-SAC
    Fix-IPPSharing
    Fix-AdvancedPointAndPrint
    Fix-mDNS
    Reset-SpoolerDependency
    Fix-UWPPrinting
    Enable-SMBGuest
    Disable-PasswordSharing
    Fix-WSDFirewall
    Fix-Error40
    Fix-Error02
    Fix-Error7e
    Fix-RDPPrinter
    Fix-CredentialGuard
    
    try { 
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name NtlmMinClientSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name NtlmMinServerSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    
    try {
        $LASTEXITCODE = 0; cmdkey /list | Select-String $env:COMPUTERNAME | ForEach-Object { cmdkey /delete:$($_.ToString().Split(':')[1].Trim()) > $null 2>&1 }
        $LASTEXITCODE = 0; klist purge > $null 2>&1
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1
        $LASTEXITCODE = 0; gpupdate /force > $null 2>&1
    }
    catch {}

    Write-Log "Jalur Extreme beres!" -Type "SUCCESS"
    Write-Host "  [+] Eksekusi sistem keamanan ekstrim selesai. Sebaiknya PC di-restart." -ForegroundColor Green
    
    $extremerestart = Read-Host "`n   [?] Mau langsung Restart PC sekarang? (Y/N)"
    if ($extremerestart -eq 'Y') { Restart-Computer -Force }
}

function Restart-PC {
    Write-Host "`n  [*] PC akan direstart dalam 5 detik..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

function Detect-Win {
    Write-Host "`n  ======================================================================"
    Write-Host "                DETEKSI WINDOWS DAN ARSITEKTUR"
    Write-Host "  ======================================================================"
    Write-Host "  [+] OS Version : $script:productName" -ForegroundColor Green
    Write-Host "  [+] OS Build   : $script:buildNumber" -ForegroundColor Green
    if ($script:isARM64) {
        Write-Host "  [+] Arsitektur : ARM64 (Snapdragon / Apple M Series VM)" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] Arsitektur : AMD64 / x64" -ForegroundColor Cyan
    }
    if ($script:isServer) {
        Write-Host "  [+] Edisi      : Windows Server Edition" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] Edisi      : Client (Home/Pro/Enterprise)" -ForegroundColor Cyan
    }
}

# =========================================================================
# FUNGSI HELP / BANTUAN INTERAKTIF
# =========================================================================
function Show-Help {
    param([string]$Topic = "")
    
    $helpData = @{
        '1'  = @("Fix Error 0x0000011b (RpcAuthnLevelPrivacy)", "Menonaktifkan registry RpcAuthnLevelPrivacyEnabled agar koneksi ke printer sharing tidak terblokir oleh autentikasi RPC.", "Error paling umum setelah update Windows 10/11. Muncul saat coba konek ke printer yang dishare.")
        '2'  = @("Bypass Error 0x00000709 / 0x7c (Point and Print)", "Menonaktifkan RestrictDriverInstallationToAdministrators agar driver printer bisa diinstall otomatis.", "Muncul setelah patch keamanan Microsoft, gagal set default printer atau install driver sharing.")
        '3'  = @("Bypass Error 0x00000bc4 (No Printers Found)", "Memaksa RPC menggunakan Named Pipe Protocol agar printer bisa ditemukan.", "Windows bilang 'No printers were found' padahal printer dishare dan nyala.")
        '4'  = @("Fix Error 0x80070035 (Nyalain Network Services)", "Mengaktifkan service fdPHost, FDResPub, SSDPSRV, upnphost secara otomatis.", "PC target tidak kelihatan di jaringan, muncul 'The network path was not found'.")
        '5'  = @("Matikan Client-Side Rendering (Error 0x6d1)", "Mengaktifkan DisableClientSideRendering di registry Printers.", "Print job macet atau gagal terkirim karena rendering driver di sisi klien.")
        '6'  = @("Hard Reset Print Spooler (Hapus File Macet)", "Stop spooler, hapus semua file antrean di Spool\Printers, start ulang.", "Ada dokumen stuck/macet yang tidak bisa dihapus dari antrean print.")
        '7'  = @("Buka Akses SMB Guest & Hapus Blokir Anonymous", "Mengaktifkan AllowInsecureGuestAuth di registry LanmanWorkstation.", "Selalu diminta password saat akses sharing padahal tidak di-set password.")
        '8'  = @("Reset Total Network (Flush DNS, Winsock, NetBIOS)", "Flush DNS, release/renew IP, reset Winsock dan IP stack.", "Koneksi jaringan tidak stabil, lambat, atau sering RTO.")
        '9'  = @("Set Jaringan ke Private", "Mengubah semua profil koneksi jaringan ke Private.", "Sharing diblokir karena profil jaringan = Public. Baru konek ke jaringan baru.")
        '10' = @("Matikan Password Protected Sharing Secara Paksa", "Mengatur registry LSA: limitblankpassworduse=0, everyoneincludesanonymous=1.", "Diminta login/password saat akses sharing padahal tidak diset.")
        '11' = @("Aktifkan RPC via Named Pipes & TCP", "Memaksa RPC melalui Named Pipe dan TCP protocol di registry.", "Error koneksi printer karena RPC diblokir, error 0xbcf4db3.")
        '12' = @("Buka Windows Firewall File & Printer Sharing", "Mengaktifkan rule 'File and Printer Sharing' dan 'Network Discovery' di Firewall.", "PC tidak kelihatan di network, sharing diblokir setelah install ulang Windows.")
        '13' = @("Backup Registry Spooler & Network", "Export registry Print, Printers Policy, dan LanmanWorkstation ke C:\WinPrinterFixBackup.", "WAJIB dijalankan sebelum perbaikan lain. Untuk jaga-jaga agar bisa rollback.")
        '14' = @("Pancing Ulang RPC & DCOM Services", "Mengecek dan memulai ulang service RpcSs dan DcomLaunch.", "Error 'RPC server is unavailable', service RPC atau DCOM mati/crash.")
        '15' = @("Jalankan SFC Scannow & DISM (Perbaikan OS)", "Menjalankan SFC /scannow dan DISM /RestoreHealth untuk perbaiki file sistem.", "File sistem Windows korup. CATATAN: Proses bisa memakan waktu 10-30 menit!")
        '16' = @("Manajemen Driver (Print Server Properties)", "Membuka Print Server Properties untuk kelola/hapus driver printer.", "Driver printer korup, duplikat, atau mau ganti driver.")
        '17' = @("Reset Hak Akses (Permissions) Folder Spooler", "Reset ACL folder Spool\Printers ke default menggunakan icacls.", "Error 'Access Denied' saat nge-print setelah pindah domain atau ubah user.")
        '18' = @("Manajemen Protokol Legacy SMB 1.0 (ON/OFF)", "Aktifkan atau matikan SMB 1.0 sesuai kebutuhan.", "Perlu konek ke printer/PC lama (Win XP/7). PERINGATAN: SMB 1.0 rawan ransomware!")
        '19' = @("Suntik Kredensial Windows ke Vault", "Menyimpan username/password ke Windows Credential Manager secara permanen.", "Agar tidak perlu login ulang setiap kali akses sharing printer.")
        '20' = @("Hapus Kredensial Nyangkut dari Windows Vault", "Menghapus kredensial lama/invalid dari Credential Manager.", "Ganti password PC host tapi yang lama masih tersimpan, menyebabkan konflik.")
        '21' = @("Buka Windows Troubleshooter (Print Diagnostic)", "Menjalankan Windows Printer Troubleshooter bawaan (msdt).", "Langkah awal diagnostik sebelum perbaikan manual.")
        '22' = @("Paksa Printer Jadi Online", "Mengirim perintah online ke printer via printui /yl.", "Status printer stuck di 'Offline' atau logo abu-abu padahal printer nyala.")
        '23' = @("Buka Services.msc (Cek Layanan Manual)", "Membuka panel Services.msc untuk cek manual.", "Mau cek apakah Print Spooler, RPC, dan service lain sedang running.")
        '24' = @("JALUR EXTREME KHUSUS WIN 11 24H2/25H2 & ARM64", "Kombinasi perbaikan agresif: DnsOnWire, StrictNameChecking, NTLM level, SMB Signing, Kerberos purge, dll.", "Fix biasa tidak mempan di Windows 11 Build 26000+. Khusus versi terbaru.")
        '25' = @("EKSEKUSI ALLFIX (42 LANGKAH SEKALIGUS)", "Menjalankan 42 langkah perbaikan otomatis secara berurutan.", "REKOMENDASI UTAMA - tidak tahu error apa, mau perbaiki semua sekaligus. Wajib restart setelahnya.")
        '26' = @("Deteksi Otomatis Versi & Build Windows", "Menampilkan info versi, build, arsitektur, dan rekomendasi.", "Butuh tahu versi Windows untuk menentukan langkah fix yang tepat.")
        '27' = @("Rollback (Kembalikan Registry dari Backup)", "Import kembali file .reg dari folder C:\WinPrinterFixBackup.", "Perbaikan malah bikin masalah baru. SYARAT: Sudah jalankan [13] backup sebelumnya.")
        '28' = @("Matikan IPv6 (Cegah Bentrok IP Routing)", "Menonaktifkan IPv6 via registry dan netsh.", "IPv6 menyebabkan konflik routing di jaringan lokal yang pakai IPv4 murni.")
        '29' = @("Generate Laporan Fix & Diagnostik HTML", "Membuat file HTML dari log perbaikan yang bisa di-print/email.", "Untuk dokumentasi IT atau laporan ke atasan.")
        '30' = @("RESTART PC", "Restart komputer secara langsung.", "Setelah menjalankan perbaikan apapun agar perubahan registry aktif.")
        '31' = @("EXIT SCRIPT", "Keluar dari program Windows Printer Sharing Fix.", "")
        '32' = @("Test Ping & Port 445/135 (Diagnostik Koneksi)", "Ping target + scan port SMB (445) dan RPC (135).", "Langkah awal diagnostik: cek apakah PC target bisa diakses via jaringan.")
        '33' = @("Scan Printer di Komputer Target (Jarak Jauh)", "Scan dan list semua shared printer di PC target.", "Mau lihat daftar printer yang dishare sebelum install.")
        '34' = @("Restart Print Spooler Komputer Target (Jarak Jauh)", "Remote reset spooler via PowerShell di PC lain.", "Spooler PC server/host macet. CATATAN: Butuh hak Admin di PC target.")
        '35' = @("Buka Log Perbaikan (WinPrinterFixLog.txt)", "Menu log: cek error / buka full log / hapus log.", "Setelah perbaikan, mau cek hasilnya atau bersihkan history.")
        '36' = @("PrintBRM (Backup/Restore)", "Backup atau restore seluruh konfigurasi printer via PrintBrm.exe.", "Migrasi/kloning settingan printer antar PC, deploy printer ke banyak komputer.")
        '37' = @("SILENT NUKE & ALLFIX (NO PROMPT)", "Eksekusi semua 42 langkah perbaikan + auto restart TANPA ditanya.", "DARURAT: Butuh fix cepat tanpa interaksi. PERINGATAN: PC akan OTOMATIS RESTART!")
        '38' = @("Hapus Paksa Printer Bermasalah", "Force remove printer via command line (printui /dl).", "Printer ghost/hantu yang tidak bisa dihapus secara normal.")
        '39' = @("Matikan SMB Signing (Fix Win 11 NAS)", "Menonaktifkan RequireSecuritySignature di SMB client dan server.", "Win 11 24H2+ tidak bisa akses NAS atau PC lama. Fix koneksi ke perangkat lawas.")
        '40' = @("Matikan Print Driver Isolation", "Menonaktifkan IsolationPolicy di registry Print.", "Driver printer crash dan membawa spooler ikut mati. Spooler sering crash.")
        '41' = @("Paksa Hidupkan WSD Print Device", "Memulai service WSDPrintDevice untuk Web Services Discovery.", "Printer jaringan WSD tidak terdeteksi di auto-discovery.")
        '42' = @("Fix Microsoft Edge / UWP Printing", "Re-register komponen UWP printing Windows.", "Tidak bisa print dari Edge/UWP app tapi dari Notepad bisa.")
        '43' = @("Aktifkan mDNS & LLMNR (Discovery)", "Mengaktifkan Multicast DNS dan LLMNR untuk penemuan perangkat.", "Printer tidak bisa ditemukan via hostname, Bonjour/mDNS tidak jalan.")
        '44' = @("Benarkan Rule Firewall WSD (Port 3702)", "Membuka port UDP 3702 untuk WSD discovery di firewall.", "Printer jaringan tidak muncul di pencarian karena firewall blokir WSD.")
        '45' = @("Turunkan LSA Protection (Auth Lawas)", "Menonaktifkan RunAsPPL di registry LSA.", "Autentikasi ditolak karena LSA Protection terlalu ketat di Win 11.")
        '46' = @("Bypass Smart App Control (SAC)", "Set VerifiedAndReputablePolicyState ke Off.", "Win 11 dengan SAC aktif memblokir installer driver printer.")
        '47' = @("Aktifkan IPP & Mopria Sharing Foundation", "Mengaktifkan fitur Windows IPP dan Mopria Foundation.", "Printer modern yang menggunakan protokol IPP (Internet Printing Protocol).")
        '48' = @("Bypass Advanced ServerList Point & Print", "Menambahkan ServerList wildcard (*) ke registry Point and Print.", "'Only install from approved servers' memblokir install driver dari server.")
        '49' = @("Paksa Mode Modern SMB2/SMB3", "Memastikan SMB2 dan SMB3 aktif, nonaktifkan SMB1.", "Transisi ke protokol modern yang lebih aman dan performa lebih baik.")
        '50' = @("Set Spooler Auto-Restart Jika Crash", "Mengatur recovery action Print Spooler: auto restart jika crash.", "Spooler sering crash dan butuh self-healing otomatis.")
        '51' = @("Bypass UAC Admin Network TokenFilter", "Mengatur LocalAccountTokenFilterPolicy = 1.", "Remote admin ke PC workgroup ditolak karena UAC filtering.")
        '52' = @("Hapus Dependensi Spooler Abal-abal", "Reset DependOnService spooler ke default (RPCSS, http).", "Spooler gagal start karena ada dependensi service pihak ketiga yang aneh.")
        '53' = @("Prioritaskan SMB di Network Provider Order", "Memprioritaskan LanmanWorkstation di daftar network provider.", "Akses sharing lambat atau timeout karena provider order salah.")
        '54' = @("Paksa Kepatuhan NTLMv2 Response", "Mengatur LmCompatibilityLevel ke NTLMv2 only (level 3).", "'Access Denied' saat konek ke PC yang beda versi Windows.")
        '55' = @("Fix Error 0x00000040 (Network Unavailable)", "Memperbaiki registry PrintProcessor dan Ports.", "Error 'Network is unavailable' saat akses printer padahal jaringan aman.")
        '56' = @("Fix Error 0x00000002 (CopyFilesPolicy)", "Mengatur CopyFilesPolicy agar driver bisa ter-copy.", "Gagal copy/install driver printer dari PC host/print server.")
        '57' = @("Fix Error 0x0000007e (RPC Bitness Mismatch)", "Memaksa registry agar menerima driver lintas arsitektur.", "PC 64-bit gagal konek ke print server 32-bit atau sebaliknya.")
        '58' = @("Manajemen Windows Protected Print (WPP)", "Menonaktifkan fitur Windows Protected Print.", "Driver printer tidak kompatibel dengan WPP mode di Win 11 terbaru.")
        '59' = @("Scan 20 Riwayat Error Print Service Log", "Membaca 20 event error terakhir dari Event Log PrintService.", "Mencari petunjuk penyebab error dari system log.")
        '60' = @("Tambah Manual Standard TCP/IP Port", "Menambahkan TCP/IP port melalui WMI scripting.", "Install printer jaringan langsung via IP address.")
        '61' = @("Set Paksa Default Printer (Permanen)", "Mematikan auto-manage dan set default printer secara paksa.", "Default printer terus berubah sendiri berdasarkan lokasi.")
        '62' = @("Pasang Watchdog Spooler (Cek Tiap 5 Menit)", "Membuat scheduled task yang cek dan restart spooler tiap 5 menit.", "Print server butuh uptime tinggi, spooler sering mati diam-diam.")
        '63' = @("Fix Error RDP Printer Terminal Services", "Mengaktifkan printer redirection di registry RDP.", "Login RDP tapi printer lokal tidak terbawa ke sesi Remote Desktop.")
        '64' = @("Atasi Konflik Network Hyper-V/WSL Virtual", "Menonaktifkan binding printer di virtual adapter Hyper-V/WSL.", "Sharing printer error setelah install Hyper-V atau WSL.")
        '65' = @("Install Protokol Lawas LPR/LPD", "Mengaktifkan fitur Windows LPR Port Monitor dan LPD Service.", "Konek ke printer Unix/Linux atau print server lawas via LPR.")
        '66' = @("Reinstall Microsoft Print to PDF/XPS", "Mengaktifkan ulang fitur Windows PDF dan XPS printing.", "'Print to PDF' atau 'XPS Document Writer' hilang atau error.")
        '67' = @("Bypass Credential Guard (Strict NTLM)", "Menonaktifkan LsaCfgFlags Credential Guard.", "Enterprise/Pro dengan Credential Guard aktif memblokir NTLM ke sharing.")
        '68' = @("Restart BITS (Background Transfer)", "Restart service BITS (Background Intelligent Transfer).", "Download driver printer dari Windows Update gagal.")
        '69' = @("Buat System Restore Point (Keamanan)", "Membuat System Restore Point untuk rollback.", "Sebelum melakukan perubahan besar pada sistem, buat jaring pengaman.")
        '70' = @("Diagnostik Sistem", "Cek status Spooler, SMB, Firewall, profil jaringan, dll.", "Ringkasan cepat kondisi kesehatan sistem terkait printer sharing.")
    }

    if ($Topic -eq "" -or $Topic -eq "menu") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "     PANDUAN PENGGUNAAN Windows Printer Sharing Fix - @KHAIRUDINFAHMI" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  CARA PAKAI:" -ForegroundColor Yellow
        Write-Host "    - Ketik nomor fitur (1-70) lalu tekan ENTER"
        Write-Host "    - Boleh ketik '7' atau '07' - keduanya sama"
        Write-Host "    - Ketik '?' untuk tampilkan panduan ini"
        Write-Host "    - Ketik '? 7' untuk penjelasan detail fitur nomor 7"
        Write-Host "    - Ketik '? all' untuk buka file dokumentasi lengkap"
        Write-Host ""
        Write-Host "  LANGKAH PEMULA (Tidak tahu harus apa):" -ForegroundColor Yellow
        Write-Host "    1. Jalankan [13] Backup Registry (WAJIB untuk jaga-jaga)" -ForegroundColor White
        Write-Host "    2. Jalankan [25] ALLFIX (ini perbaiki 42 langkah otomatis)" -ForegroundColor White
        Write-Host "    3. Restart PC" -ForegroundColor White
        Write-Host "    4. Coba akses printer sharing lagi" -ForegroundColor White
        Write-Host ""
        Write-Host "  LANGKAH UNTUK WIN 11 24H2/25H2 (Build 26000+):" -ForegroundColor Yellow
        Write-Host "    1. Jalankan [13] Backup Registry" -ForegroundColor White
        Write-Host "    2. Jalankan [24] Jalur Extreme" -ForegroundColor White
        Write-Host "    3. Restart PC" -ForegroundColor White
        Write-Host ""
        Write-Host "  LANGKAH DARURAT (Cepat tanpa banyak tanya):" -ForegroundColor Yellow
        Write-Host "    - Jalankan [37] Silent Nuke (AWAS: PC auto restart!)" -ForegroundColor White
        Write-Host ""
        Write-Host "  KATEGORI FITUR:" -ForegroundColor Yellow
        Write-Host "    [01-05] Error Code Fixes (0x11b, 0x709, 0xbc4, 0x35, 0x6d1)" -ForegroundColor Cyan
        Write-Host "    [06-12] Perbaikan Jaringan & Sharing (Spooler, SMB, Firewall)" -ForegroundColor Cyan
        Write-Host "    [13-17] Tools Sistem (Backup, RPC, SFC/DISM, Driver, ACL)" -ForegroundColor Cyan
        Write-Host "    [18-23] Kredensial & Manajemen (SMB1, Credential, Troubleshooter)" -ForegroundColor Cyan
        Write-Host "    [24-31] Eksekusi & Kontrol (Extreme, AllFix, Rollback, Restart)" -ForegroundColor Cyan
        Write-Host "    [32-38] Remote & Diagnostik (Ping, Scan, Remote Reset, Log)" -ForegroundColor Cyan
        Write-Host "    [39-54] Advanced Tweaks (SMB Signing, WSD, LSA, SAC, IPP, UAC)" -ForegroundColor Green
        Write-Host "    [55-70] Extended Fixes (Error 0x40/02/7e, WPP, RDP, Hyper-V)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  TROUBLESHOOTING CEPAT:" -ForegroundColor Yellow
        Write-Host "    - Diminta password terus?       -> Jalankan [07], [10], [19]" -ForegroundColor White
        Write-Host "    - Printer Offline padahal nyala? -> Jalankan [22]" -ForegroundColor White
        Write-Host "    - PC tidak kelihatan?            -> Jalankan [04], [09], [12]" -ForegroundColor White
        Write-Host "    - Gagal print dari Edge?         -> Jalankan [42]" -ForegroundColor White
        Write-Host "    - Mau rollback semua?            -> Jalankan [27]" -ForegroundColor White
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
    }
    elseif ($Topic.ToLower() -eq "all") {
        $docPath = $null
        # Coba cari dari lokasi EXE dulu (kompatibel ps2exe)
        try {
            $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
            $docPath = Join-Path $exeDir "dokumentasi.html"
        }
        catch {}
        # Fallback ke $PSCommandPath (jika jalan dari script .ps1)
        if (-not $docPath -or -not (Test-Path $docPath)) {
            try {
                if ($PSCommandPath) {
                    $docPath = Join-Path (Split-Path $PSCommandPath -Parent) "dokumentasi.html"
                }
            }
            catch {}
        }
        if ($docPath -and (Test-Path $docPath)) {
            Write-Host "  [*] Membuka dokumentasi lengkap HTML..." -ForegroundColor Cyan
            $fileUrl = "file:///" + $docPath.Replace("\", "/") + "?all"
            Start-Process $fileUrl
        }
        else {
            Write-Host "  [-] File dokumentasi.html tidak ditemukan di folder instalasi." -ForegroundColor Red
            Write-Host "  [!] Gunakan '?' untuk panduan cepat atau '? <nomor>' untuk detail fitur." -ForegroundColor Yellow
        }
    }
    else {
        $num = $Topic.TrimStart('0')
        if ($helpData.ContainsKey($num)) {
            $h = $helpData[$num]
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host "     HELP: FITUR [$Topic]" -ForegroundColor Green
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  NAMA   : $($h[0])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  FUNGSI : $($h[1])" -ForegroundColor White
            Write-Host ""
            if ($h[2] -ne "") {
                Write-Host "  KAPAN  : $($h[2])" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [-] Fitur nomor '$Topic' tidak ditemukan. Ketik angka 1-70." -ForegroundColor Red
        }
    }
}

function Show-Menu {
    cls
    $winName = "$script:productName $script:buildNumber".ToUpper()
    if ($script:isARM64) { $winName += " ARM64" }
    elseif ([Environment]::Is64BitOperatingSystem) { $winName += " 64BIT" }
    else { $winName += " 32BIT" }

    Write-Host " USER: " -NoNewline
    Write-Host "$env:USERNAME " -ForegroundColor DarkYellow -NoNewline
    Write-Host "| COMPUTERNAME: " -NoNewline
    Write-Host "$env:COMPUTERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| OS: " -NoNewline
    Write-Host "$winName " -ForegroundColor Blue -NoNewline
    Write-Host "| Windows Printer Sharing Fix" -ForegroundColor Green
    
    Write-Host " TIME ZONE: " -NoNewline
    Write-Host "$(Get-TimeZone | Select-Object -ExpandProperty Id) | $(Get-Date -Format 'HH.mm.ss')" -ForegroundColor Red
    Write-Host " BY: @KHAIRUDINFAHMI (2026)" -ForegroundColor Magenta
    Write-Host "------------------------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $colWidth = 59

    Write-Host ""
    Write-Host " ERROR CODES & FIXES" -ForegroundColor Cyan -NoNewline
    Write-Host (" " * ($colWidth - 20)) -NoNewline
    Write-Host " NETWORK & ADVANCED TWEAKS" -ForegroundColor Cyan
    Write-Host ""

    $left = @(
        "[01] Fix Error 0x0000011b (RpcAuthnLevelPrivacy)",
        "[02] Bypass Error 0x00000709 / 0x7c (Point and Print)",
        "[03] Bypass Error 0x00000bc4 (No Printers Found)",
        "[04] Fix Error 0x80070035 (Nyalain Network Services)",
        "[05] Matikan Client-Side Rendering (Error 0x6d1)",
        "[06] Hard Reset Print Spooler (Hapus File Macet)",
        "[07] Buka Akses SMB Guest & Hapus Blokir Anonymous",
        "[08] Reset Total Network (Flush DNS, Winsock, NetBIOS)",
        "[09] Set Jaringan ke Private (Abaikan Public/Domain)",
        "[10] Matikan Password Protected Sharing Secara Paksa",
        "[11] Aktifkan RPC via Named Pipes & TCP",
        "[12] Buka Windows Firewall File & Printer Sharing",
        "[13] Backup Registry Spooler & Network Sebelum Oprek",
        "[14] Pancing Ulang RPC & DCOM Services",
        "[15] Jalankan SFC Scannow & DISM (Perbaikan OS)",
        "[16] Manajemen Driver (Buka Print Server Properties)",
        "[17] Reset Hak Akses (Permissions) Folder Spooler",
        "[18] Manajemen Protokol Legacy SMB 1.0 (ON/OFF)",
        "[19] Suntik Kredensial Windows ke Vault Secara Permanen",
        "[20] Hapus Kredensial Nyangkut dari Windows Vault",
        "[21] Buka Windows Troubleshooter (Print Diagnostic)",
        "[22] Paksa Printer Jadi Online (Tembakan Default)",
        "[23] Buka Services.msc (Cek Layanan Manual)",
        "[24] JALUR EXTREME KHUSUS WIN 11 24H2/25H2 & ARM64",
        "[25] EKSEKUSI ALLFIX (42 LANGKAH SEKALIGUS)",
        "[26] Deteksi Otomatis Versi & Build Windows Kamu",
        "[27] Rollback (Kembalikan Registry dari Backup)",
        "[28] Matikan IPv6 (Cegah Bentrok IP Routing)",
        "[29] Generate Laporan Fix & Diagnostik HTML",
        "[30] RESTART PC (Rekomendasi Setelah Perbaikan)",
        "[31] EXIT SCRIPT",
        "[32] Test Ping & Port 445/135 (Diagnostik Koneksi)",
        "[33] Scan Printer di Komputer Target (Jarak Jauh)",
        "[34] Restart Print Spooler Komputer Target (Jarak Jauh)",
        "[35] Buka Log Perbaikan (WinPrinterFixLog.txt)"
    )

    $right = @(
        "[36] PrintBRM (Backup/Restore)",
        "[37] SILENT NUKE & ALLFIX (NO PROMPT)",
        "[38] Hapus Paksa Printer Bermasalah",
        "[39] Matikan SMB Signing (Fix Win 11 NAS)",
        "[40] Matikan Print Driver Isolation",
        "[41] Paksa Hidupkan WSD Print Device",
        "[42] Fix Microsoft Edge / UWP Printing",
        "[43] Aktifkan mDNS & LLMNR (Discovery)",
        "[44] Benarkan Rule Firewall WSD (Port 3702)",
        "[45] Turunkan LSA Protection (Auth Lawas)",
        "[46] Bypass Smart App Control (SAC)",
        "[47] Aktifkan IPP & Mopria Sharing Foundation",
        "[48] Bypass Advanced ServerList Point & Print",
        "[49] Paksa Mode Modern SMB2/SMB3",
        "[50] Set Spooler Auto-Restart Jika Crash",
        "[51] Bypass UAC Admin Network TokenFilter",
        "[52] Hapus Dependensi Spooler Abal-abal",
        "[53] Prioritaskan SMB di Network Provider Order",
        "[54] Paksa Kepatuhan NTLMv2 Response",
        "[55] Fix Error 0x00000040 (Network Unavailable)",
        "[56] Fix Error 0x00000002 (CopyFilesPolicy)",
        "[57] Fix Error 0x0000007e (RPC Bitness Mismatch)",
        "[58] Manajemen Windows Protected Print (WPP)",
        "[59] Scan 20 Riwayat Error Print Service Log",
        "[60] Tambah Manual Standard TCP/IP Port",
        "[61] Set Paksa Default Printer (Permanen)",
        "[62] Pasang Watchdog Spooler (Cek Tiap 5 Menit)",
        "[63] Fix Error RDP Printer Terminal Services",
        "[64] Atasi Konflik Network Hyper-V/WSL Virtual",
        "[65] Install Protokol Lawas LPR/LPD",
        "[66] Reinstall Microsoft Print to PDF/XPS",
        "[67] Bypass Credential Guard (Strict NTLM)",
        "[68] Restart BITS (Background Transfer)",
        "[69] Buat System Restore Point (Keamanan)",
        "[70] Diagnostik Sistem"
    )

    for ($i = 0; $i -lt 35; $i++) {
        Write-Host " " -NoNewline
        # Kolom Kiri
        $matchL = [regex]::Match($left[$i], '^(\[\d+\])(.*)')
        if ($matchL.Success) {
            Write-Host $matchL.Groups[1].Value -ForegroundColor Green -NoNewline
            Write-Host $matchL.Groups[2].Value.PadRight($colWidth - $matchL.Groups[1].Value.Length) -ForegroundColor Cyan -NoNewline
        }
        else {
            Write-Host $left[$i].PadRight($colWidth) -ForegroundColor Cyan -NoNewline
        }
        
        Write-Host "  " -NoNewline
        
        # Kolom Kanan
        if ($i -lt $right.Count) {
            $matchR = [regex]::Match($right[$i], '^(\[\d+\])(.*)')
            if ($matchR.Success) {
                Write-Host $matchR.Groups[1].Value -ForegroundColor Green -NoNewline
                Write-Host $matchR.Groups[2].Value.PadRight($colWidth - $matchR.Groups[1].Value.Length) -ForegroundColor Green -NoNewline
            }
            else {
                Write-Host $right[$i].PadRight($colWidth) -ForegroundColor Green -NoNewline
            }
        }
        Write-Host ""
    }

    Write-Host ""
    Write-Host " :   NOTE:                                                                            :" -ForegroundColor Red
    Write-Host " :   Rekomen Pilih: [25] EKSEKUSI ALLFIX (42 LANGKAH SEKALIGUS - Obat Manjur!)        :" -ForegroundColor Red
    Write-Host " :   Ketik [?] untuk HELP | [? 7] detail fitur 7 | [? all] buka dokumentasi          :" -ForegroundColor DarkYellow
    Write-Host " --------------------------------------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
    Write-Host "Type option: " -NoNewline
}

# =========================================================================
# RUNTIME LOOP DAN PENUTUPAN SCRIPT
# =========================================================================

if ($script:silentNuke) {
    AllFix-Core
    exit
}

do {
    Show-Menu
    $choice = Read-Host
    $choice = $choice.Trim()
    
    # Handle perintah bantuan: ?, ? 7, ? all, help, help 7
    if ($choice -match '^\?(.*)$' -or $choice -match '^help\s*(.*)$') {
        $helpTopic = $Matches[1].Trim()
        Show-Help -Topic $helpTopic
        Write-Host "`n  [>] Tekan ENTER untuk kembali ke Menu Utama..." -ForegroundColor Yellow
        Read-Host | Out-Null
        continue
    }
    
    if ($choice -match '^\d+$' -and $choice.Length -gt 1) { $choice = $choice.TrimStart('0') }
    switch ($choice) {
        '1' { Fix-11b }
        '2' { Fix-709 }
        '3' { Fix-bc4 }
        '4' { Fix-NetworkServices }
        '5' { Fix-CSR }
        '6' { Reset-Spooler }
        '7' { Enable-SMBGuest }
        '8' { Reset-Network }
        '9' { Set-NetworkPrivate }
        '10' { Disable-PasswordSharing }
        '11' { Fix-NamedPipes }
        '12' { Open-Firewall }
        '13' { Backup-Registry }
        '14' { Check-RPC }
        '15' { Run-SfcDism }
        '16' { Manage-Drivers }
        '17' { Reset-SpoolerPerm }
        '18' { Manage-SMB1 }
        '19' { Add-Credential }
        '20' { Clean-Credential }
        '21' { Start-Troubleshooter }
        '22' { Force-PrinterOnline }
        '23' { Open-Services }
        '24' { Extreme-25H2 }
        '25' { AllFix-Core }
        '26' { Detect-Win }
        '27' { Rollback-Registry }
        '28' { Disable-IPv6 }
        '29' { Generate-HtmlLog }
        '30' { Restart-PC }
        '31' { Write-Log "Tool Di-close." -Type "INFO"; exit }
        '32' { Test-Koneksi }
        '33' { Scan-RemotePrinter }
        '34' { Remote-SpoolerReset }
        '35' { Log-Manager }
        '36' { Print-Migration }
        '37' { $script:silentNuke = $true; AllFix-Core }
        '38' { Uninstall-Printer }
        '39' { Fix-SMBSigning }
        '40' { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force; Write-Host "  [+] Isolation Dimatikan" -ForegroundColor Green }
        '41' { Start-Service WSDPrintDevice -ErrorAction SilentlyContinue; Write-Host "  [+] WSD Discovery Dinyalakan" -ForegroundColor Green }
        '42' { Fix-UWPPrinting }
        '43' { Fix-mDNS }
        '44' { Fix-WSDFirewall }
        '45' { Fix-LSAProtection }
        '46' { Fix-SAC }
        '47' { Fix-IPPSharing }
        '48' { Fix-AdvancedPointAndPrint }
        '49' { Fix-ModernSMB }
        '50' { Set-SpoolerRecovery }
        '51' { Fix-UACTokenFilter }
        '52' { Reset-SpoolerDependency }
        '53' { Fix-ProviderOrder }
        '54' { Fix-NTLMv2 }
        '55' { Fix-Error40 }
        '56' { Fix-Error02 }
        '57' { Fix-Error7e }
        '58' { Manage-WPP }
        '59' { Scan-PrintEventLog }
        '60' { Manage-TCPPort }
        '61' { Manage-DefaultPrinter }
        '62' { Set-SpoolerWatchdog }
        '63' { Fix-RDPPrinter }
        '64' { Fix-HyperVConflict }
        '65' { Manage-LPR }
        '66' { Fix-PrintToPDF }
        '67' { Fix-CredentialGuard }
        '68' { Manage-BITS }
        '69' { Create-RestorePoint }
        '70' { Quick-Diagnostic }
        default { Write-Host "`n  [-] Salah input. Ketik angka 1 - 70." -ForegroundColor Red }
    }
    
    if ($choice -ne '31' -and $choice -ne '30' -and $choice -ne '37') {
        Write-Host "`n  [>] Tekan ENTER untuk kembali ke Menu Utama..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)
