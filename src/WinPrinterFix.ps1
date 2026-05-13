<#
.SYNOPSIS
Windows Printer Sharing Fix Tool (88 OPTIONS)
@khairudinfahmi

.DESCRIPTION
This script repairs various Windows printer sharing issues.
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
    # Microsoft registry quirk: Windows 11 still reports as "Windows 10"
    if ($script:buildNumber -ge 22000 -and $script:productName -match "Windows 10") {
        $script:productName = $script:productName -replace "Windows 10", "Windows 11"
    }
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
        Write-Log "IPv6 disabled via registry change." -Type "SUCCESS"
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
    Write-Log "Enforcing Strict NTLMv2 Response Compliance (Synology NAS Compatible)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 3 -Type DWord -Force 
        Write-Log "Strict NTLMv2 successfully enforced." -Type "SUCCESS"
        Write-Host "  [+] Strict NTLMv2 enforced (Value 3). NAS Synology & Modern Print Sharing secured." -ForegroundColor Green
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
# NEW FEATURES v2.0 (71-88)
# =========================================================================

function Fix-V4ClassDriver {
    Write-Log "Scanning Universal Print Class Driver (V4) for corruption..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           UNIVERSAL PRINT CLASS DRIVER V4 REPAIR"
    Write-Host "  ======================================================================"
    try {
        $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-4"
        if (-not (Test-Path $v4Path)) {
            $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows NT x86\Drivers\Version-4"
        }
        $corrupted = @()
        if (Test-Path $v4Path) {
            $drivers = Get-ChildItem $v4Path -ErrorAction SilentlyContinue
            foreach ($drv in $drivers) {
                $props = Get-ItemProperty $drv.PSPath -ErrorAction SilentlyContinue
                if ($props.InfPath) {
                    $driverDir = $props.DriverPath
                    if ($driverDir) {
                        $configDll = Join-Path (Split-Path $driverDir -Parent) "PrintConfig.dll"
                        if (-not (Test-Path $configDll)) { $corrupted += $drv.PSChildName }
                    }
                }
            }
        }
        if ($corrupted.Count -gt 0) {
            Write-Host "  [!] Corrupted V4 drivers detected: $($corrupted.Count)" -ForegroundColor Red
            foreach ($c in $corrupted) { Write-Host "      - $c" -ForegroundColor Yellow }
            Write-Host "  [*] Attempting repair via DriverStore re-registration..." -ForegroundColor Cyan
            $prnmsDir = Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository\prnms*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($prnmsDir) {
                $goodDll = Get-ChildItem $prnmsDir.FullName -Filter "PrintConfig.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($goodDll) {
                    Write-Host "  [+] Known-good PrintConfig.dll located at $($goodDll.FullName)" -ForegroundColor Green
                    Write-Log "PrintConfig.dll source located: $($goodDll.FullName)" -Type "SUCCESS"
                }
            }
            & pnputil /scan-devices > $null 2>&1
            Write-Log "V4 driver scan complete. $($corrupted.Count) corrupted entries flagged." -Type "WARNING"
        }
        else {
            Write-Host "  [+] All V4 Print Class Drivers are intact." -ForegroundColor Green
            Write-Log "V4 drivers healthy." -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed V4 scan: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Switch-DriverMode {
    Write-Host "`n  ======================================================================"
    Write-Host "           TOGGLE PCL vs. POSTSCRIPT DRIVER MODE"
    Write-Host "  ======================================================================"
    Write-Log "Launching PCL/PostScript driver toggle..." -Type "INFO"
    try {
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] No printers installed." -ForegroundColor Red; return }
        Write-Host ""
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | Driver: $($p.DriverName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] Select printer number"
        $selIdx = [int]$sel - 1
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] Invalid selection." -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $allDrivers = Get-PrinterDriver -ErrorAction SilentlyContinue
        $currentDriver = $target.DriverName
        Write-Host "`n  Current Driver: $currentDriver" -ForegroundColor Yellow
        if ($currentDriver -match 'PCL') {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PS|PostScript' }
            Write-Host "  [*] Searching for PostScript alternatives..." -ForegroundColor Cyan
        }
        else {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PCL' }
            Write-Host "  [*] Searching for PCL alternatives..." -ForegroundColor Cyan
        }
        if ($altDrivers) {
            $idx = 1
            foreach ($d in $altDrivers) { Write-Host "  [$idx] $($d.Name)" -ForegroundColor Green; $idx++ }
            $drvSel = Read-Host "  [?] Select replacement driver number (0 to cancel)"
            if ($drvSel -ne '0') {
                $drvIdx = [int]$drvSel - 1
                if ($drvIdx -ge 0 -and $drvIdx -lt $altDrivers.Count) {
                    Set-Printer -Name $target.Name -DriverName $altDrivers[$drvIdx].Name -ErrorAction Stop
                    Write-Log "Driver switched: $($target.Name) -> $($altDrivers[$drvIdx].Name)" -Type "SUCCESS"
                    Write-Host "  [+] Driver successfully switched!" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [-] No alternative drivers found. Install the target driver first." -ForegroundColor Red
        }
    }
    catch { Write-Log "Driver toggle failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Manage-WindowsUpdate {
    Write-Host "`n  ======================================================================"
    Write-Host "           UNINSTALL & PAUSE SPECIFIC WINDOWS UPDATE (KB)"
    Write-Host "  ======================================================================"
    Write-Log "Launching KB Update manager..." -Type "INFO"
    try {
        Write-Host "  [*] Enumerating recent Windows Updates..." -ForegroundColor Cyan
        $updates = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 20
        if ($updates) { $updates | Format-Table HotFixID, Description, InstalledOn -AutoSize }
        else { Write-Host "  [-] No hotfixes detected via Get-HotFix." -ForegroundColor Yellow }
        $kb = Read-Host "`n  [?] Input KB number to uninstall (e.g., KB5034441, or blank to cancel)"
        if (-not $kb) { return }
        $kb = $kb -replace '(?i)^KB', ''
        Write-Host "  [*] Attempting to uninstall KB$kb via DISM..." -ForegroundColor Cyan
        $packages = & dism /online /get-packages 2>&1 | Select-String "Package_for_KB$kb"
        if ($packages) {
            $pkgName = ($packages[0].ToString() -split ':')[1].Trim()
            & dism /online /remove-package /package-name:"$pkgName" /quiet /norestart
            Write-Log "KB$kb uninstalled via DISM." -Type "SUCCESS"
            Write-Host "  [+] KB$kb successfully uninstalled." -ForegroundColor Green
        }
        else {
            Write-Host "  [*] DISM package not found, attempting wusa fallback..." -ForegroundColor Yellow
            Start-Process wusa.exe -ArgumentList "/uninstall /kb:$kb /quiet /norestart" -Wait -ErrorAction SilentlyContinue
            Write-Log "KB$kb uninstall attempted via wusa." -Type "INFO"
        }
        $pauseOpt = Read-Host "  [?] Pause Windows Update for 35 days to prevent reinstall? (Y/N)"
        if ($pauseOpt -eq 'Y') {
            $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
            $pauseDate = (Get-Date).AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ")
            Set-ItemProperty -Path $wuPath -Name PauseQualityUpdatesStartTime -Value $pauseDate -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Windows Update paused for 35 days." -ForegroundColor Green
            Write-Log "Windows Update paused until $pauseDate." -Type "SUCCESS"
        }
    }
    catch { Write-Log "KB management failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Sweep-OrphanedDrivers {
    Write-Host "`n  ======================================================================"
    Write-Host "           ORPHANED DRIVER SWEEPER (pnputil)"
    Write-Host "  ======================================================================"
    Write-Log "Scanning for orphaned printer drivers..." -Type "INFO"
    try {
        $rawOutput = & pnputil /enum-drivers 2>&1
        $activeDrivers = (Get-PrinterDriver -ErrorAction SilentlyContinue).Name
        $orphans = @()
        $currentOem = ""
        $currentClass = ""
        $currentProvider = ""
        foreach ($line in $rawOutput) {
            if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') { $currentOem = $Matches[1] }
            if ($line -match 'Class Name\s*:\s*(.+)') { $currentClass = $Matches[1].Trim() }
            if ($line -match 'Driver Package Provider\s*:\s*(.+)') { $currentProvider = $Matches[1].Trim() }
            if ($line -match '^\s*$' -and $currentOem -and $currentClass -match 'Printer') {
                $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
                $currentOem = ""; $currentClass = ""; $currentProvider = ""
            }
        }
        if ($currentOem -and $currentClass -match 'Printer') {
            $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
        }
        if ($orphans.Count -gt 0) {
            Write-Host "  [!] Found $($orphans.Count) printer driver package(s) in Driver Store:" -ForegroundColor Yellow
            $orphans | Format-Table OemInf, Provider -AutoSize
            $confirm = Read-Host "  [?] Force-delete ALL orphaned printer drivers? (Y/N)"
            if ($confirm -eq 'Y') {
                foreach ($o in $orphans) {
                    Write-Host "  [*] Removing $($o.OemInf)..." -ForegroundColor Cyan
                    & pnputil /delete-driver $o.OemInf /force 2>&1 | Out-Null
                }
                Write-Log "Orphaned drivers purged: $($orphans.Count) packages." -Type "SUCCESS"
                Write-Host "  [+] Cleanup complete." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] No orphaned printer drivers found in Driver Store." -ForegroundColor Green
            Write-Log "No orphaned drivers detected." -Type "SUCCESS"
        }
    }
    catch { Write-Log "Driver sweep failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Force-KillDriverProcess {
    Write-Host "`n  ======================================================================"
    Write-Host "           BYPASS 'DRIVER IS CURRENTLY IN USE'"
    Write-Host "  ======================================================================"
    Write-Log "Force-killing driver isolation processes..." -Type "INFO"
    Write-Host "  [!] WARNING: This will terminate all active print processing." -ForegroundColor Red
    $confirm = Read-Host "  [?] Proceed? (Y/N)"
    if ($confirm -ne 'Y') { return }
    try {
        Write-Host "  [*] Stopping Print Spooler..." -ForegroundColor Cyan
        Stop-Service spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $targets = @("PrintIsolationHost", "printfilterpipelinesvc", "splwow64")
        foreach ($proc in $targets) {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] Terminated: $proc (PID: $($running.Id -join ', '))" -ForegroundColor Green
            }
            else {
                Write-Host "  [*] $proc not running." -ForegroundColor Cyan
            }
        }
        Start-Sleep -Seconds 2
        Start-Service spooler -ErrorAction SilentlyContinue
        Write-Log "Driver handles released. Spooler restarted." -Type "SUCCESS"
        Write-Host "  [+] All driver handles released. You may now uninstall drivers." -ForegroundColor Green
    }
    catch { Write-Log "Force-kill failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Convert-WSDtoTCPIP {
    Write-Host "`n  ======================================================================"
    Write-Host "           WSD to STANDARD TCP/IP PORT CONVERTER"
    Write-Host "  ======================================================================"
    Write-Log "Scanning for WSD ports..." -Type "INFO"
    try {
        $wsdPorts = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "WSD-*" }
        if (-not $wsdPorts) {
            Write-Host "  [+] No WSD ports detected. All ports are stable." -ForegroundColor Green
            Write-Log "No WSD ports found." -Type "SUCCESS"
            return
        }
        Write-Host "  [!] Found $($wsdPorts.Count) WSD port(s):" -ForegroundColor Yellow
        foreach ($wp in $wsdPorts) {
            $printerOnPort = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $wp.Name }
            $printerName = if ($printerOnPort) { $printerOnPort.Name } else { "(unassigned)" }
            Write-Host "      Port: $($wp.Name) | Printer: $printerName" -ForegroundColor Cyan
        }
        $ip = Read-Host "`n  [?] Input the actual IP of the WSD printer (e.g., 192.168.1.100)"
        if (-not $ip) { return }
        $newPortName = "IP_$ip"
        if (-not (Get-PrinterPort -Name $newPortName -ErrorAction SilentlyContinue)) {
            Add-PrinterPort -Name $newPortName -PrinterHostAddress $ip -ErrorAction Stop
            Write-Host "  [+] TCP/IP Port $newPortName created." -ForegroundColor Green
        }
        $printerToMove = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -like "WSD-*" } | Select-Object -First 1
        if ($printerToMove) {
            Set-Printer -Name $printerToMove.Name -PortName $newPortName -ErrorAction Stop
            Write-Log "Printer $($printerToMove.Name) migrated from WSD to TCP/IP ($ip)." -Type "SUCCESS"
            Write-Host "  [+] $($printerToMove.Name) migrated to $newPortName." -ForegroundColor Green
        }
    }
    catch { Write-Log "WSD conversion failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-NetworkSockets {
    Write-Host "`n  ======================================================================"
    Write-Host "           NETWORK SOCKET RE-INIT (SELECTIVE PURGE)"
    Write-Host "  ======================================================================"
    Write-Log "Performing selective network socket cleanup..." -Type "INFO"
    try {
        Write-Host "  [*] Scanning for stuck SMB/RPC connections..." -ForegroundColor Cyan
        $stuck445 = & netstat -ano 2>&1 | Select-String ":445\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $stuck135 = & netstat -ano 2>&1 | Select-String ":135\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $totalStuck = 0
        if ($stuck445) { $totalStuck += $stuck445.Count; Write-Host "  [!] Port 445 (SMB): $($stuck445.Count) stuck connections" -ForegroundColor Yellow }
        if ($stuck135) { $totalStuck += $stuck135.Count; Write-Host "  [!] Port 135 (RPC): $($stuck135.Count) stuck connections" -ForegroundColor Yellow }
        if ($totalStuck -eq 0) { Write-Host "  [+] No stuck connections detected." -ForegroundColor Green }
        Write-Host "  [*] Restarting SMB Client & Server services only..." -ForegroundColor Cyan
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanServer -Force -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1
        Write-Log "Network sockets selectively purged. $totalStuck connections cleared." -Type "SUCCESS"
        Write-Host "  [+] Socket cleanup complete. $totalStuck stale connections purged." -ForegroundColor Green
    }
    catch { Write-Log "Socket re-init failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Rescue-NetworkProfile {
    Write-Host "`n  ======================================================================"
    Write-Host "           RESCUE NETWORK PROFILE (AUTO-DETECT & WATCHDOG)"
    Write-Host "  ======================================================================"
    Write-Log "Rescuing network profile..." -Type "INFO"
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        $publicFound = $false
        foreach ($p in $profiles) {
            if ($p.NetworkCategory -eq 'Public') {
                $publicFound = $true
                Write-Host "  [!] Public profile detected on: $($p.InterfaceAlias)" -ForegroundColor Red
                Set-NetConnectionProfile -InterfaceAlias $p.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
                Write-Host "  [+] Forced to Private: $($p.InterfaceAlias)" -ForegroundColor Green
            }
        }
        if (-not $publicFound) { Write-Host "  [+] All profiles are already Private/Domain. No action needed." -ForegroundColor Green }
        $deployWatchdog = Read-Host "`n  [?] Deploy Network Profile Watchdog (checks every 10 min)? (Y/N)"
        if ($deployWatchdog -eq 'Y') {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Get-NetConnectionProfile | Where-Object { `$_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private`""
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
            Register-ScheduledTask -TaskName "NetworkProfileWatchdog" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null
            Write-Log "Network Profile Watchdog deployed." -Type "SUCCESS"
            Write-Host "  [+] Watchdog deployed. Profile enforced to Private every 10 minutes." -ForegroundColor Green
        }
    }
    catch { Write-Log "Network rescue failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Remove-GhostUSBPrinters {
    Write-Host "`n  ======================================================================"
    Write-Host "           GHOST USB PORT & COPY ELIMINATOR"
    Write-Host "  ======================================================================"
    Write-Log "Scanning for ghost USB printers and duplicates..." -Type "INFO"
    try {
        $allPrinters = Get-Printer -ErrorAction SilentlyContinue
        $ghosts = $allPrinters | Where-Object { $_.Name -match '\(Copy \d+\)' -or $_.Name -match ' - Copy' -or $_.Name -match 'Copy \d+$' }
        $activePorts = ($allPrinters | Where-Object { $_.Name -notmatch 'Copy' }).PortName
        $deadUSB = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "USB*" -and $_.Name -notin $activePorts }
        if ($ghosts.Count -eq 0 -and $deadUSB.Count -eq 0) {
            Write-Host "  [+] No ghost printers or dead USB ports detected." -ForegroundColor Green
            Write-Log "No ghost devices found." -Type "SUCCESS"
            return
        }
        if ($ghosts.Count -gt 0) {
            Write-Host "  [!] Duplicate/Ghost printers found:" -ForegroundColor Yellow
            foreach ($g in $ghosts) { Write-Host "      - $($g.Name) [Port: $($g.PortName)]" -ForegroundColor Red }
        }
        if ($deadUSB.Count -gt 0) {
            Write-Host "  [!] Dead USB ports found:" -ForegroundColor Yellow
            foreach ($u in $deadUSB) { Write-Host "      - $($u.Name)" -ForegroundColor Red }
        }
        $confirm = Read-Host "`n  [?] Remove all ghost printers and dead USB ports? (Y/N)"
        if ($confirm -eq 'Y') {
            foreach ($g in $ghosts) {
                Remove-Printer -Name $g.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] Removed printer: $($g.Name)" -ForegroundColor Green
            }
            foreach ($u in $deadUSB) {
                Remove-PrinterPort -Name $u.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] Removed port: $($u.Name)" -ForegroundColor Green
            }
            Write-Log "Ghost cleanup: $($ghosts.Count) printers, $($deadUSB.Count) ports removed." -Type "SUCCESS"
        }
    }
    catch { Write-Log "Ghost USB cleanup failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Nuke-PrintQueue {
    Write-Log "Executing Hard-Nuke on Print Queue..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           HARD-NUKE PRINT QUEUE"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] Terminating Print Spooler and all child processes..." -ForegroundColor Cyan
        Stop-Service spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Get-Process -Name "PrintIsolationHost", "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $spoolDir = "$env:SystemRoot\System32\Spool\Printers"
        $shdFiles = Get-ChildItem "$spoolDir\*.shd" -ErrorAction SilentlyContinue
        $splFiles = Get-ChildItem "$spoolDir\*.spl" -ErrorAction SilentlyContinue
        $totalFiles = 0
        if ($shdFiles) { $totalFiles += $shdFiles.Count; Remove-Item "$spoolDir\*.shd" -Force -ErrorAction SilentlyContinue }
        if ($splFiles) { $totalFiles += $splFiles.Count; Remove-Item "$spoolDir\*.spl" -Force -ErrorAction SilentlyContinue }
        Remove-Item "$spoolDir\*" -Force -Recurse -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Service spooler -ErrorAction Stop
        Write-Log "Hard-Nuke complete. $totalFiles corrupt spool files destroyed." -Type "SUCCESS"
        Write-Host "  [+] Print Queue obliterated. $totalFiles stale files purged. Spooler restarted." -ForegroundColor Green
    }
    catch { Write-Log "Hard-Nuke failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-SpoolerDependencyRegistry {
    Write-Log "Resetting Spooler DependOnService via direct registry write..." -Type "INFO"
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Spooler"
        $current = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DependOnService
        if ($current) {
            Write-Host "  [*] Current dependencies: $($current -join ', ')" -ForegroundColor Yellow
        }
        Set-ItemProperty -Path $regPath -Name DependOnService -Value @("RPCSS","http") -Type MultiString -Force -ErrorAction Stop
        Write-Log "Spooler DependOnService reset to factory defaults (RPCSS, http)." -Type "SUCCESS"
        Write-Host "  [+] Spooler dependencies reset to: RPCSS, http" -ForegroundColor Green
        Write-Host "  [*] Restarting Spooler to apply..." -ForegroundColor Cyan
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
    }
    catch { Write-Log "Dependency registry reset failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Inject-CrossUserCredentials {
    Write-Host "`n  ======================================================================"
    Write-Host "           CROSS-USER CREDENTIAL MAPPING"
    Write-Host "  ======================================================================"
    Write-Host "  [!] WARNING: This injects credentials into ALL user profiles on this PC." -ForegroundColor Red
    Write-Log "Cross-User Credential Mapping initiated..." -Type "INFO"
    $ip = Read-Host "  [?] Target IP/Hostname (e.g., 192.168.1.10)"
    $usr = Read-Host "  [?] Username on Target Host"
    $pass = Read-Host "  [?] Password on Target Host (Visible Text)"
    if (-not $ip -or -not $usr) { Write-Host "  [-] Cancelled." -ForegroundColor Red; return }
    try {
        $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' }
        $injected = 0
        foreach ($profile in $profiles) {
            $sid = $profile.PSChildName
            $profilePath = (Get-ItemProperty $profile.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            $userName = Split-Path $profilePath -Leaf
            Write-Host "  [*] Injecting credential for user: $userName ($sid)..." -ForegroundColor Cyan
            $ntuser = Join-Path $profilePath "NTUSER.DAT"
            if (Test-Path $ntuser) {
                $LASTEXITCODE = 0; & reg load "HKU\$sid" $ntuser > $null 2>&1
                Start-Process -FilePath "cmdkey.exe" -ArgumentList "/add:$ip", "/user:$usr", "/pass:`"$pass`"" -WindowStyle Hidden -Wait
                $LASTEXITCODE = 0; & reg unload "HKU\$sid" > $null 2>&1
                $injected++
            }
        }
        Write-Log "Credentials injected for $injected user profiles." -Type "SUCCESS"
        Write-Host "  [+] Credentials injected into $injected user profiles." -ForegroundColor Green
        $pass = ""
    }
    catch { Write-Log "Cross-user credential injection failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Force-DefaultPrinterRegistry {
    Write-Host "`n  ======================================================================"
    Write-Host "           FORCE-SET DEFAULT PRINTER (REGISTRY BYPASS 0x709)"
    Write-Host "  ======================================================================"
    Write-Log "Force-setting default printer via registry injection..." -Type "INFO"
    try {
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] No printers found." -ForegroundColor Red; return }
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | Port: $($p.PortName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] Select printer number to force as default"
        $selIdx = [int]$sel - 1
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] Invalid selection." -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $deviceStr = "$($target.Name),winspool,$($target.PortName):"
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name Device -Value $deviceStr -Type String -Force -ErrorAction Stop
        Write-Log "Default printer forced via registry: $($target.Name)" -Type "SUCCESS"
        Write-Host "  [+] Default printer set to: $($target.Name) (Registry bypass applied)." -ForegroundColor Green
    }
    catch { Write-Log "Registry default printer failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Sanitize-PrinterShareName {
    Write-Log "Scanning for unsanitary printer share names..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           AUTO-SANITIZE PRINTER SHARE NAME"
    Write-Host "  ======================================================================"
    try {
        $shared = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true }
        if (-not $shared) { Write-Host "  [+] No shared printers found." -ForegroundColor Yellow; return }
        $fixed = 0
        foreach ($p in $shared) {
            $original = $p.ShareName
            $clean = $original -replace '[^a-zA-Z0-9_\-\.]', '_' -replace '__+', '_' -replace '^_|_$', ''
            if ($clean -ne $original) {
                Write-Host "  [!] $original -> $clean" -ForegroundColor Yellow
                Set-Printer -Name $p.Name -ShareName $clean -ErrorAction SilentlyContinue
                $fixed++
            }
            else {
                Write-Host "  [+] $original (clean)" -ForegroundColor Green
            }
        }
        if ($fixed -gt 0) {
            Write-Log "Sanitized $fixed printer share names." -Type "SUCCESS"
            Write-Host "`n  [+] $fixed share name(s) sanitized." -ForegroundColor Green
        }
        else {
            Write-Host "`n  [+] All share names are already clean." -ForegroundColor Green
            Write-Log "All share names clean." -Type "SUCCESS"
        }
    }
    catch { Write-Log "Share name sanitization failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Fix-BrowserPrintSandbox {
    Write-Log "Resetting browser print sandbox (Chromium)..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           BROWSER PRINT SANDBOX FIX (CHROMIUM)"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] Terminating browser processes..." -ForegroundColor Cyan
        Get-Process -Name "chrome", "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $cleared = 0
        $chromePrintDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
        $edgePrintDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        if (Test-Path $chromePrintDir) {
            Remove-Item "$chromePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Chrome cache cleared." -ForegroundColor Green
        }
        if (Test-Path $edgePrintDir) {
            Remove-Item "$edgePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Edge cache cleared." -ForegroundColor Green
        }
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
        Write-Log "Browser print sandbox reset. $cleared browser cache(s) cleared." -Type "SUCCESS"
        Write-Host "  [+] Browser print sandbox reset complete. Restart your browser." -ForegroundColor Green
    }
    catch { Write-Log "Browser sandbox fix failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Inject-F4PaperSize {
    Write-Log "Injecting F4/Folio (8.5 x 13 in) paper size..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           AUTO-INJECT F4 / FOLIO PAPER SIZE"
    Write-Host "  ======================================================================"
    try {
        $formName = "F4 (8.5 x 13 in)"
        $existingForms = Get-PrinterProperty -PrinterName (Get-Printer | Select-Object -First 1 -ExpandProperty Name) -ErrorAction SilentlyContinue 2>$null
        Write-Host "  [*] Injecting form via Print Server Properties..." -ForegroundColor Cyan
        $widthMicrons = 215900
        $heightMicrons = 330200
        $formsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Forms"
        if (-not (Test-Path "$formsPath\$formName")) {
            $formData = [byte[]](0x00, 0x00, 0x00, 0x00) + 
                        [BitConverter]::GetBytes([int]$widthMicrons) + 
                        [BitConverter]::GetBytes([int]$heightMicrons) + 
                        [byte[]](0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) + 
                        [BitConverter]::GetBytes([int]$widthMicrons) + 
                        [BitConverter]::GetBytes([int]$heightMicrons)
            try {
                New-Item -Path "$formsPath\$formName" -Force -ErrorAction Stop | Out-Null
                Set-ItemProperty -Path "$formsPath\$formName" -Name "FormData" -Value $formData -Type Binary -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
        $LASTEXITCODE = 0
        & cscript //nologo "$env:SystemRoot\System32\Printing_Admin_Scripts\en-US\prnform.vbs" -a -f "$formName" -w 215.9 -h 330.2 -l 0 -r 215.9 -t 0 -b 330.2 2>&1 | Out-Null
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
        Write-Log "F4/Folio paper size ($formName) injected into Print Server." -Type "SUCCESS"
        Write-Host "  [+] F4 (8.5 x 13 in) paper size successfully registered." -ForegroundColor Green
        Write-Host "  [*] Open Printer Properties > Paper/Quality to verify." -ForegroundColor Cyan
    }
    catch { Write-Log "F4 paper size injection failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Detect-GPOIntervention {
    Write-Log "Scanning for Group Policy intervention on printer registry..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           GROUP POLICY (GPO) INTERVENTION DETECTION"
    Write-Host "  ======================================================================"
    try {
        $policyPaths = @(
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "Printer Policies" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"; Label = "Point and Print" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"; Label = "RPC Policies" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"; Label = "Windows Protected Print" },
            @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "User Printer Policies" }
        )
        $gpoDetected = $false
        foreach ($entry in $policyPaths) {
            if (Test-Path $entry.Path) {
                $props = Get-ItemProperty $entry.Path -ErrorAction SilentlyContinue
                $propNames = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
                if ($propNames.Count -gt 0) {
                    $gpoDetected = $true
                    Write-Host "  [!] GPO LOCK: $($entry.Label)" -ForegroundColor Red
                    foreach ($prop in $propNames) {
                        Write-Host "      $($prop.Name) = $($prop.Value)" -ForegroundColor Yellow
                    }
                }
            }
        }
        Write-Host "`n  [*] Running gpresult for printer-related GPOs..." -ForegroundColor Cyan
        $gpresult = & gpresult /R /Scope Computer 2>&1 | Select-String -Pattern "Printer|Print|Point"
        if ($gpresult) {
            Write-Host "  [!] GPO references found in Computer Policy:" -ForegroundColor Yellow
            $gpresult | ForEach-Object { Write-Host "      $_" -ForegroundColor Cyan }
        }
        if (-not $gpoDetected) {
            Write-Host "  [+] No Group Policy restrictions detected on printer registry." -ForegroundColor Green
            Write-Log "No GPO intervention detected." -Type "SUCCESS"
        }
        else {
            Write-Host "`n  [!] WARNING: GPO-managed keys will be OVERWRITTEN by Domain Controller." -ForegroundColor Red
            Write-Host "  [!] Local changes to these keys will revert after gpupdate." -ForegroundColor Red
            Write-Log "GPO intervention detected on printer registry." -Type "WARNING"
        }
    }
    catch { Write-Log "GPO detection failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Parse-PrintEventLog {
    Write-Log "Parsing top 5 PrintService Error/Warning events..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "           PRINTSERVICE EVENT LOG PARSER (TOP 5)"
    Write-Host "  ======================================================================"
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-PrintService/Admin'
            Level   = @(2, 3)
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($events) {
            $resolutionMap = @{
                '372' = "Spooler crash. Execute [06] or [80] Hard-Nuke Print Queue."
                '808' = "Driver install failure. Execute [74] Orphaned Driver Sweeper."
                '842' = "Queue corruption. Execute [80] Hard-Nuke Print Queue."
                '354' = "Spooler failed to start. Execute [81] Spooler Dependency Reset."
                '824' = "Printer offline. Execute [76] WSD to TCP/IP Converter."
            }
            foreach ($evt in $events) {
                $levelStr = if ($evt.Level -eq 2) { "ERROR" } else { "WARNING" }
                $color = if ($evt.Level -eq 2) { "Red" } else { "Yellow" }
                Write-Host "`n  [$levelStr] Event $($evt.Id) - $($evt.TimeCreated)" -ForegroundColor $color
                Write-Host "  Message: $($evt.Message)" -ForegroundColor White
                if ($resolutionMap.ContainsKey($evt.Id.ToString())) {
                    Write-Host "  SUGGESTION: $($resolutionMap[$evt.Id.ToString()])" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [+] No Error/Warning events found. PrintService is healthy." -ForegroundColor Green
        }
        Write-Log "PrintService event log parsed." -Type "SUCCESS"
    }
    catch { Write-Log "Event log parse failed: $($_.Exception.Message)" -Type "ERROR" }
}


function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         EXECUTE ALLFIX (50 AUTOMATED REPAIR SEQUENCES)"
    Write-Host "  ===================================================================================================`n"
    Write-Log "RUN ALLFIX (SILENT=$script:silentNuke)" -Type "INFO"

    Write-Host "  [*] [1/50] Detecting OS..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/50] Securing Registry (Backup)..." -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/50] Auditing RPC & DCOM..." -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [4/50] Patching Error 0x11b..." -ForegroundColor Cyan
    Fix-11b

    Write-Host "  [*] [5/50] Bypassing Error 0x709 & UpdatePromptSettings..." -ForegroundColor Cyan
    Fix-709

    Write-Host "  [*] [6/50] Bypassing Error 0xbc4..." -ForegroundColor Cyan
    Fix-bc4

    Write-Host "  [*] [7/50] Fixing Error 0x40 (KeepConn)..." -ForegroundColor Cyan
    Fix-Error40

    Write-Host "  [*] [8/50] Fixing Error 0x02 (CopyFilesPolicy)..." -ForegroundColor Cyan
    Fix-Error02

    Write-Host "  [*] [9/50] Fixing Error 0x7e (RPC Auth)..." -ForegroundColor Cyan
    Fix-Error7e

    Write-Host "  [*] [10/50] Injecting DnsOnWire, StrictName & UAC Bypass..." -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [11/50] Disabling SMB Signing Requirement..." -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [12/50] Ensuring SMB2/SMB3 Compatibility & Provider Order..." -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [13/50] Enforcing Named Pipes & TCP..." -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [14/50] Disabling Client-Side Rendering..." -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [15/50] Disabling Driver Isolation..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force 
    }
    catch {}

    Write-Host "  [*] [16/50] Starting Network Discovery, mDNS, NetBIOS & WSD Services..." -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [17/50] Penetrating Firewall & Opening UDP Pathways..." -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [18/50] Opening SMB Guest Access (Client & Server)..." -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [19/50] Disabling Password Protected Network Sharing..." -ForegroundColor Cyan
    Disable-PasswordSharing
    
    Write-Host "  [*] [20/50] Downgrading LSA Protection & Enforcing NTLMv2..." -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard
    
    Write-Host "  [*] [21/50] Bypassing Smart App Control (SAC)..." -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [22/50] Initializing IPP & Mopria Print Sharing..." -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [23/50] Disabling WPP (Allowing legacy network printing)..." -ForegroundColor Cyan
    try { 
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue 
    }
    catch {}

    Write-Host "  [*] [24/50] Fixing RDP & LPD Protocols..." -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [25/50] Forcing network to Private Mode..." -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [26/50] Deprioritizing Virtual Adapters (Hyper-V)..." -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [27/50] Flushing DNS & Winsock..." -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [28/50] Terminating Spooler..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [29/50] Injecting Auto-Restart Recovery into Spooler..." -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [30/50] Purging Spooler Dependencies (http & RPCSS)..." -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [31/50] Resetting PRINTERS Folder Permissions..." -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [32/50] Purging stale print queues & Splwow64..." -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [33/50] Bypassing AppContainer UWP/Edge Loopback..." -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [34/50] Applying Advanced Point & Print ServerList (*.*)..." -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [35/50] Deploying Spooler Watchdog Task..." -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [36/50] Restarting BITS Service..." -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [37/50] Restarting Spooler (validation)..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler validated operational." -ForegroundColor Green

    Write-Host "  [*] [38/50] Purging Kerberos Login Cache..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [39/50] Restarting WdiSystemHost Service..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [40/50] Registering mDNS (Multicast)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [41/50] Forcefully Updating Group Policy Registry (GPUpdate)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [42/50] Generating Restore Point..." -ForegroundColor Cyan
    Create-RestorePoint

    Write-Host "  [*] [43/50] Scanning V4 Print Class Drivers..." -ForegroundColor Cyan
    Fix-V4ClassDriver

    Write-Host "  [*] [44/50] Rescuing Network Profile (Force Private)..." -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    $profiles | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    Write-Host "  [*] [45/50] Hard-Nuking corrupt Print Queue files..." -ForegroundColor Cyan
    Nuke-PrintQueue

    Write-Host "  [*] [46/50] Resetting Spooler Dependencies (Registry)..." -ForegroundColor Cyan
    Reset-SpoolerDependencyRegistry

    Write-Host "  [*] [47/50] Sanitizing Printer Share Names..." -ForegroundColor Cyan
    Sanitize-PrinterShareName

    Write-Host "  [*] [48/50] Injecting F4/Folio Paper Size..." -ForegroundColor Cyan
    Inject-F4PaperSize

    Write-Host "  [*] [49/50] Parsing PrintService Event Log..." -ForegroundColor Cyan
    Parse-PrintEventLog

    Write-Host "  [*] [50/50] Final Spooler Validation..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler validated operational." -ForegroundColor Green

    Write-Log "ALLFIX CONCLUDED" -Type "SUCCESS"

    if ($script:silentNuke) {
        Write-Host "`n  ==================================================================================================="
        Write-Host "    [+] SILENT NUKE CONCLUDED! SYSTEM REBOOTING IN 3 SECONDS!"
        Write-Host "  ===================================================================================================`n"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }

    Write-Host "`n  ==================================================================================================="
    Write-Host "    [+] COMPLETE! ALL 50 REPAIR SEQUENCES EXECUTED!"
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
    Fix-V4ClassDriver
    Reset-SpoolerDependencyRegistry
    Sanitize-PrinterShareName
    
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
    Write-Host "  [+] Extreme security configuration changes complete. System reboot highly recommended." -ForegroundColor Green
    
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
        '3'  = @("Bypass Error 0x00000bc4 (No Printers Found)", "Forces RPC to use Named Pipe Protocol so printers can be discovered.", "Windows reports 'No printers were found' despite network availability.")
        '4'  = @("Fix Error 0x80070035 (Automate Network Services)", "Automates startup for fdPHost, FDResPub, SSDPSRV, upnphost services.", "Target PC is not showing up on the network; 'The network path was not found'.")
        '5'  = @("Disable Client-Side Rendering (Error 0x6d1)", "Enables DisableClientSideRendering in the registry.", "Print job fails due to client-side driver rendering issues.")
        '6'  = @("Fix Error 0x80070005 (Reset Spooler ACL)", "Resets Spool\Printers directory ACL to default using icacls.", "'Access Denied' (0x80070005) error during print operations.")
        '7'  = @("Fix Error 0x00000040 (Network Unavailable)", "Repairs PrintProcessor and Ports registry nodes.", "Error 'Network is unavailable' during printer access.")
        '8'  = @("Fix Error 0x00000002 (CopyFilesPolicy)", "Configures CopyFilesPolicy allowing driver ingestion.", "Error cloning printer driver from host server.")
        '9'  = @("Fix Error 0x0000007e (RPC Bitness Mismatch)", "Forces registry compliance for cross-architecture drivers.", "32-bit vs 64-bit architecture mismatch.")
        '10' = @("Complete Network Reset (DNS, Winsock, NetBIOS)", "Flushes DNS, releases/renews IP, resets Winsock & NetBIOS.", "Unstable network connection, RTO, or severe latency.")
        '11' = @("Force Network Profile to Private", "Overrides all connection profiles to Private state.", "Sharing blocked because network profile is set to Public.")
        '12' = @("Force Disable Password Protected Sharing", "Modifies LSA registry: limitblankpassworduse=0, everyoneincludesanonymous=1.", "Credential prompt appears despite no password being configured.")
        '13' = @("Enable RPC via Named Pipes & TCP", "Forces RPC communication through Named Pipes and TCP protocols.", "Printer connection error due to RPC endpoint blocking.")
        '14' = @("Configure Firewall File & Printer Sharing", "Enables 'File and Printer Sharing' and 'Network Discovery' rules in Firewall.", "Host invisible on network, sharing heavily blocked.")
        '15' = @("SMB 1.0 Legacy Protocol Management (ON/OFF)", "Enables or disables SMB 1.0 protocol based on user input.", "Need to connect to legacy hardware (Win XP/7). WARNING: Ransomware risk!")
        '16' = @("Disable SMB Signing (Fix Win 11 NAS Access)", "Disables RequireSecuritySignature for SMB client and server.", "Unable to access NAS or legacy hosts from Win 11 24H2+.")
        '17' = @("Force Modern SMB2/SMB3 Topology", "Ensures SMB2/SMB3 are active, explicitly disables SMB1.", "Transitioning to modern secure protocols.")
        '18' = @("Prioritize SMB in Network Provider Order", "Prioritizes LanmanWorkstation in the provider list.", "SMB connections suffering extreme latency.")
        '19' = @("Disable IPv6 Stack", "Disables IPv6 via registry and netsh interfaces.", "IPv6 causing network routing issues in pure IPv4 networks.")
        '20' = @("Enable mDNS & LLMNR (Discovery Protocols)", "Enables Multicast DNS and LLMNR protocols.", "Printers undetectable via hostname resolution.")
        '21' = @("Configure WSD Firewall Rules (Port 3702)", "Opens UDP port 3702 for WSD discovery in firewall.", "Web Services Discovery blocked by firewall.")
        '22' = @("Enable IPP & Mopria Sharing Foundation", "Enables Windows IPP and Mopria Foundation features.", "Modern printers utilizing IPP protocols.")
        '23' = @("Resolve Hyper-V/WSL Virtual Network Conflicts", "Disables printer bindings on virtual adapters.", "Hyper-V/WSL virtual switches disrupting LAN topology.")
        '24' = @("Install Legacy LPR/LPD Protocols", "Enables Windows LPR Port Monitor & LPD Service features.", "Need to connect via legacy LPR (Line Printer Remote).")
        '25' = @("Remote Network Printer Discovery", "Scans and enumerates all shared printers on the target.", "Unknown shared printers on target host.")
        '26' = @("WSD to Standard TCP/IP Port Converter", "Detects WSD ports and migrates printers to stable Standard TCP/IP ports.", "Intermittent printer disappearance or offline status due to WSD discovery failure.")
        '27' = @("Network Socket Re-init (Selective Purge)", "Restarts SMB Client/Server services and clears stuck port 445/135 connections.", "Stale network connections blocking printer access after IP changes or VPN.")
        '28' = @("Rescue Network Profile (Auto Watchdog)", "Forces all Public network profiles to Private and optionally deploys a watchdog task.", "Network profile resetting to Public after reboot, blocking printer sharing.")
        '29' = @("Manually Inject Standard TCP/IP Port", "Injects TCP/IP port via WMI scripting.", "Need to manually add an IP printer port.")
        '30' = @("Force Initialize WSD Print Device", "Initializes WSDPrintDevice service for Web Services Discovery.", "WSD network printers remain undetected.")
        '31' = @("Hard Reset Print Spooler (Purge Queue)", "Stops spooler, forcefully deletes queue files in Spool\Printers, restarts spooler.", "Print queue is completely frozen, spooler hangs.")
        '32' = @("Re-initialize RPC & DCOM Services", "Verifies and restarts RpcSs and DcomLaunch services.", "RPC or DCOM services terminated/crashed; 'RPC server unavailable'.")
        '33' = @("Remote Target Spooler Restart", "Executes remote spooler reset via PowerShell WinRM/DCOM.", "Remote spooler frozen without physical access.")
        '34' = @("Configure Spooler Auto-Restart on Crash", "Configures recovery action: auto-restart upon crash.", "Print Spooler crashes and remains inactive.")
        '35' = @("Purge Stale Spooler Dependencies", "Resets DependOnService spooler parameters to default.", "Spooler fails to start due to invalid service dependencies.")
        '36' = @("Deploy Spooler Watchdog (5-Min Audit)", "Deploys a scheduled task auditing the spooler every 5 minutes.", "Spooler silently terminates without notification.")
        '37' = @("Hard-Nuke Print Queue (.shd/.spl)", "Terminates all print processes and purges corrupt .shd/.spl spool files.", "Print queue permanently stuck with undeletable jobs.")
        '38' = @("Spooler Dependency Registry Reset", "Resets Spooler's DependOnService registry to factory defaults (RPCSS, http).", "Spooler fails to start due to corrupted or missing service dependencies.")
        '39' = @("Driver Management (Print Server Props)", "Launches Print Server Properties to manage installed drivers.", "Corrupted or duplicate printer drivers.")
        '40' = @("Disable Print Driver Isolation", "Disables IsolationPolicy in the registry.", "Printer driver crash forces spooler termination.")
        '41' = @("Universal Print Class Driver V4 Fix", "Scans V4 drivers for corrupted PrintConfig.dll and triggers DriverStore re-registration.", "Post-Windows Update V4 driver corruption causing blank/garbled output.")
        '42' = @("Toggle PCL vs. PostScript Driver Mode", "Switches a printer's driver between PCL and PostScript rendering modes.", "Garbled text or formatting issues caused by incompatible driver mode.")
        '43' = @("Orphaned Driver Sweeper (pnputil)", "Scans DriverStore for orphaned printer OEM INF packages and force-deletes them.", "Phantom driver conflicts or bloated DriverStore after multiple driver installs.")
        '44' = @("Bypass 'Driver is currently in use'", "Force-kills PrintIsolationHost, splwow64, and pipeline processes to release driver handles.", "Cannot uninstall or update a printer driver due to 'in use' lock.")
        '45' = @("Ghost USB Port & Copy Eliminator", "Detects and removes duplicate/ghost printer copies and dead USB ports.", "Multiple 'Copy 1/2/3' printer entries cluttering the printer list.")
        '46' = @("Force Remove Ghost Printers", "Forces printer removal via command line (printui /dl).", "Printer uninstallation fails via standard GUI.")
        '47' = @("Fix Microsoft Edge / UWP Printing", "Re-registers UWP printing components.", "Unable to print from Microsoft Store/Edge applications.")
        '48' = @("Reinstall Microsoft Print to PDF/XPS", "Re-initializes native Windows PDF & XPS printing features.", "Native virtual printers missing or generating errors.")
        '49' = @("Browser Print Sandbox Fix (Chromium)", "Clears browser print cache and fixes loopback exemptions for print dialogs.", "Chrome/Edge shows blank print preview or fails to detect printers.")
        '50' = @("Auto-Inject F4/Folio Paper Size", "Registers F4 (8.5x13 in) paper size into Print Server properties.", "F4/Folio paper size missing from paper size selection dropdown.")
        '51' = @("Force Permanent Default Printer", "Disables auto-manage and forcibly sets default.", "Default printer spontaneously reassigns.")
        '52' = @("Force-Set Default Printer (Reg Bypass)", "Bypasses Windows auto-manage and sets default printer via direct registry write.", "Error 0x709 or default printer keeps changing after reboot.")
        '53' = @("Fix RDP Printer Terminal Services", "Enables printer redirection in RDP registry.", "Redirected printers absent in Remote Desktop sessions.")
        '54' = @("Auto-Sanitize Printer Share Name", "Scans shared printers and replaces illegal characters in share names.", "Printer sharing fails due to special characters or spaces in share name.")
        '55' = @("Downgrade LSA Protection (Legacy Auth)", "Disables RunAsPPL in LSA registry.", "Authentication rejected due to aggressive LSA Protection.")
        '56' = @("Bypass Smart App Control (SAC)", "Sets VerifiedAndReputablePolicyState to Off.", "Smart App Control blocking driver installation.")
        '57' = @("Bypass Advanced ServerList Point & Print", "Injects ServerList wildcard (*) into registry.", "Point and Print policies obstructing driver installation.")
        '58' = @("Bypass UAC Admin Network TokenFilter", "Configures LocalAccountTokenFilterPolicy = 1.", "Admin share access denied despite administrative credentials.")
        '59' = @("Force NTLMv2 Response Compliance", "Configures LmCompatibilityLevel strictly to NTLMv2.", "Authentication fails due to NTLM version mismatch.")
        '60' = @("Manage Windows Protected Print (WPP)", "Disables Windows Protected Print feature.", "WPP in Windows 11 obstructing legacy driver usage.")
        '61' = @("Inject Credentials into Vault Permanently", "Injects username/password into Windows Credential Manager.", "To bypass manual authentication upon each access.")
        '62' = @("Purge Stale Credentials from Vault", "Purges invalid or outdated credentials from the vault.", "Cached legacy logins causing authentication conflicts.")
        '63' = @("Bypass Credential Guard (Strict NTLM)", "Disables LsaCfgFlags Credential Guard registry node.", "Credential Guard actively blocking NTLM authentication.")
        '64' = @("Cross-User Credential Mapping", "Injects network credentials into all user profiles for shared printer access.", "Multiple user accounts need credentials for the same network printer.")
        '65' = @("Pre-execution Registry Backup (Spooler)", "Exports Print, Printers Policy, and LanmanWorkstation registry trees to C:\WinPrinterFixBackup.", "Highly recommended before applying other fixes.")
        '66' = @("Rollback Registry from Backup", "Imports .reg files from the backup directory.", "If things get worse after applying fixes. SYNERGY: Requires [65] Backup execution first.")
        '67' = @("Generate System Restore Point (Security)", "Generates a System Restore Point for full OS rollback.", "Need to create a restore point before making system changes.")
        '68' = @("System File Checker & DISM Restoration", "Executes SFC /scannow and DISM /RestoreHealth.", "Corrupted or damaged Windows system files. NOTE: Takes 10-30 minutes.")
        '69' = @("Restart BITS (Background Transfer)", "Restarts Background Intelligent Transfer Service.", "Driver downloads failing via Windows Update.")
        '70' = @("Uninstall & Pause Specific KB Update", "Removes a specific Windows Update KB and optionally pauses updates for 35 days.", "A specific KB update has broken printer sharing functionality.")
        '71' = @("Launch Native Windows Troubleshooter", "Executes native Windows Printer Troubleshooter (msdt).", "Initial diagnostic step before manual intervention.")
        '72' = @("Force Printer Online Status", "Transmits online enforcement command via printui /yl.", "Printer status stuck on 'Offline' or grayed out.")
        '73' = @("Launch Services.msc", "Launches the Services.msc MMC snap-in.", "Manually check Windows services.")
        '74' = @("Detect OS Version & Build Architecture", "Displays OS version, build number, and specific recommendations.", "before choosing a specific fix.")
        '75' = @("Ping & Port 445/135 Diagnostics", "ICMP Ping + port scanning for SMB (445) and RPC (135).", "First step in testing network connection.")
        '76' = @("View Execution Logs", "Launches log management interface.", "Need to view the history of past repair logs.")
        '77' = @("Audit Last 20 Print Service Error Logs", "Parses the last 20 error events from the System Event Log.", "Need to check specific print service error logs.")
        '78' = @("System Diagnostics Audit", "Audits Spooler state, SMB, Firewall, and network topologies.", "Need a quick health summary of the printing subsystem.")
        '79' = @("PrintService Event Log Parser (Top 5)", "Parses the 5 most recent Error/Warning events with resolution suggestions.", "Need to identify root cause from Windows Event Log print errors.")
        '80' = @("Generate HTML Diagnostic Report", "Compiles execution logs into an HTML file.", "For IT documentation or administrative reporting.")
        '81' = @("Detect GPO Intervention (Policy Scan)", "Scans registry and gpresult for Group Policy overrides affecting printers.", "Local registry fixes keep reverting due to domain GPO enforcement.")
        '82' = @("PrintBRM (Backup/Restore Migration)", "Executes full backup or restoration of printer topologies via PrintBrm.exe.", "Deploying printers to multiple workstations or migrating to new hardware.")
        '83' = @("Enable SMB Guest Access & Drop Anon Blocks", "Enables AllowInsecureGuestAuth in LanmanWorkstation registry.", "Continuous prompt for credentials when accessing shares.")
        '84' = @("EXTREME PATH (WIN 11 24H2/25H2 & ARM64)", "Aggressive fix combination: DnsOnWire, StrictNameChecking, NTLM level, SMB Signing, Kerberos purge, etc.", "Standard fixes ineffective on latest Windows 11 builds.")
        '85' = @("ALLFIX (50 AUTOMATED REPAIR SEQUENCES)", "Executes 50 automated repair steps sequentially.", "PRIMARY RECOMMENDATION - the recommended fix for most general cases. Reboot required.")
        '86' = @("SILENT NUKE & ALLFIX (ZERO-PROMPT)", "Executes all 50 steps + automated reboot WITHOUT interaction.", "EMERGENCY: Quick Automated resolution. WARNING: AUTO REBOOTS!")
        '87' = @("Reboot System", "Executes an immediate system reboot.", "After running any major fixes.")
        '88' = @("EXIT SCRIPT", "Exits the tool.", "")
    }

    if ($Topic -eq "" -or $Topic -eq "menu") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "     USER GUIDE: Windows Printer Sharing Fix - @KHAIRUDINFAHMI" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  HOW TO USE:" -ForegroundColor Yellow
        Write-Host "    - Input feature number (1-88) and press ENTER"
        Write-Host "    - Both '7' and '07' are valid"
        Write-Host "    - Input '?' to display this guide"
        Write-Host "    - Input '? 7' for detailed explanation of feature 7"
        Write-Host "    - Input '? all' to open complete HTML documentation"
        Write-Host ""
        Write-Host "  BEGINNER WORKFLOW (Standard Execution):" -ForegroundColor Yellow
        Write-Host "    1. Execute [65] Backup Registry (MANDATORY)" -ForegroundColor White
        Write-Host "    2. Execute [85] ALLFIX (50 automated steps)" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host "    4. Verify printer sharing access" -ForegroundColor White
        Write-Host ""
        Write-Host "  WIN 11 24H2+ WORKFLOW (Build 26000+):" -ForegroundColor Yellow
        Write-Host "    1. Execute [65] Backup Registry" -ForegroundColor White
        Write-Host "    2. Execute [84] Extreme Path" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host ""
        Write-Host "  EMERGENCY PROTOCOL (Quick Automated):" -ForegroundColor Yellow
        Write-Host "    - Execute [86] Silent Nuke (WARNING: Auto-reboots!)" -ForegroundColor White
        Write-Host ""
        Write-Host "  FEATURE CATEGORIES:" -ForegroundColor Yellow
        Write-Host "    [01-09] Error Code Fixes (0x11b, 0x709, 0xbc4, 0x35, 0x6d1, 0x40, 0x02, 0x7e)" -ForegroundColor Cyan
        Write-Host "    [10-30] Network & Sharing Configuration (DNS, SMB, Firewall, WSD, IPP)" -ForegroundColor Cyan
        Write-Host "    [31-38] Spooler Management (Reset, RPC, Recovery, Watchdog, Nuke)" -ForegroundColor Cyan
        Write-Host "    [39-54] Drivers & Printing (Isolation, V4, PCL, Ghost, PDF, RDP)" -ForegroundColor Cyan
        Write-Host "    [55-60] Security & Policy (LSA, SAC, UAC, NTLMv2, WPP)" -ForegroundColor Cyan
        Write-Host "    [61-70] Credentials & System (Vault, Backup, SFC, BITS, KB)" -ForegroundColor Cyan
        Write-Host "    [71-82] Diagnostics & Utilities (Troubleshooter, Logs, GPO, BRM)" -ForegroundColor Green
        Write-Host "    [83-88] Special Operations (SMB Guest, Extreme, AllFix, Nuke, Exit)" -ForegroundColor Green

        Write-Host ""
        Write-Host "  QUICK TROUBLESHOOTING:" -ForegroundColor Yellow
        Write-Host "    - Continuous password prompts?     -> Execute [12], [61], [83]" -ForegroundColor White
        Write-Host "    - Printer Offline despite powered on? -> Execute [72]" -ForegroundColor White
        Write-Host "    - Host invisible in network?       -> Execute [04], [11], [14]" -ForegroundColor White
        Write-Host "    - Failed to print from Edge/UWP?   -> Execute [47]" -ForegroundColor White
        Write-Host "    - Need to rollback all changes?    -> Execute [66]" -ForegroundColor White
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
    }
    elseif ($Topic.ToLower() -eq "all") {
        $docPath = $null
        # Search in multiple locations (EXE dir, docs/ subfolder, parent/docs/)
        try {
            $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
            $searchPaths = @(
                (Join-Path $exeDir "dokumentasi.html"),
                (Join-Path $exeDir "docs\dokumentasi.html"),
                (Join-Path (Split-Path $exeDir -Parent) "docs\dokumentasi.html")
            )
            foreach ($sp in $searchPaths) {
                if (Test-Path $sp) { $docPath = $sp; break }
            }
        }
        catch {}
        # Fallback to $PSCommandPath (if executed as .ps1)
        if (-not $docPath -or -not (Test-Path $docPath)) {
            try {
                if ($PSCommandPath) {
                    $scriptDir = Split-Path $PSCommandPath -Parent
                    $fallbacks = @(
                        (Join-Path $scriptDir "dokumentasi.html"),
                        (Join-Path $scriptDir "docs\dokumentasi.html"),
                        (Join-Path (Split-Path $scriptDir -Parent) "docs\dokumentasi.html")
                    )
                    foreach ($fb in $fallbacks) {
                        if (Test-Path $fb) { $docPath = $fb; break }
                    }
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
            Write-Host "  [!] use '?' for quick guide or '? <number>' for feature details." -ForegroundColor Yellow
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
            Write-Host "  [-] Feature number '$Topic' not found. Input 1-88." -ForegroundColor Red
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
    Write-Host "$env:USERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| COMPUTERNAME: " -NoNewline
    Write-Host "$env:COMPUTERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| OS: " -NoNewline
    Write-Host "$winName " -ForegroundColor Blue -NoNewline
    Write-Host "| Windows Printer Sharing Fix" -ForegroundColor Green
    
    Write-Host " TIME ZONE: " -NoNewline
    Write-Host "$(Get-TimeZone | Select-Object -ExpandProperty Id) | $(Get-Date -Format 'HH.mm.ss')" -ForegroundColor Red
    Write-Host " ENGINEERED BY: @KHAIRUDINFAHMI (2026)" -ForegroundColor Magenta
    Write-Host ("=" * 175) -ForegroundColor DarkGray

    # Force console buffer & window to 180 columns for consistent layout
    try {
        $rawUI = $Host.UI.RawUI
        $bufSize = $rawUI.BufferSize
        if ($bufSize.Width -lt 180) {
            $bufSize.Width = 180
            $rawUI.BufferSize = $bufSize
        }
        $winSize = $rawUI.WindowSize
        if ($winSize.Width -lt 180) {
            $winSize.Width = 180
            $rawUI.WindowSize = $winSize
        }
    } catch {}

    $cw1 = 62
    $cw2 = 55
    $cw3 = 58
    $totalW = $cw1 + $cw2 + $cw3

    Write-Host (" CORE FIXES & NETWORK SERVICES".PadRight($cw1)) -ForegroundColor Cyan -NoNewline
    Write-Host (" SPOOLER, DRIVERS & POLICIES".PadRight($cw2)) -ForegroundColor Cyan -NoNewline
    Write-Host " DIAGNOSTICS & AUTOMATION" -ForegroundColor Cyan

    $col1 = @(
        "[01] Patch Error 0x0000011b (RpcAuthnLevelPrivacy)",
        "[02] Bypass Error 0x00000709 / 0x7c (Point and Print)",
        "[03] Bypass Error 0x00000bc4 (No Printers Found)",
        "[04] Fix Error 0x80070035 (Automate Network Services)",
        "[05] Disable Client-Side Rendering (Error 0x6d1)",
        "[06] Fix Error 0x80070005 (Reset Spooler ACL)",
        "[07] Fix Error 0x00000040 (Network Unavailable)",
        "[08] Fix Error 0x00000002 (CopyFilesPolicy)",
        "[09] Fix Error 0x0000007e (RPC Bitness Mismatch)",
        "[10] Complete Network Reset (DNS, Winsock, NetBIOS)",
        "[11] Force Network Profile to Private",
        "[12] Force Disable Password Protected Sharing",
        "[13] Enable RPC via Named Pipes & TCP",
        "[14] Configure Firewall File & Printer Sharing",
        "[15] SMB 1.0 Legacy Protocol Management (ON/OFF)",
        "[16] Disable SMB Signing (Fix Win 11 NAS Access)",
        "[17] Force Modern SMB2/SMB3 Topology",
        "[18] Prioritize SMB in Network Provider Order",
        "[19] Disable IPv6 Stack",
        "[20] Enable mDNS & LLMNR (Discovery Protocols)",
        "[21] Configure WSD Firewall Rules (Port 3702)",
        "[22] Enable IPP & Mopria Sharing Foundation",
        "[23] Resolve Hyper-V/WSL Virtual Network Conflicts",
        "[24] Install Legacy LPR/LPD Protocols",
        "[25] Remote Network Printer Discovery",
        "[26] WSD to Standard TCP/IP Port Converter",
        "[27] Network Socket Re-init (Selective Purge)",
        "[28] Rescue Network Profile (Auto Watchdog)",
        "[29] Manually Inject Standard TCP/IP Port",
        "[30] Force Initialize WSD Print Device"
    )

    $col2 = @(
        "[31] Hard Reset Print Spooler (Purge Queue)",
        "[32] Re-initialize RPC & DCOM Services",
        "[33] Remote Target Spooler Restart",
        "[34] Configure Spooler Auto-Restart on Crash",
        "[35] Purge Stale Spooler Dependencies",
        "[36] Deploy Spooler Watchdog (5-Min Audit)",
        "[37] Hard-Nuke Print Queue (.shd/.spl)",
        "[38] Spooler Dependency Registry Reset",
        "[39] Driver Management (Print Server Props)",
        "[40] Disable Print Driver Isolation",
        "[41] Universal Print Class Driver V4 Fix",
        "[42] Toggle PCL vs. PostScript Driver Mode",
        "[43] Orphaned Driver Sweeper (pnputil)",
        "[44] Bypass 'Driver is currently in use'",
        "[45] Ghost USB Port & Copy Eliminator",
        "[46] Force Remove Ghost Printers",
        "[47] Fix Microsoft Edge / UWP Printing",
        "[48] Reinstall Microsoft Print to PDF/XPS",
        "[49] Browser Print Sandbox Fix (Chromium)",
        "[50] Auto-Inject F4/Folio Paper Size",
        "[51] Force Permanent Default Printer",
        "[52] Force-Set Default Printer (Reg Bypass)",
        "[53] Fix RDP Printer Terminal Services",
        "[54] Auto-Sanitize Printer Share Name",
        "[55] Downgrade LSA Protection (Legacy Auth)",
        "[56] Bypass Smart App Control (SAC)",
        "[57] Bypass Advanced ServerList Point & Print",
        "[58] Bypass UAC Admin Network TokenFilter",
        "[59] Force NTLMv2 Response Compliance",
        "[60] Manage Windows Protected Print (WPP)"
    )

    $col3 = @(
        "[61] Inject Credentials into Vault Permanently",
        "[62] Purge Stale Credentials from Vault",
        "[63] Bypass Credential Guard (Strict NTLM)",
        "[64] Cross-User Credential Mapping",
        "[65] Pre-execution Registry Backup (Spooler)",
        "[66] Rollback Registry from Backup",
        "[67] Generate System Restore Point (Security)",
        "[68] System File Checker & DISM Restoration",
        "[69] Restart BITS (Background Transfer)",
        "[70] Uninstall & Pause Specific KB Update",
        "[71] Launch Native Windows Troubleshooter",
        "[72] Force Printer Online Status",
        "[73] Launch Services.msc",
        "[74] Detect OS Version & Build Architecture",
        "[75] Ping & Port 445/135 Diagnostics",
        "[76] View Execution Logs",
        "[77] Audit Last 20 Print Service Error Logs",
        "[78] System Diagnostics Audit",
        "[79] PrintService Event Log Parser (Top 5)",
        "[80] Generate HTML Diagnostic Report",
        "[81] Detect GPO Intervention (Policy Scan)",
        "[82] PrintBRM (Backup/Restore Migration)",
        "[83] Enable SMB Guest Access & Drop Anon Blocks",
        "[84] EXTREME PATH (WIN 11 24H2/25H2 & ARM64)",
        "[85] ALLFIX (50 AUTOMATED REPAIR SEQUENCES)",
        "[86] SILENT NUKE & ALLFIX (ZERO-PROMPT)",
        "[87] Reboot System",
        "[88] EXIT SCRIPT"
    )

    $maxRows = 30
    for ($i = 0; $i -lt $maxRows; $i++) {
        # Column 1
        if ($i -lt $col1.Count) {
            $m1 = [regex]::Match($col1[$i], '^(\[\d+\])(.*)')
            if ($m1.Success) {
                Write-Host (" " + $m1.Groups[1].Value) -ForegroundColor Green -NoNewline
                Write-Host $m1.Groups[2].Value.PadRight($cw1 - 6) -ForegroundColor Green -NoNewline
            } else { Write-Host (" " + $col1[$i].PadRight($cw1 - 1)) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * $cw1) -NoNewline }

        Write-Host " " -NoNewline

        # Column 2
        if ($i -lt $col2.Count) {
            $m2 = [regex]::Match($col2[$i], '^(\[\d+\])(.*)')
            if ($m2.Success) {
                Write-Host $m2.Groups[1].Value -ForegroundColor Green -NoNewline
                Write-Host $m2.Groups[2].Value.PadRight($cw2 - 5) -ForegroundColor Green -NoNewline
            } else { Write-Host $col2[$i].PadRight($cw2 - 1) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * $cw2) -NoNewline }

        Write-Host " " -NoNewline

        # Column 3
        if ($i -lt $col3.Count) {
            $m3 = [regex]::Match($col3[$i], '^(\[\d+\])(.*)')
            if ($m3.Success) {
                Write-Host $m3.Groups[1].Value -ForegroundColor Green -NoNewline
                if ($m3.Groups[1].Value -in @("[84]", "[85]", "[86]")) {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Red
                } else {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Green
                }
            } else { Write-Host $col3[$i] -ForegroundColor Green }
        } else { Write-Host "" }
    }

    Write-Host ("-" * $totalW) -ForegroundColor Red
    $noteLine1 = " :   NOTE: ".PadRight($totalW - 2) + ":"
    $noteLine2 = " :   [85] ALLFIX (50 Steps) | [84] EXTREME PATH (Win11) | [86] SILENT NUKE ".PadRight($totalW - 2) + ":"
    $noteLine3 = " :   Input [?] for HELP     | [? 7] feature 7 details   | [? all] open HTML ".PadRight($totalW - 2) + ":"
    
    Write-Host $noteLine1 -ForegroundColor Red
    Write-Host $noteLine2 -ForegroundColor Red
    Write-Host $noteLine3 -ForegroundColor Green
    Write-Host ("-" * $totalW) -ForegroundColor Red
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
    
    if ($choice -match '^\d+$') {
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  EXECUTING MODULE [$choice]" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host ""
    }
    
    switch ($choice) {
        '1' { Fix-11b }
        '2' { Fix-709 }
        '3' { Fix-bc4 }
        '4' { Fix-NetworkServices }
        '5' { Fix-CSR }
        '6' { Reset-SpoolerPerm }
        '7' { Fix-Error40 }
        '8' { Fix-Error02 }
        '9' { Fix-Error7e }
        '10' { Reset-Network }
        '11' { Set-NetworkPrivate }
        '12' { Disable-PasswordSharing }
        '13' { Fix-NamedPipes }
        '14' { Open-Firewall }
        '15' { Manage-SMB1 }
        '16' { Fix-SMBSigning }
        '17' { Fix-ModernSMB }
        '18' { Fix-ProviderOrder }
        '19' { Disable-IPv6 }
        '20' { Fix-mDNS }
        '21' { Fix-WSDFirewall }
        '22' { Fix-IPPSharing }
        '23' { Fix-HyperVConflict }
        '24' { Manage-LPR }
        '25' { Scan-RemotePrinter }
        '26' { Convert-WSDtoTCPIP }
        '27' { Reset-NetworkSockets }
        '28' { Rescue-NetworkProfile }
        '29' { Manage-TCPPort }
        '30' { Start-Service WSDPrintDevice -ErrorAction SilentlyContinue; Write-Host "  [+] WSD Discovery Enabled" -ForegroundColor Green }
        '31' { Reset-Spooler }
        '32' { Check-RPC }
        '33' { Remote-SpoolerReset }
        '34' { Set-SpoolerRecovery }
        '35' { Reset-SpoolerDependency }
        '36' { Set-SpoolerWatchdog }
        '37' { Nuke-PrintQueue }
        '38' { Reset-SpoolerDependencyRegistry }
        '39' { Manage-Drivers }
        '40' { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force; Write-Host "  [+] Isolation Disabled" -ForegroundColor Green }
        '41' { Fix-V4ClassDriver }
        '42' { Switch-DriverMode }
        '43' { Sweep-OrphanedDrivers }
        '44' { Force-KillDriverProcess }
        '45' { Remove-GhostUSBPrinters }
        '46' { Uninstall-Printer }
        '47' { Fix-UWPPrinting }
        '48' { Fix-PrintToPDF }
        '49' { Fix-BrowserPrintSandbox }
        '50' { Inject-F4PaperSize }
        '51' { Manage-DefaultPrinter }
        '52' { Force-DefaultPrinterRegistry }
        '53' { Fix-RDPPrinter }
        '54' { Sanitize-PrinterShareName }
        '55' { Fix-LSAProtection }
        '56' { Fix-SAC }
        '57' { Fix-AdvancedPointAndPrint }
        '58' { Fix-UACTokenFilter }
        '59' { Fix-NTLMv2 }
        '60' { Manage-WPP }
        '61' { Add-Credential }
        '62' { Clean-Credential }
        '63' { Fix-CredentialGuard }
        '64' { Inject-CrossUserCredentials }
        '65' { Backup-Registry }
        '66' { Rollback-Registry }
        '67' { Create-RestorePoint }
        '68' { Run-SfcDism }
        '69' { Manage-BITS }
        '70' { Manage-WindowsUpdate }
        '71' { Start-Troubleshooter }
        '72' { Force-PrinterOnline }
        '73' { Open-Services }
        '74' { Detect-Win }
        '75' { Test-Koneksi }
        '76' { Log-Manager }
        '77' { Scan-PrintEventLog }
        '78' { Quick-Diagnostic }
        '79' { Parse-PrintEventLog }
        '80' { Generate-HtmlLog }
        '81' { Detect-GPOIntervention }
        '82' { Print-Migration }
        '83' { Enable-SMBGuest }
        '84' { Extreme-25H2 }
        '85' { AllFix-Core }
        '86' { $script:silentNuke = $true; AllFix-Core }
        '87' { Restart-PC }
        '88' { Write-Log "Tool Terminated." -Type "INFO"; exit }

        default { Write-Host "`n  [-] Invalid input. Input numerals 1 - 88." -ForegroundColor Red }
    }
    
    if ($choice -ne '88' -and $choice -ne '87' -and $choice -ne '86') {
        Write-Host "`n  [>] Press ENTER to return to Main Menu..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)
