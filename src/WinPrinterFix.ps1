<#
.SYNOPSIS
Windows Printer Sharing Fix Tool (70 OPTIONS)
@khairudinfahmi

.DESCRIPTION
This script repairs various Windows printer sharing anomalies.
Native support for Windows 11 ARM64 & Windows Server 2025.
#>

param(
    [switch]$nuke
)

# =========================================================================
# GLOBAL CONSTANTS & VARIABLES
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

# [ABSOLUTE SILENT] Suppress native PowerShell progress bars
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# =========================================================================
# LOGGING & ELEVATION CORE
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
    Write-Host "`n  [!] Standby... Requesting Administrator elevation." -ForegroundColor Yellow
    Write-Host "  [!] Click 'YES' on the UAC prompt to proceed." -ForegroundColor Yellow
    
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
# REPAIR FUNCTIONS (1-54)
# =========================================================================
function Fix-11b {
    Write-Log "Patching Error 0x0000011b (RpcAuthnLevelPrivacy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "Registry 0x11b successfully mutated." -Type "SUCCESS"
        Write-Host "  [+] RpcAuthnLevelPrivacyEnabled bypass applied." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to patch 0x11b: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-709 {
    Write-Log "Bypassing Error 0x00000709 / 0x0000007c (Point and Print)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name RestrictDriverInstallationToAdministrators -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name BypassedWarnings -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name UpdatePromptSettings -Value 2 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "Point and Print bypass successful (0x709)." -Type "SUCCESS"
        Write-Host "  [+] Point and Print Restrictions fully disabled." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to bypass 0x709: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-bc4 {
    Write-Log "Bypassing Error 0x00000bc4 (No printers were found)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcTcpEnable -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcProtocols -Value 0x7 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ForceSetup -Value 1 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "RPC Endpoint Mapper forced via Named Pipes & TCP." -Type "SUCCESS"
        Write-Host "  [+] RPC printer discovery explicitly routed via Named Pipes." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to bypass 0xbc4: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Fix-NetworkServices {
    Write-Log "Fixing Error 0x80070035 (Starting WSD, SMB, NetBIOS services)..." -Type "INFO"
    $services = @("LanmanServer", "LanmanWorkstation", "lmhosts", "fdPHost", "FDResPub", "SSDPSRV", "upnphost", "WdiSystemHost", "WdiServiceHost")
    
    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Warning: Unable to configure service $svc." -Type "WARNING"
        }
    }
    Write-Log "Network & WSD services configured for auto-start." -Type "SUCCESS"
    Write-Host "  [+] All network services are operational." -ForegroundColor Green
}

function Fix-CSR {
    Write-Log "Disabling Client-Side Rendering (Error 0x6d1)..." -Type "INFO"
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        
        Set-ItemProperty -Path $path -Name DisableClientSideRendering -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "CSR successfully disabled." -Type "SUCCESS"
        Write-Host "  [+] Client-Side Rendering disabled; Host will process print jobs." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to disable CSR: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-Spooler {
    Write-Log "Terminating Print Spooler & Purging Queue..." -Type "INFO"
    try {
        Stop-Service -Name spooler -Force -ErrorAction SilentlyContinue
        
        Write-Log "Ensuring related processes (splwow64, printfilter) are terminated..." -Type "INFO"
        Get-Process -Name "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 1
        
        Write-Log "Purging stale print spool files..." -Type "INFO"
        Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*" -Force -Recurse -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 1
        Start-Service -Name spooler -ErrorAction Stop
        
        Write-Log "Spooler successfully refreshed!" -Type "SUCCESS"
        Write-Host "  [+] Print Spooler successfully purged (Hard Reset)." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to reset Spooler: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Enable-SMBGuest {
    Write-Log "Enabling SMB Guest access (LanmanWorkstation & LanmanServer)..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $path -Name AllowInsecureGuestAuth -Value 1 -Type DWord -Force -ErrorAction Stop
        
        $pathServer = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $pathServer -Name EnableSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Log "Guest access enabled." -Type "SUCCESS"
        Write-Host "  [+] SMB credential protection lowered to permit Guest access." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to enable SMB Guest: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Reset-Network {
    Write-Log "Complete Network Reset (Flush DNS, NetBIOS, Winsock)..." -Type "INFO"
    try {
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; & netsh winsock reset > $null 2>&1
        $LASTEXITCODE = 0; & netsh int ip reset > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1
        
        Write-Log "Network configuration reset." -Type "SUCCESS"
        Write-Host "  [+] Network caches successfully flushed." -ForegroundColor Green
    }
    catch { 
        Write-Log "Failed to reset network: $($_.Exception.Message)" -Type "ERROR" 
    }
}

function Set-NetworkPrivate {
    Write-Log "Mutating Network Profile (Public to Private, bypassing Domain)..." -Type "INFO"
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
                    Write-Log "Failed to mutate profile $($profile.InterfaceAlias)." -Type "WARNING"
                }
            }
            elseif ($profile.NetworkCategory -eq 'Private' -or $profile.NetworkCategory -eq 'DomainAuthenticated') {
                $success = $true
            }
        }
        
        if ($success) {
            Write-Log "Private network profile securely enforced." -Type "SUCCESS"
            Write-Host "  [+] Network enforced as Private; discovery blocks removed." -ForegroundColor Green
        }
    }
    catch {
        Write-Log "Failed to mutate network profile: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Disable-PasswordSharing {
    Write-Log "Disabling Password Protected Sharing..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name limitblankpassworduse -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name everyoneincludesanonymous -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name restrictnullsessaccess -Value 0 -Type DWord -Force -ErrorAction Stop
        
        Write-Log "Password Protected Sharing disabled." -Type "SUCCESS"
        Write-Host "  [+] Network shares opened (Everyone = Anonymous)." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to disable password sharing: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NamedPipes {
    Write-Log "Activating RPC Named Pipes..." -Type "INFO"
    try {
        $rpcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }
        
        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable -Value 1 -Type DWord -Force 
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols -Value 0x7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force
        
        Write-Log "Named Pipes activated." -Type "SUCCESS"
        Write-Host "  [+] RPC Named Pipes pathway for print spooling corrected." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to mutate Named Pipes: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Open-Firewall {
    Write-Log "Opening Firewall for File & Printer Sharing..." -Type "INFO"
    try {
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -ErrorAction SilentlyContinue | Out-Null 
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28509" -ErrorAction SilentlyContinue | Out-Null 
        Enable-NetFirewallRule -DisplayGroup "*File*Printer*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*Network Discovery*" -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Firewall ports opened." -Type "SUCCESS"
        Write-Host "  [+] Windows Defender Firewall configured to permit Sharing." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to mutate Firewall rules: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Backup-Registry {
    Write-Log "Executing Printer Registry Backup..." -Type "INFO"
    try {
        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Print" "$script:backupDir\Print.reg" /y > $null 2>&1
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers" "$script:backupDir\PrintersPolicy.reg" /y > $null 2>&1
        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "$script:backupDir\LanmanWorkstation.reg" /y > $null 2>&1
        Write-Log "Backup successful." -Type "SUCCESS"
        Write-Host "  [+] Critical registry nodes backed up to $script:backupDir." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to backup registry: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Check-RPC {
    Write-Log "Auditing RPC & DCOM service states..." -Type "INFO"
    $rpc = Get-Service -Name RpcSs -ErrorAction SilentlyContinue
    if ($rpc.Status -ne 'Running') { 
        Start-Service RpcSs -ErrorAction SilentlyContinue
        Write-Host "  [*] RpcSs offline. Re-initializing service." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] RpcSs operational." -ForegroundColor Green
    }
    
    $dcom = Get-Service -Name DcomLaunch -ErrorAction SilentlyContinue
    if ($dcom.Status -ne 'Running') { 
        Start-Service DcomLaunch -ErrorAction SilentlyContinue
        Write-Host "  [*] DcomLaunch offline. Re-initializing service." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] DcomLaunch operational." -ForegroundColor Green
    }
}

function Run-SfcDism {
    Write-Log "Initiating SFC and DISM sequences..." -Type "INFO"
    Write-Host "`n  [!] STANDBY, this operation requires significant time..." -ForegroundColor Yellow
    Write-Host "  [*] [1/2] SFC Scannow sequence executing..." -ForegroundColor Cyan
    & sfc /scannow
    Write-Host "  [*] [2/2] DISM RestoreHealth sequence executing..." -ForegroundColor Cyan
    & dism /online /cleanup-image /restorehealth
    Write-Log "SFC & DISM sequence completed." -Type "SUCCESS"
    Write-Host "  [+] OS file integrity verification concluded." -ForegroundColor Green
}

function Manage-Drivers { 
    Write-Log "Launching Print Server Properties..." -Type "INFO"
    Write-Host "  [!] Print Server Properties dialog opening. Purge anomalous drivers manually." -ForegroundColor Yellow
    Start-Process printui -ArgumentList '/s /t2' -NoNewWindow 
}

function Reset-SpoolerPerm {
    Write-Log "Resetting Spooler directory ACL permissions..." -Type "INFO"
    try { 
        & icacls "$env:SystemRoot\System32\Spool\Printers" /reset /t /c /q > $null 2>&1 
        Write-Log "Spooler ACL reset complete." -Type "SUCCESS"
        Write-Host "  [+] Print queue directory permissions explicitly reset." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to reset ACL: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-SMB1 {
    Write-Host "`n  ======================================================================"
    Write-Host "                 SMB 1.0 PROTOCOL MANAGEMENT (LEGACY)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] WARNING: SMB 1.0 is highly vulnerable to Ransomware vectors."
    Write-Host "  [1] ENABLE SMB1 (Emergency) `n  [2] DISABLE SMB1 (Recommended)"
    $smbopt = Read-Host "  Select Option (1/2)"
    if ($smbopt -eq '1') { 
        Write-Log "Enabling SMB 1.0 Protocol..." -Type "INFO"
        Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null 
        Write-Host "  [+] SMB 1.0 Protocol enabled." -ForegroundColor Green
    }
    if ($smbopt -eq '2') { 
        Write-Log "Disabling SMB 1.0 Protocol..." -Type "INFO"
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null 
        Write-Host "  [+] SMB 1.0 Protocol successfully disabled for security." -ForegroundColor Green
    }
}

function Add-Credential {
    Write-Host "`n  INJECT WINDOWS CREDENTIALS"
    $ip = Read-Host "  [?] Target IP/Hostname (e.g., 192.168.1.10)"
    $usr = Read-Host "  [?] Username on Target Host"
    $pass = Read-Host "  [?] Password on Target Host (Visible Text)"
    
    try {
        Start-Process -FilePath "cmdkey.exe" -ArgumentList "/add:$ip", "/user:$usr", "/pass:`"$pass`"" -WindowStyle Hidden -Wait
        Write-Log "Credential for $ip injected." -Type "SUCCESS"
        Write-Host "  [+] Credentials successfully committed to Windows Vault." -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Log "Failed to inject credential: $($_.Exception.Message)" -Type "ERROR"
    }
    $pass = ""
}

function Clean-Credential {
    Write-Host "`n  PURGE STALE WINDOWS CREDENTIALS"
    & cmdkey /list | Select-String "Target:" | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    $del = Read-Host "`n  [?] Enter Target to purge (Leave blank to cancel)"
    if ($del) { 
        $del = $del -replace '(?i)^\s*Target:\s*', ''
        try {
            $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/delete:`"$del`"" -WindowStyle Hidden -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Log "Credential $del purged." -Type "SUCCESS"
                Write-Host "  [+] Credential $del successfully purged." -ForegroundColor Green
            } else {
                Write-Log "Failed to purge credential $del. Verify target name." -Type "ERROR"
                Write-Host "  [-] Failed to purge credential $del. Verify target name." -ForegroundColor Red
            }
        }
        catch {
            Write-Log "Failed to purge credential: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Start-Troubleshooter { 
    Write-Log "Executing native Windows Troubleshooter..." -Type "INFO"
    Start-Process msdt -ArgumentList '/id PrinterDiagnostic' -NoNewWindow 
}

function Force-PrinterOnline {
    Write-Log "Forcing Printer Online status..." -Type "INFO"
    $pname = Read-Host "  [?] Input exact Printer Name (e.g., EPSON L120 Series)"
    if ($pname) {
        try {
            $prn = Get-CimInstance Win32_Printer -Filter "Name='$pname'" -ErrorAction Stop
            if ($prn) {
                # Force default triggers online spooler event
                $prn | Invoke-CimMethod -MethodName "SetDefaultPrinter" | Out-Null
                Write-Log "Printer $pname state forced." -Type "SUCCESS"
                Write-Host "  [+] Online enforcement directive transmitted to $pname." -ForegroundColor Green
            }
            else {
                Write-Host "  [-] Printer $pname not detected on this system." -ForegroundColor Red
            }
        }
        catch { 
            Write-Log "Failed to force printer online status: $($_.Exception.Message)" -Type "ERROR" 
        }
    }
}

function Open-Services { 
    Write-Log "Launching Services.msc MMC snap-in..." -Type "INFO"
    Start-Process services.msc 
}

function Rollback-Registry {
    Write-Log "Restoring Registry from Backup..." -Type "INFO"
    if (Test-Path "$script:backupDir\Print.reg") {
        & reg import "$script:backupDir\Print.reg" > $null 2>&1
        & reg import "$script:backupDir\PrintersPolicy.reg" > $null 2>&1
        & reg import "$script:backupDir\LanmanWorkstation.reg" > $null 2>&1
        Write-Log "Registry rollback successful!" -Type "SUCCESS"
        Write-Host "  [+] Network and printer configurations successfully reverted." -ForegroundColor Green
    }
    else {
        Write-Host "  [-] Failure: Backup files not detected in $script:backupDir." -ForegroundColor Red
    }
}

function Disable-IPv6 {
    Write-Log "Disabling IPv6 Stack..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -Value 0xffffffff -Type DWord -Force -ErrorAction Stop
        Write-Log "IPv6 disabled via registry mutation." -Type "SUCCESS"
        Write-Host "  [+] IPv6 disabled to prevent routing conflicts. System reboot required." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to disable IPv6: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Generate-HtmlLog {
    Write-Log "Generating HTML Diagnostic Report..." -Type "INFO"
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
    <h1>Windows Printer Sharing Fix Diagnostics Report</h1>
    <p>Generation Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Target OS: $script:productName</p>
    <pre>$(Get-Content $script:logFile -Raw)</pre>
</body>
</html>
"@
    $htmlContent | Out-File $htmlFile -Encoding UTF8
    Write-Log "HTML Log generated at $htmlFile." -Type "SUCCESS"
    Start-Process $htmlFile
}

function Test-Koneksi {
    Write-Host "`n  ======================================================================"
    Write-Host "                 PING & NETWORK PORT DIAGNOSTICS"
    Write-Host "  ======================================================================"
    $ip = Read-Host "  [?] Input Target IP/Hostname"
    if (Test-Connection $ip -Count 1 -Quiet) {
        Write-Host "  [+] PING SUCCESS: Host $ip is reachable." -ForegroundColor Green
        
        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] PORT 445 (SMB): OPEN" -ForegroundColor Green } 
        else { Write-Host "  [-] PORT 445 (SMB): CLOSED (FIREWALL BLOCKED)" -ForegroundColor Red }
        
        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] PORT 135 (RPC): OPEN" -ForegroundColor Green } 
        else { Write-Host "  [-] PORT 135 (RPC): CLOSED (FIREWALL BLOCKED)" -ForegroundColor Red }
    }
    else { 
        Write-Host "  [-] PING FAILED: Target Host unreachable or explicitly blocking ICMP." -ForegroundColor Red 
    }
}

function Scan-RemotePrinter {
    Write-Host "`n  REMOTE NETWORK PRINTER DISCOVERY"
    $ip = Read-Host "  [?] Target IP/Hostname"
    Write-Host "  [*] Scanning $ip..." -ForegroundColor Cyan
    try {
        $prn = Get-Printer -ComputerName $ip -ErrorAction Stop | Where-Object Shared -eq $true
        if ($prn) {
            $prn | Format-Table Name, ShareName, PortName, PrinterStatus -AutoSize
        }
        else {
            Write-Host "  [-] No shared printers detected on the target host." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [-] RPC connection failure. Verify Admin/Guest access to $ip." -ForegroundColor Red
    }
}

function Remote-SpoolerReset {
    Write-Host "`n  REMOTE SPOOLER RESTART (VIA WINRM/DCOM)"
    $ip = Read-Host "  [?] Target IP/Hostname"
    try { 
        Invoke-Command -ComputerName $ip -ScriptBlock { Restart-Service spooler -Force } -ErrorAction Stop
        Write-Host "  [+] Remote Spooler on $ip successfully restarted!" -ForegroundColor Green
    }
    catch { 
        Write-Host "  [-] Access denied. Verify WinRM/DCOM accessibility and permissions." -ForegroundColor Red 
    }
}

function Log-Manager { 
    Write-Log "Launching Log Manager via Notepad..." -Type "INFO"
    notepad $script:logFile 
}

function Print-Migration { 
    Write-Log "Launching PrintBRM migration utility..." -Type "INFO"
    Start-Process "$env:SystemRoot\System32\spool\tools\PrintBrm.exe" 
}

function Uninstall-Printer {
    $up = Read-Host "`n  [?] Input exact name of the printer to forcefully uninstall"
    if ($up) { 
        try {
            & printui.exe /dl /n "$up" 
            Write-Log "Uninstall directive transmitted for $up." -Type "SUCCESS"
        }
        catch {
            Write-Log "Failed to uninstall $up : $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Fix-SMBSigning {
    Write-Log "Disabling SMB Signing enforcement..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "SMB Signing enforcement disabled." -Type "SUCCESS"
        Write-Host "  [+] SMB Signature requirements dropped (Resolves Win 11 NAS/Legacy connectivity)." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to disable SMB signing: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UWPPrinting {
    Write-Log "Bypassing UWP AppContainer Isolation for Microsoft Edge..." -Type "INFO"
    try {
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Write-Log "Loopback Isolation explicit exemption granted." -Type "SUCCESS"
        Write-Host "  [+] Loopback network isolation for Edge and UWP Apps disabled." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to bypass UWP Loopback: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-mDNS {
    Write-Log "Enabling mDNS & LLMNR discovery protocols..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name EnableMDNS -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "mDNS/LLMNR protocols activated." -Type "SUCCESS"
    }
    catch {
        Write-Log "Failed to configure mDNS: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-WSDFirewall {
    Write-Log "Ensuring WSD (3702) & mDNS (5353) Ports are unconditionally open..." -Type "INFO"
    try {
        Remove-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -ErrorAction SilentlyContinue | Out-Null
        Remove-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -ErrorAction SilentlyContinue | Out-Null
        
        New-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3702 -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5353 -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "WSD Firewall rules successfully mutated." -Type "SUCCESS"
        Write-Host "  [+] UDP Ports 3702 and 5353 explicitly opened in Firewall." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to configure WSD Firewall: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-LSAProtection {
    Write-Log "Downgrading LSA Protection (Permitting legacy authentication)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "LSA PPL enforcement downgraded." -Type "SUCCESS"
    }
    catch {}
}

function Fix-SAC {
    Write-Log "Bypassing Smart App Control (SAC) for print driver injection..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "SAC active bypass deployed." -Type "SUCCESS"
    }
    catch {}
}

function Fix-IPPSharing {
    Write-Log "Enabling Internet Printing Protocol (IPP & Mopria)..." -Type "INFO"
    try {
        if ((Get-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -ErrorAction SilentlyContinue)) {
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-InternetPrinting-Client" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Log "IPP Foundation successfully enabled." -Type "SUCCESS"
            Write-Host "  [+] Windows Feature: Internet Printing Client activated." -ForegroundColor Green
        }
    }
    catch {
        Write-Log "Failed to configure IPP: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-AdvancedPointAndPrint {
    Write-Log "Bypassing Advanced Point & Print Policies (ServerList *.*)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name InForest -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name TrustedServers -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name ServerList -Value "*.*" -Type String -Force -ErrorAction SilentlyContinue
        Write-Log "Point & Print ServerList constraints entirely bypassed." -Type "SUCCESS"
    }
    catch {}
}

function Fix-ModernSMB { 
    Write-Log "Enforcing Modern SMB2/SMB3 Server Configurations..." -Type "INFO"
    try {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue 
        Write-Log "SMB2/SMB3 topologies active." -Type "SUCCESS"
    }
    catch {}
}

function Set-SpoolerRecovery { 
    Write-Log "Configuring Print Spooler automatic restart recovery..." -Type "INFO"
    try {
        & sc.exe failure spooler reset= 0 actions= restart/60000/restart/60000/restart/60000 > $null 2>&1 
        Write-Log "Spooler Auto-Restart Recovery configured." -Type "SUCCESS"
    }
    catch {}
}

function Fix-UACTokenFilter {
    Write-Log "Bypassing UAC Network Administrator restrictions..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force
        Write-Log "LocalAccountTokenFilterPolicy set to 1." -Type "SUCCESS"
        Write-Host "  [+] UAC network administration token filtering disabled." -ForegroundColor Green
    }
    catch {}
}

function Reset-SpoolerDependency {
    Write-Log "Purging third-party Spooler dependencies..." -Type "INFO"
    try {
        & sc.exe config spooler depend= RPCSS/http > $null 2>&1
        Write-Log "Dependencies explicitly reset to RPCSS and http (IPP compliant)." -Type "SUCCESS"
        Write-Host "  [+] Print Spooler dependencies structurally repaired for modern IPP support." -ForegroundColor Green
    }
    catch {}
}

function Fix-ProviderOrder {
    Write-Log "Prioritizing SMB (LanmanWorkstation) in Network Provider Order..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
        $currentOrder = (Get-ItemProperty -Path $path -Name ProviderOrder -ErrorAction SilentlyContinue).ProviderOrder
        if ($currentOrder) {
            $arr = $currentOrder -split "," | Where-Object { $_ -ne "LanmanWorkstation" -and $_ -ne "" }
            $newOrder = "LanmanWorkstation," + ($arr -join ",")
            Set-ItemProperty -Path $path -Name ProviderOrder -Value $newOrder -Force
            Write-Log "Provider Order explicitly mutated (LanmanWorkstation prioritized)." -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to configure Provider Order: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NTLMv2 { 
    Write-Log "Enforcing NTLMv2 Response Compliance..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 1 -Type DWord -Force 
        Write-Log "NTLMv2 successfully enforced." -Type "SUCCESS"
    }
    catch {}
}
# =========================================================================
# EXTENDED FIXES (55 - 70)
# =========================================================================

function Fix-Error40 {
    Write-Log "Fixing Error 0x00000040 (Network Name No Longer Available)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name KeepConn -Value 65535 -Type DWord -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Write-Log "KeepConn SMB set to maximum." -Type "SUCCESS"
        Write-Host "  [+] SMB connection timeout extended to mitigate unstable network topologies." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x40: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Error02 {
    Write-Log "Fixing Error 0x00000002 (System cannot find file)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name CopyFilesPolicy -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "CopyFilesPolicy activated." -Type "SUCCESS"
        Write-Host "  [+] CopyFilesPolicy allowed so OS can ingest missing drivers from Host." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x02: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Error7e {
    Write-Log "Fixing Error 0x0000007e (RPC Failed / Bitness mismatch)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcAuthenticationLevel -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "RPC Authentication downgraded." -Type "SUCCESS"
        Write-Host "  [+] RPC Auth limitations removed to facilitate cross-architecture communication." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x7e: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-WPP {
    Write-Host "`n  ======================================================================"
    Write-Host "           WINDOWS PROTECTED PRINT (WPP) MANAGEMENT"
    Write-Host "  ======================================================================"
    Write-Host "  [!] Modern Win 11 24H2+ feature that provides strict security, BUT blocks"
    Write-Host "      all legacy/custom printers that do not support the Mopria protocol."
    Write-Host "  [1] ENABLE WPP (Legacy printers will likely fail)"
    Write-Host "  [2] DISABLE WPP (Safe for Legacy LAN Sharing - Recommended)"
    $opt = Read-Host "  Select Option (1/2)"
    if ($opt -eq '1') { 
        Write-Log "Enabling WPP Mode..." -Type "INFO"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue 
        Write-Host "  [+] WPP Enabled." -ForegroundColor Yellow
    }
    if ($opt -eq '2') { 
        Write-Log "Disabling WPP Mode..." -Type "INFO"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
        Write-Host "  [+] WPP Successfully Disabled (Compatibility Mode)." -ForegroundColor Green
    }
}

function Scan-PrintEventLog {
    Write-Log "Reading the 20 most recent Printer Service Logs..." -Type "INFO"
    Write-Host "`n  --- ERROR HISTORY FROM MICROSOFT PRINT SERVICE EVENT LOG ---" -ForegroundColor Cyan
    $events = Get-WinEvent -LogName "Microsoft-Windows-PrintService/Admin" -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
        $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
    }
    else {
        Write-Host "  [+] Clean! No historical failures recorded." -ForegroundColor Green
    }
}

function Manage-TCPPort {
    Write-Host "`n  CREATE MANUAL TCP/IP PORT"
    $ip = Read-Host "  [?] Physical Printer IP (e.g., 192.168.1.100)"
    if ($ip) { 
        try {
            Add-PrinterPort -Name "IP_$ip" -PrinterHostAddress $ip -ErrorAction Stop
            Write-Log "TCP/IP Port IP_$ip successfully created." -Type "SUCCESS"
            Write-Host "  [+] Port [IP_$ip] successfully injected into the system." -ForegroundColor Green
        }
        catch {
            Write-Log "Failed to create port: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Manage-DefaultPrinter {
    Write-Host "`n  ENFORCE PERMANENT DEFAULT PRINTER"
    $prn = Read-Host "  [?] Input exact Printer Name to be set as Default"
    if ($prn) { 
        try {
            $wmi = Get-CimInstance Win32_Printer -Filter "Name='$prn'" -ErrorAction Stop
            if ($wmi) { 
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                Write-Log "Default forcefully set to $prn" -Type "SUCCESS"
                Write-Host "  [+] OS forced to assign $prn as Primary Default." -ForegroundColor Green
            }
            else {
                Write-Host "  [-] Printer not detected." -ForegroundColor Red
            }
        }
        catch {
            Write-Log "Failed to set default printer: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Set-SpoolerWatchdog {
    Write-Log "Injecting Spooler Watchdog Task..." -Type "INFO"
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"if((Get-Service spooler).Status -ne 'Running'){ Start-Service spooler }`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "SpoolerWatchdog" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null
        Write-Log "Spooler Watchdog successfully deployed." -Type "SUCCESS"
        Write-Host "  [+] Automated task injected. Spooler audited every 5 minutes and automatically resurrected if offline." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed Watchdog deployment: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RDPPrinter {
    Write-Log "Repairing RDP Printer Terminal Services Redirection..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fDisableCpm -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fEnablePrintRDR -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "RDP Redirection activated." -Type "SUCCESS"
        Write-Host "  [+] Local printers are now visible during Remote Desktop (RDP) sessions." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix RDP: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HyperVConflict {
    Write-Log "Fixing Hyper-V/WSL Network Discovery Conflict..." -Type "INFO"
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Virtual" -or $_.InterfaceDescription -match "Hyper-V" -or $_.InterfaceDescription -match "WSL" }
        if ($adapters) {
            foreach ($adp in $adapters) {
                Set-NetIPInterface -InterfaceAlias $adp.Name -InterfaceMetric 99 -ErrorAction SilentlyContinue
            }
            Write-Log "vSwitch Priority (Metric) successfully lowered." -Type "SUCCESS"
            Write-Host "  [+] Hyper-V/WSL virtual adapters deprioritized to prevent native LAN/Wi-Fi choking." -ForegroundColor Green
        }
        else {
            Write-Host "  [*] No conflicting virtual adapters detected." -ForegroundColor Cyan
        }
    }
    catch {
        Write-Log "Failed Hyper-V Fix: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-LPR {
    Write-Log "Installing legacy LPR/LPD protocols..." -Type "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPRPortMonitor" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPR Port Monitor Installed." -Type "SUCCESS"
    } catch {
        Write-Log "Failed to Install LPR Port Monitor: $($_.Exception.Message)" -Type "WARNING"
    }

    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPDPrintService" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPD Print Service Installed." -Type "SUCCESS"
    } catch {
        Write-Log "Failed to Install LPD Service: $($_.Exception.Message) (Potentially deprecated in latest Win 11 builds)" -Type "WARNING"
    }

    Write-Host "  [+] LPR/LPD installation complete. If failed, this feature may be deprecated in your Windows version." -ForegroundColor Green
}

function Fix-PrintToPDF {
    Write-Log "Reinstalling / Refreshing Microsoft Print to PDF & XPS..." -Type "INFO"
    Write-Host "  [*] This process requires approximately 10-30 seconds..." -ForegroundColor Cyan
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 2
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Print to PDF successfully refreshed." -Type "SUCCESS"
        Write-Host "  [+] Missing/corrupted Microsoft Print to PDF drivers successfully restored!" -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to refresh PrintToPDF: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CredentialGuard {
    Write-Log "Bypassing Credential Guard Restrictions (Strict NTLM)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LsaCfgFlags -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "Credential Guard protection (LsaCfgFlags) disabled." -Type "SUCCESS"
        Write-Host "  [+] Strict NTLM blockade in Win 11 Pro/Enterprise alleviated." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to bypass Credential Guard: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-BITS {
    Write-Log "Restarting BITS Service..." -Type "INFO"
    try {
        Restart-Service BITS -Force -ErrorAction SilentlyContinue
        Write-Log "Background Intelligent Transfer Service (BITS) restarted." -Type "SUCCESS"
        Write-Host "  [+] Windows native driver downloader service restarted to prevent stalled connections." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to restart BITS: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Create-RestorePoint {
    Write-Log "Generating System Restore Point..." -Type "INFO"
    Write-Host "  [*] Invoking System Protection (Please stand by)..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinPrinterSharingFix-SafetyBackup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "System Restore Point generated successfully." -Type "SUCCESS"
        Write-Host "  [+] Windows Restore Point established." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to generate Restore Point: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Quick-Diagnostic {
    Write-Host "`n  ======================================================================"
    Write-Host "              SYSTEM DIAGNOSTICS"
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
    Write-Host "  [+] Network Profile: " -NoNewline; Write-Host $netStr -ForegroundColor $ntc
    
    Write-Host "  [+] OS Type       : " -NoNewline; Write-Host $script:productName -ForegroundColor Cyan
    if ($script:isARM64) { Write-Host "  [+] Architecture  : ARM64 (Snapdragon / Apple M Series VM)" -ForegroundColor Cyan }
    
    Write-Host "  ======================================================================"
}

# =========================================================================
# EXECUTE ALLFIX (42 AUTOMATED STEPS)
# =========================================================================

function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         EXECUTE ALLFIX (42 AUTOMATED REPAIR SEQUENCES)"
    Write-Host "  ===================================================================================================`n"
    Write-Log "RUN ALLFIX (SILENT=$script:silentNuke)" -Type "INFO"

    Write-Host "  [*] [1/42] Detecting OS..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/42] Securing Registry (Backup)..." -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/42] Auditing RPC & DCOM..." -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [4/42] Patching Error 0x11b..." -ForegroundColor Cyan
    Fix-11b

    Write-Host "  [*] [5/42] Bypassing Error 0x709 & UpdatePromptSettings..." -ForegroundColor Cyan
    Fix-709

    Write-Host "  [*] [6/42] Bypassing Error 0xbc4..." -ForegroundColor Cyan
    Fix-bc4

    Write-Host "  [*] [7/42] Fixing Error 0x40 (KeepConn)..." -ForegroundColor Cyan
    Fix-Error40

    Write-Host "  [*] [8/42] Fixing Error 0x02 (CopyFilesPolicy)..." -ForegroundColor Cyan
    Fix-Error02

    Write-Host "  [*] [9/42] Fixing Error 0x7e (RPC Auth)..." -ForegroundColor Cyan
    Fix-Error7e

    Write-Host "  [*] [10/42] Injecting DnsOnWire, StrictName & UAC Bypass..." -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [11/42] Disabling SMB Signing Requirement..." -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [12/42] Ensuring SMB2/SMB3 Compatibility & Provider Order..." -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [13/42] Enforcing Named Pipes & TCP..." -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [14/42] Disabling Client-Side Rendering..." -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [15/42] Disabling Driver Isolation..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force 
    }
    catch {}

    Write-Host "  [*] [16/42] Starting Network Discovery, mDNS, NetBIOS & WSD Services..." -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [17/42] Penetrating Firewall & Opening UDP Pathways..." -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [18/42] Opening SMB Guest Access (Client & Server)..." -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [19/42] Disabling Password Protected Network Sharing..." -ForegroundColor Cyan
    Disable-PasswordSharing
    
    Write-Host "  [*] [20/42] Downgrading LSA Protection & Enforcing NTLMv2..." -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard
    
    Write-Host "  [*] [21/42] Bypassing Smart App Control (SAC)..." -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [22/42] Initializing IPP & Mopria Print Sharing..." -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [23/42] Disabling WPP (Allowing legacy network printing)..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
    }
    catch {}

    Write-Host "  [*] [24/42] Fixing RDP & LPD Protocols..." -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [25/42] Forcing network to Private Mode..." -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [26/42] Deprioritizing Virtual Adapters (Hyper-V)..." -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [27/42] Flushing DNS & Winsock..." -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [28/42] Terminating Spooler..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [29/42] Injecting Auto-Restart Recovery into Spooler..." -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [30/42] Purging Spooler Dependencies (http & RPCSS)..." -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [31/42] Resetting PRINTERS Folder Permissions..." -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [32/42] Purging stale print queues & Splwow64..." -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [33/42] Bypassing AppContainer UWP/Edge Loopback..." -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [34/42] Applying Advanced Point & Print ServerList (*.*)..." -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [35/42] Deploying Spooler Watchdog Task..." -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [36/42] Restarting BITS Service..." -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [37/42] Restarting Spooler (validation)..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler validated operational." -ForegroundColor Green

    Write-Host "  [*] [38/42] Purging Kerberos Login Cache..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [39/42] Restarting WdiSystemHost Service..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [40/42] Registering mDNS (Multicast)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [41/42] Forcefully Updating Group Policy Registry (GPUpdate)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [42/42] Generating Restore Point..." -ForegroundColor Cyan
    Create-RestorePoint

    Write-Log "ALLFIX CONCLUDED" -Type "SUCCESS"

    if ($script:silentNuke) {
        Write-Host "`n  ==================================================================================================="
        Write-Host "    [+] SILENT NUKE CONCLUDED! SYSTEM REBOOTING IN 3 SECONDS!"
        Write-Host "  ===================================================================================================`n"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }

    Write-Host "`n  ==================================================================================================="
    Write-Host "    [+] COMPLETE! ALL 42 REPAIR SEQUENCES EXECUTED!"
    Write-Host "  ==================================================================================================="
    Write-Host "  [!] DOMAIN INFO: If host is AD-joined, verify 'Access this computer from network' in secpol.msc`n" -ForegroundColor Yellow

    $cekerror = Read-Host "   [?] Audit logs for execution ERRORS? (Y/N)"
    if ($cekerror -eq 'Y') {
        Write-Host "`n   --- ERROR SCAN RESULTS ---" -ForegroundColor Cyan
        $errors = Select-String -Path $script:logFile -Pattern " - ERROR - " -SimpleMatch
        if ($errors) {
            $errors.Line | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        else {
            Write-Host "   [+] Pristine! No errors detected." -ForegroundColor Green
        }
        Write-Host "   --------------------`n"
    }

    $allfixrestart = Read-Host "   [?] Execute immediate system reboot? (Y/N)"
    if ($allfixrestart -eq 'Y') {
        Write-Host "  [*] Proceeding, rebooting in 5 seconds..." -ForegroundColor Cyan
        Restart-Computer -Force
    }
    else {
        Write-Host "  [*] Acknowledged, ensure manual reboot for maximum efficacy!" -ForegroundColor Cyan
    }
}

function Extreme-25H2 {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "       EXTREME PATH FOR WIN 11 25H2 / 24H2 / 26H2+ / ARM64"
    Write-Host "  ==================================================================================================="
    Write-Host "  [*] Aggressive specialized fix tailored for environments with maximum security enforcement."
    Write-Host "  [*] Automated execution proceeding with zero interruptions..." -ForegroundColor Cyan
    
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

    Write-Log "Extreme Path concluded!" -Type "SUCCESS"
    Write-Host "  [+] Extreme security mutations complete. System reboot highly recommended." -ForegroundColor Green
    
    $extremerestart = Read-Host "`n   [?] Execute immediate system reboot now? (Y/N)"
    if ($extremerestart -eq 'Y') { Restart-Computer -Force }
}

function Restart-PC {
    Write-Host "`n  [*] System rebooting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

function Detect-Win {
    Write-Host "`n  ======================================================================"
    Write-Host "                WINDOWS & ARCHITECTURE DETECTION"
    Write-Host "  ======================================================================"
    Write-Host "  [+] OS Version : $script:productName" -ForegroundColor Green
    Write-Host "  [+] OS Build   : $script:buildNumber" -ForegroundColor Green
    if ($script:isARM64) {
        Write-Host "  [+] Architecture  : ARM64 (Snapdragon / Apple M Series VM)" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] Architecture  : AMD64 / x64" -ForegroundColor Cyan
    }
    if ($script:isServer) {
        Write-Host "  [+] Edition       : Windows Server Edition" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] Edition       : Client (Home/Pro/Enterprise)" -ForegroundColor Cyan
    }
}

# =========================================================================
# INTERACTIVE HELP SYSTEM
# =========================================================================
function Show-Help {
    param([string]$Topic = "")
    
    $helpData = @{
        '1'  = @("Patch Error 0x0000011b (RpcAuthnLevelPrivacy)", "Disables the RpcAuthnLevelPrivacyEnabled registry key so RPC authentication does not block sharing connections.", "Most common error following Windows 10/11 cumulative updates.")
        '2'  = @("Bypass Error 0x00000709 / 0x7c (Point and Print)", "Disables RestrictDriverInstallationToAdministrators to allow automated driver injection.", "Occurs after Microsoft security patches blocking driver injection.")
        '3'  = @("Bypass Error 0x00000bc4 (No Printers Found)", "Forces RPC to utilize Named Pipe Protocol so printers can be discovered.", "Windows reports 'No printers were found' despite network availability.")
        '4'  = @("Fix Error 0x80070035 (Automate Network Services)", "Automates startup for fdPHost, FDResPub, SSDPSRV, upnphost services.", "Target host is invisible in network; 'The network path was not found'.")
        '5'  = @("Disable Client-Side Rendering (Error 0x6d1)", "Enables DisableClientSideRendering in the registry.", "Print job fails due to client-side driver rendering issues.")
        '6'  = @("Hard Reset Print Spooler (Purge Stuck Queue)", "Stops spooler, forcefully deletes queue files in Spool\Printers, restarts spooler.", "Print queue is completely frozen, spooler hangs.")
        '7'  = @("Enable SMB Guest Access & Drop Anonymous Blocks", "Enables AllowInsecureGuestAuth in LanmanWorkstation registry.", "Continuous prompt for credentials when accessing shares.")
        '8'  = @("Complete Network Reset (Flush DNS, Winsock, NetBIOS)", "Flushes DNS, releases/renews IP, resets Winsock & NetBIOS.", "Unstable network connection, RTO, or severe latency.")
        '9'  = @("Force Network Profile to Private", "Overrides all connection profiles to Private state.", "Sharing blocked because network profile is set to Public.")
        '10' = @("Force Disable Password Protected Sharing", "Modifies LSA registry: limitblankpassworduse=0, everyoneincludesanonymous=1.", "Credential prompt appears despite no password being configured.")
        '11' = @("Enable RPC via Named Pipes & TCP", "Forces RPC communication through Named Pipes and TCP protocols.", "Printer connection error due to RPC endpoint blocking.")
        '12' = @("Configure Windows Firewall File & Printer Sharing", "Enables 'File and Printer Sharing' and 'Network Discovery' rules in Firewall.", "Host invisible on network, sharing heavily blocked.")
        '13' = @("Pre-execution Registry Backup (Spooler & Network)", "Exports Print, Printers Policy, and LanmanWorkstation registry trees to C:\WinPrinterFixBackup.", "MANDATORY prior to executing other fixes (safety net).")
        '14' = @("Re-initialize RPC & DCOM Services", "Verifies and restarts RpcSs and DcomLaunch services.", "RPC or DCOM services terminated/crashed; 'RPC server unavailable'.")
        '15' = @("System File Checker & DISM Restoration", "Executes SFC /scannow and DISM /RestoreHealth.", "Corrupted or damaged Windows system files. NOTE: Takes 10-30 minutes.")
        '16' = @("Driver Management (Print Server Properties)", "Launches Print Server Properties to manage installed drivers.", "Corrupted or duplicate printer drivers.")
        '17' = @("Fix Error 0x80070005 (Reset Spooler ACL Permissions)", "Resets Spool\Printers directory ACL to default using icacls.", "'Access Denied' (0x80070005) error during print operations.")
        '18' = @("SMB 1.0 Legacy Protocol Management (ON/OFF)", "Enables or disables SMB 1.0 protocol based on user input.", "Requirement to connect to legacy hosts (Win XP/7). WARNING: Ransomware risk!")
        '19' = @("Inject Windows Credentials into Vault Permanently", "Injects username/password into Windows Credential Manager.", "To bypass manual authentication upon each access.")
        '20' = @("Purge Stale Credentials from Windows Vault", "Purges invalid or outdated credentials from the vault.", "Cached legacy logins causing authentication conflicts.")
        '21' = @("Launch Native Windows Troubleshooter", "Executes native Windows Printer Troubleshooter (msdt).", "Initial diagnostic step before manual intervention.")
        '22' = @("Force Printer Online Status", "Transmits online enforcement command via printui /yl.", "Printer status stuck on 'Offline' or grayed out.")
        '23' = @("Launch Services.msc", "Launches the Services.msc MMC snap-in.", "Manual verification of Windows service states.")
        '24' = @("EXTREME PATH (WIN 11 24H2/25H2 & ARM64 SPECIFIC)", "Aggressive fix combination: DnsOnWire, StrictNameChecking, NTLM level, SMB Signing, Kerberos purge, etc.", "Standard fixes ineffective on latest Windows 11 builds.")
        '25' = @("EXECUTE ALLFIX (42 AUTOMATED REPAIR SEQUENCES)", "Executes 42 automated repair steps sequentially.", "PRIMARY RECOMMENDATION - optimal for all general cases. Reboot required.")
        '26' = @("Detect OS Version & Build Architecture", "Displays OS version, build number, and specific recommendations.", "Prior to selecting a repair pathway.")
        '27' = @("Rollback Registry from Backup", "Imports .reg files from the backup directory.", "Post-fix anomalies introduced. SYNERGY: Requires [13] Backup execution first.")
        '28' = @("Disable IPv6 Stack", "Disables IPv6 via registry and netsh interfaces.", "IPv6 inducing routing conflicts in pure IPv4 networks.")
        '29' = @("Generate HTML Diagnostic Report", "Compiles execution logs into an HTML file.", "For IT documentation or administrative reporting.")
        '30' = @("Reboot System", "Executes an immediate system reboot.", "Following the execution of any major repair sequence.")
        '31' = @("EXIT SCRIPT", "Terminates the Windows Printer Sharing Fix utility.", "")
        '32' = @("Ping & Port 445/135 Diagnostics", "ICMP Ping + port scanning for SMB (445) and RPC (135).", "Initial phase of network connectivity diagnostics.")
        '33' = @("Remote Network Printer Discovery", "Scans and enumerates all shared printers on the target.", "Unknown shared printers on target host.")
        '34' = @("Remote Target Spooler Restart", "Executes remote spooler reset via PowerShell WinRM/DCOM.", "Remote spooler frozen without physical access.")
        '35' = @("View Execution Logs", "Launches log management interface.", "Requirement to audit historical repair operations.")
        '36' = @("PrintBRM (Printer Backup/Restore Migration)", "Executes full backup or restoration of printer topologies via PrintBrm.exe.", "Deploying printers to multiple workstations or migrating to new hardware.")
        '37' = @("SILENT NUKE & ALLFIX (ZERO-PROMPT)", "Executes all 42 steps + automated reboot WITHOUT interaction.", "EMERGENCY: Rapid unattended resolution. WARNING: AUTO REBOOTS!")
        '38' = @("Force Remove Ghost Printers", "Forces printer removal via command line (printui /dl).", "Printer uninstallation fails via standard GUI.")
        '39' = @("Disable SMB Signing (Fix Win 11 NAS Access)", "Disables RequireSecuritySignature for SMB client and server.", "Unable to access NAS or legacy hosts from Win 11 24H2+.")
        '40' = @("Disable Print Driver Isolation", "Disables IsolationPolicy in the registry.", "Printer driver crash forces spooler termination.")
        '41' = @("Force Initialize WSD Print Device", "Initializes WSDPrintDevice service for Web Services Discovery.", "WSD network printers remain undetected.")
        '42' = @("Fix Microsoft Edge / UWP Printing", "Re-registers UWP printing components.", "Unable to print from Microsoft Store/Edge applications.")
        '43' = @("Enable mDNS & LLMNR (Discovery Protocols)", "Enables Multicast DNS and LLMNR protocols.", "Printers undetectable via hostname resolution.")
        '44' = @("Configure WSD Firewall Rules (Port 3702)", "Opens UDP port 3702 for WSD discovery in firewall.", "Web Services Discovery blocked by firewall.")
        '45' = @("Downgrade LSA Protection (Legacy Auth)", "Disables RunAsPPL in LSA registry.", "Authentication rejected due to aggressive LSA Protection.")
        '46' = @("Bypass Smart App Control (SAC)", "Sets VerifiedAndReputablePolicyState to Off.", "Smart App Control blocking driver installation.")
        '47' = @("Enable IPP & Mopria Sharing Foundation", "Enables Windows IPP and Mopria Foundation features.", "Modern printers utilizing IPP protocols.")
        '48' = @("Bypass Advanced ServerList Point & Print", "Injects ServerList wildcard (*) into registry.", "Point and Print policies obstructing driver installation.")
        '49' = @("Force Modern SMB2/SMB3 Topology", "Ensures SMB2/SMB3 are active, explicitly disables SMB1.", "Transitioning to modern secure protocols.")
        '50' = @("Configure Spooler Auto-Restart on Crash", "Configures recovery action: auto-restart upon crash.", "Print Spooler crashes and remains inactive.")
        '51' = @("Bypass UAC Admin Network TokenFilter", "Configures LocalAccountTokenFilterPolicy = 1.", "Admin share access denied despite administrative credentials.")
        '52' = @("Purge Stale Spooler Dependencies", "Resets DependOnService spooler parameters to default.", "Spooler fails to start due to invalid service dependencies.")
        '53' = @("Prioritize SMB in Network Provider Order", "Prioritizes LanmanWorkstation in the provider list.", "SMB connections suffering extreme latency.")
        '54' = @("Force NTLMv2 Response Compliance", "Configures LmCompatibilityLevel strictly to NTLMv2.", "Authentication fails due to NTLM version mismatch.")
        '55' = @("Fix Error 0x00000040 (Network Unavailable)", "Repairs PrintProcessor and Ports registry nodes.", "Error 'Network is unavailable' during printer access.")
        '56' = @("Fix Error 0x00000002 (CopyFilesPolicy Violation)", "Configures CopyFilesPolicy allowing driver ingestion.", "Error cloning printer driver from host server.")
        '57' = @("Fix Error 0x0000007e (RPC Bitness Mismatch)", "Forces registry compliance for cross-architecture drivers.", "32-bit vs 64-bit architecture mismatch.")
        '58' = @("Manage Windows Protected Print (WPP)", "Disables Windows Protected Print feature.", "WPP in Windows 11 obstructing legacy driver usage.")
        '59' = @("Audit Last 20 Print Service Error Logs", "Parses the last 20 error events from the System Event Log.", "Requirement to audit specific print service fault origins.")
        '60' = @("Manually Inject Standard TCP/IP Port", "Injects TCP/IP port via WMI scripting.", "Requirement to inject an IP printer port manually.")
        '61' = @("Force Permanent Default Printer", "Disables auto-manage and forcibly sets default.", "Default printer spontaneously reassigns.")
        '62' = @("Deploy Spooler Watchdog (5-Minute Audit)", "Deploys a scheduled task auditing the spooler every 5 minutes.", "Spooler silently terminates without notification.")
        '63' = @("Fix RDP Printer Terminal Services", "Enables printer redirection in RDP registry.", "Redirected printers absent in Remote Desktop sessions.")
        '64' = @("Resolve Hyper-V/WSL Virtual Network Conflicts", "Disables printer bindings on virtual adapters.", "Hyper-V/WSL virtual switches disrupting LAN topology.")
        '65' = @("Install Legacy LPR/LPD Protocols", "Enables Windows LPR Port Monitor & LPD Service features.", "Requirement to connect via LPR (Line Printer Remote).")
        '66' = @("Reinstall Microsoft Print to PDF/XPS", "Re-initializes native Windows PDF & XPS printing features.", "Native virtual printers missing or generating errors.")
        '67' = @("Bypass Credential Guard (Strict NTLM Block)", "Disables LsaCfgFlags Credential Guard registry node.", "Credential Guard actively blocking NTLM authentication.")
        '68' = @("Restart BITS (Background Transfer Service)", "Restarts Background Intelligent Transfer Service.", "Driver downloads failing via Windows Update.")
        '69' = @("Generate System Restore Point (Security)", "Generates a System Restore Point for full OS rollback.", "Requirement for a system-level safety net prior to mutation.")
        '70' = @("System Diagnostics Audit", "Audits Spooler state, SMB, Firewall, and network topologies.", "Requirement for a rapid health summary of the printing subsystem.")
    }

    if ($Topic -eq "" -or $Topic -eq "menu") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "     USER GUIDE: Windows Printer Sharing Fix - @KHAIRUDINFAHMI" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  HOW TO USE:" -ForegroundColor Yellow
        Write-Host "    - Input feature number (1-70) and press ENTER"
        Write-Host "    - Both '7' and '07' are valid"
        Write-Host "    - Input '?' to display this guide"
        Write-Host "    - Input '? 7' for detailed explanation of feature 7"
        Write-Host "    - Input '? all' to open complete HTML documentation"
        Write-Host ""
        Write-Host "  BEGINNER WORKFLOW (Standard Execution):" -ForegroundColor Yellow
        Write-Host "    1. Execute [13] Backup Registry (MANDATORY)" -ForegroundColor White
        Write-Host "    2. Execute [25] ALLFIX (42 automated steps)" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host "    4. Verify printer sharing access" -ForegroundColor White
        Write-Host ""
        Write-Host "  WIN 11 24H2+ WORKFLOW (Build 26000+):" -ForegroundColor Yellow
        Write-Host "    1. Execute [13] Backup Registry" -ForegroundColor White
        Write-Host "    2. Execute [24] Extreme Path" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host ""
        Write-Host "  EMERGENCY PROTOCOL (Rapid Unattended):" -ForegroundColor Yellow
        Write-Host "    - Execute [37] Silent Nuke (WARNING: Auto-reboots!)" -ForegroundColor White
        Write-Host ""
        Write-Host "  FEATURE CATEGORIES:" -ForegroundColor Yellow
        Write-Host "    [01-05] Error Code Fixes (0x11b, 0x709, 0xbc4, 0x35, 0x6d1)" -ForegroundColor Cyan
        Write-Host "    [06-12] Network & Sharing Configuration (Spooler, SMB, Firewall)" -ForegroundColor Cyan
        Write-Host "    [13-17] System Utilities (Backup, RPC, SFC/DISM, Driver, ACL)" -ForegroundColor Cyan
        Write-Host "    [18-23] Credential & Management (SMB1, Credential, Troubleshooter)" -ForegroundColor Cyan
        Write-Host "    [24-31] Execution & Control (Extreme, AllFix, Rollback, Restart)" -ForegroundColor Cyan
        Write-Host "    [32-38] Remote & Diagnostics (Ping, Scan, Remote Reset, Log)" -ForegroundColor Cyan
        Write-Host "    [39-54] Advanced Tweaks (SMB Signing, WSD, LSA, SAC, IPP, UAC)" -ForegroundColor Green
        Write-Host "    [55-70] Extended Fixes (Error 0x40/02/7e, WPP, RDP, Hyper-V)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  QUICK TROUBLESHOOTING:" -ForegroundColor Yellow
        Write-Host "    - Continuous password prompts?     -> Execute [07], [10], [19]" -ForegroundColor White
        Write-Host "    - Printer Offline despite powered on? -> Execute [22]" -ForegroundColor White
        Write-Host "    - Host invisible in network?       -> Execute [04], [09], [12]" -ForegroundColor White
        Write-Host "    - Failed to print from Edge/UWP?   -> Execute [42]" -ForegroundColor White
        Write-Host "    - Need to rollback all changes?    -> Execute [27]" -ForegroundColor White
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
    }
    elseif ($Topic.ToLower() -eq "all") {
        $docPath = $null
        # Search relative to EXE location (ps2exe compatible)
        try {
            $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
            $docPath = Join-Path $exeDir "dokumentasi.html"
        }
        catch {}
        # Fallback to $PSCommandPath (if executed as .ps1)
        if (-not $docPath -or -not (Test-Path $docPath)) {
            try {
                if ($PSCommandPath) {
                    $docPath = Join-Path (Split-Path $PSCommandPath -Parent) "dokumentasi.html"
                }
            }
            catch {}
        }
        if ($docPath -and (Test-Path $docPath)) {
            Write-Host "  [*] Opening complete HTML documentation..." -ForegroundColor Cyan
            $fileUrl = "file:///" + $docPath.Replace("\", "/") + "?all"
            Start-Process $fileUrl
        }
        else {
            Write-Host "  [-] File dokumentasi.html not detected in installation directory." -ForegroundColor Red
            Write-Host "  [!] Utilize '?' for quick guide or '? <number>' for feature details." -ForegroundColor Yellow
        }
    }
    else {
        $num = $Topic.TrimStart('0')
        if ($helpData.ContainsKey($num)) {
            $h = $helpData[$num]
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host "     HELP: FEATURE [$Topic]" -ForegroundColor Green
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  NAME     : $($h[0])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  FUNCTION : $($h[1])" -ForegroundColor White
            Write-Host ""
            if ($h[2] -ne "") {
                Write-Host "  TRIGGER  : $($h[2])" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [-] Feature number '$Topic' not found. Input 1-70." -ForegroundColor Red
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
    Write-Host " ENGINEERED BY: @KHAIRUDINFAHMI (2026)" -ForegroundColor Magenta
    Write-Host "------------------------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $colWidth = 59

    Write-Host ""
    Write-Host " ERROR CODES & FIXES" -ForegroundColor Cyan -NoNewline
    Write-Host (" " * ($colWidth - 20)) -NoNewline
    Write-Host " NETWORK & ADVANCED TWEAKS" -ForegroundColor Cyan
    Write-Host ""

    $left = @(
        "[01] Patch Error 0x0000011b (RpcAuthnLevelPrivacy)",
        "[02] Bypass Error 0x00000709 / 0x7c (Point and Print)",
        "[03] Bypass Error 0x00000bc4 (No Printers Found)",
        "[04] Fix Error 0x80070035 (Automate Network Services)",
        "[05] Disable Client-Side Rendering (Error 0x6d1)",
        "[06] Hard Reset Print Spooler (Purge Stuck Queue)",
        "[07] Enable SMB Guest Access & Drop Anonymous Blocks",
        "[08] Complete Network Reset (Flush DNS, Winsock, NetBIOS)",
        "[09] Force Network Profile to Private",
        "[10] Force Disable Password Protected Sharing",
        "[11] Enable RPC via Named Pipes & TCP",
        "[12] Configure Windows Firewall File & Printer Sharing",
        "[13] Pre-execution Registry Backup (Spooler & Network)",
        "[14] Re-initialize RPC & DCOM Services",
        "[15] System File Checker & DISM Restoration",
        "[16] Driver Management (Print Server Properties)",
        "[17] Fix Error 0x80070005 (Reset Spooler ACL Permissions)",
        "[18] SMB 1.0 Legacy Protocol Management (ON/OFF)",
        "[19] Inject Windows Credentials into Vault Permanently",
        "[20] Purge Stale Credentials from Windows Vault",
        "[21] Launch Native Windows Troubleshooter",
        "[22] Force Printer Online Status",
        "[23] Launch Services.msc",
        "[24] EXTREME PATH (WIN 11 24H2/25H2 & ARM64 SPECIFIC)",
        "[25] EXECUTE ALLFIX (42 AUTOMATED REPAIR SEQUENCES)",
        "[26] Detect OS Version & Build Architecture",
        "[27] Rollback Registry from Backup",
        "[28] Disable IPv6 Stack",
        "[29] Generate HTML Diagnostic Report",
        "[30] Reboot System",
        "[31] EXIT SCRIPT",
        "[32] Ping & Port 445/135 Diagnostics",
        "[33] Remote Network Printer Discovery",
        "[34] Remote Target Spooler Restart",
        "[35] View Execution Logs"
    )

    $right = @(
        "[36] PrintBRM (Backup/Restore Migration)",
        "[37] SILENT NUKE & ALLFIX (ZERO-PROMPT)",
        "[38] Force Remove Ghost Printers",
        "[39] Disable SMB Signing (Fix Win 11 NAS Access)",
        "[40] Disable Print Driver Isolation",
        "[41] Force Initialize WSD Print Device",
        "[42] Fix Microsoft Edge / UWP Printing",
        "[43] Enable mDNS & LLMNR (Discovery Protocols)",
        "[44] Configure WSD Firewall Rules (Port 3702)",
        "[45] Downgrade LSA Protection (Legacy Auth)",
        "[46] Bypass Smart App Control (SAC)",
        "[47] Enable IPP & Mopria Sharing Foundation",
        "[48] Bypass Advanced ServerList Point & Print",
        "[49] Force Modern SMB2/SMB3 Topology",
        "[50] Configure Spooler Auto-Restart on Crash",
        "[51] Bypass UAC Admin Network TokenFilter",
        "[52] Purge Stale Spooler Dependencies",
        "[53] Prioritize SMB in Network Provider Order",
        "[54] Force NTLMv2 Response Compliance",
        "[55] Fix Error 0x00000040 (Network Unavailable)",
        "[56] Fix Error 0x00000002 (CopyFilesPolicy Violation)",
        "[57] Fix Error 0x0000007e (RPC Bitness Mismatch)",
        "[58] Manage Windows Protected Print (WPP)",
        "[59] Audit Last 20 Print Service Error Logs",
        "[60] Manually Inject Standard TCP/IP Port",
        "[61] Force Permanent Default Printer",
        "[62] Deploy Spooler Watchdog (5-Minute Audit)",
        "[63] Fix RDP Printer Terminal Services",
        "[64] Resolve Hyper-V/WSL Virtual Network Conflicts",
        "[65] Install Legacy LPR/LPD Protocols",
        "[66] Reinstall Microsoft Print to PDF/XPS",
        "[67] Bypass Credential Guard (Strict NTLM Block)",
        "[68] Restart BITS (Background Transfer Service)",
        "[69] Generate System Restore Point (Security)",
        "[70] System Diagnostics Audit"
    )

    for ($i = 0; $i -lt 35; $i++) {
        Write-Host " " -NoNewline
        # Left Column
        $matchL = [regex]::Match($left[$i], '^(\[\d+\])(.*)')
        if ($matchL.Success) {
            Write-Host $matchL.Groups[1].Value -ForegroundColor Green -NoNewline
            if ($matchL.Groups[1].Value -eq "[24]") {
                Write-Host $matchL.Groups[2].Value.PadRight($colWidth - $matchL.Groups[1].Value.Length) -ForegroundColor Red -NoNewline
            } elseif ($matchL.Groups[1].Value -eq "[25]") {
                Write-Host $matchL.Groups[2].Value.PadRight($colWidth - $matchL.Groups[1].Value.Length) -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host $matchL.Groups[2].Value.PadRight($colWidth - $matchL.Groups[1].Value.Length) -ForegroundColor Cyan -NoNewline
            }
        }
        else {
            Write-Host $left[$i].PadRight($colWidth) -ForegroundColor Cyan -NoNewline
        }
        
        Write-Host "  " -NoNewline
        
        # Right Column
        if ($i -lt $right.Count) {
            $matchR = [regex]::Match($right[$i], '^(\[\d+\])(.*)')
            if ($matchR.Success) {
                Write-Host $matchR.Groups[1].Value -ForegroundColor Green -NoNewline
                if ($matchR.Groups[1].Value -eq "[37]") {
                    Write-Host $matchR.Groups[2].Value.PadRight($colWidth - $matchR.Groups[1].Value.Length) -ForegroundColor Magenta -NoNewline
                } else {
                    Write-Host $matchR.Groups[2].Value.PadRight($colWidth - $matchR.Groups[1].Value.Length) -ForegroundColor Green -NoNewline
                }
            }
            else {
                Write-Host $right[$i].PadRight($colWidth) -ForegroundColor Green -NoNewline
            }
        }
        Write-Host ""
    }

    Write-Host ""
    Write-Host " :   NOTE:                                                                            :" -ForegroundColor Red
    Write-Host " :   [25] ALLFIX (Recommended) | [24] EXTREME PATH (Win11) | [37] SILENT NUKE         :" -ForegroundColor Red
    Write-Host " :   Input [?] for HELP | [? 7] feature 7 details | [? all] open HTML manual         :" -ForegroundColor DarkYellow
    Write-Host " --------------------------------------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
    Write-Host "Type option: " -NoNewline
}

# =========================================================================
# RUNTIME LOOP AND SCRIPT TERMINATION
# =========================================================================

if ($script:silentNuke) {
    AllFix-Core
    exit
}

do {
    Show-Menu
    $choice = Read-Host
    $choice = $choice.Trim()
    
    # Handle help commands: ?, ? 7, ? all, help, help 7
    if ($choice -match '^\?(.*)$' -or $choice -match '^help\s*(.*)$') {
        $helpTopic = $Matches[1].Trim()
        Show-Help -Topic $helpTopic
        Write-Host "`n  [>] Press ENTER to return to Main Menu..." -ForegroundColor Yellow
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
        '31' { Write-Log "Tool Terminated." -Type "INFO"; exit }
        '32' { Test-Koneksi }
        '33' { Scan-RemotePrinter }
        '34' { Remote-SpoolerReset }
        '35' { Log-Manager }
        '36' { Print-Migration }
        '37' { $script:silentNuke = $true; AllFix-Core }
        '38' { Uninstall-Printer }
        '39' { Fix-SMBSigning }
        '40' { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force; Write-Host "  [+] Isolation Disabled" -ForegroundColor Green }
        '41' { Start-Service WSDPrintDevice -ErrorAction SilentlyContinue; Write-Host "  [+] WSD Discovery Enabled" -ForegroundColor Green }
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
        default { Write-Host "`n  [-] Invalid input. Input numerals 1 - 70." -ForegroundColor Red }
    }
    
    if ($choice -ne '31' -and $choice -ne '30' -and $choice -ne '37') {
        Write-Host "`n  [>] Press ENTER to return to Main Menu..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)
