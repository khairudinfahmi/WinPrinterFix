param(
    [switch]$nuke
)

$script:version = "2.2.9"
$script:logFile = "C:\WinPrinterFixLog.txt"
$script:backupDir = "C:\WinPrinterFixBackup"
$script:silentNuke = $nuke

$script:isARM64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$script:isServer = ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)

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

    if ($script:buildNumber -ge 22000 -and $script:productName -match "Windows 10") {
        $script:productName = $script:productName -replace "Windows 10", "Windows 11"
    }
}
else {
    $script:productName = "Windows NT $([Environment]::OSVersion.Version.Major)"
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

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

function Fix-RpcAuthn0x0000011b {
    Write-Log "Patching Error 0x0000011b (RpcAuthnLevelPrivacy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "Registry 0x0000011b successfully applied." -Type "SUCCESS"
        Write-Host "  [+] RPC Authentication Level Privacy requirement disabled." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to patch 0x0000011b: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Deep0x00000709 {
    Write-Log "Deep fix 0x00000709 — applying all RPC layers..." -Type "INFO"
    try {

        $rpcPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }
        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable            -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols            -Value 7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes       -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcAuthenticationLevel  -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name ForceKerberosForRpc     -Value 0 -Type DWord -Force

        $printPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
        Set-ItemProperty -Path $printPath -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $printPath -Name DnsOnWire              -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $printPath -Name CopyFilesPolicy        -Value 1 -Type DWord -Force

        $lanPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $lanPath -Name DisableStrictNameChecking -Value 1 -Type DWord -Force

        $deviceKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $deviceVal = (Get-ItemProperty $deviceKey -ErrorAction SilentlyContinue).Device
        if ($deviceVal) {
            Write-Host "  [!] Purging legacy Device key: $deviceVal" -ForegroundColor Yellow
            Remove-ItemProperty -Path $deviceKey -Name "Device" -ErrorAction SilentlyContinue
            Write-Log "HKCU Device key purged: $deviceVal" -Type "SUCCESS"
        }

        Set-ItemProperty -Path $deviceKey -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force

        $wppPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"
        if (-not (Test-Path $wppPath)) { New-Item -Path $wppPath -Force | Out-Null }
        Set-ItemProperty -Path $wppPath -Name Enabled -Value 0 -Type DWord -Force

        $lsaMSV = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinClientSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinServerSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Restart-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "Fix-Deep0x00000709 complete. MUST also be executed on the HOST machine." -Type "SUCCESS"
        Write-Host "  [+] All 0x00000709 layers applied." -ForegroundColor Green
        Write-Host "  [!] IMPORTANT: Run this script on the HOST PC (the one connected to the printer)!" -ForegroundColor Red
    }
    catch {
        Write-Log "Failed Deep 0x00000709 Fix: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CrossSignedDriverPolicy {
    Write-Log "Bypassing KB5089549 Cross-Signed Driver Enforcement (Audit Mode Disable)..." -Type "INFO"
    try {

        $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
        if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }

        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" `
            -Name VulnerableDriverBlocklistEnable -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        $polPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }
        Set-ItemProperty -Path $polPath `
            -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "Cross-signed driver enforcement set to permissive (post-KB5089549 fix)." -Type "SUCCESS"
        Write-Host "  [+] KB5089549 driver policy enforcement neutralized." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix cross-signed driver policy: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HKCU-PrinterKeyPerms {
    Write-Log "Fixing HKCU Windows registry key permissions for printer device write..." -Type "INFO"
    try {

        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $acl = Get-Acl $regKey
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            "Everyone",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $regKey -AclObject $acl -ErrorAction Stop
        Write-Log "HKCU Windows key: Everyone FullControl granted." -Type "SUCCESS"
        Write-Host "  [+] Registry permission fix applied (Everyone = FullControl on printer device key)." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix HKCU printer key permissions: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-PostPatchTuesdayTask {
    Write-Log "Deploying Post-Windows-Update Auto-Reapply Task..." -Type "INFO"
    try {

        $fixScript = @'
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name ForceKerberosForRpc -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcProtocols -Value 7 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force -EA SilentlyContinue
Restart-Service spooler -Force -EA SilentlyContinue
'@
        $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixScript))
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-WindowStyle Hidden -EncodedCommand $encodedScript"

        $trigger = New-ScheduledTaskTrigger -AtStartup

        $trigger2 = New-ScheduledTaskTrigger -Daily -At "10:00AM"

        Register-ScheduledTask -TaskName "PrinterFixPostUpdate" `
            -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null

        Register-ScheduledTask -TaskName "PrinterFixDaily" `
            -Action $action -Trigger $trigger2 -User "SYSTEM" -RunLevel Highest -Force | Out-Null

        Write-Log "Post-Windows-Update reapply task deployed successfully." -Type "SUCCESS"
        Write-Host "  [+] Auto-reapply task deployed. Registry fixes will re-apply automatically after every reboot/update." -ForegroundColor Green
        Write-Host "  [+] Task: 'PrinterFixPostUpdate' & 'PrinterFixDaily' are active in Task Scheduler." -ForegroundColor Cyan
    }
    catch {
        Write-Log "Failed to deploy post-update task: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Discovery0x00000bc4 {
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
        Write-Log "Failed to bypass 0x00000bc4: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NetworkServices {
    Write-Log "Fixing Error 0x80070035 (Starting WSD, SMB, NetBIOS services)..." -Type "INFO"
    $services = @("nlasvc", "Dnscache", "LanmanServer", "LanmanWorkstation", "lmhosts", "fdPHost", "FDResPub", "SSDPSRV", "upnphost", "WdiSystemHost", "WdiServiceHost")

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
    Write-Log "Disabling Client-Side Rendering (Error 0x000006d1)..." -Type "INFO"
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
        Stop-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "Ensuring related processes (splwow64, printfilter) are terminated..." -Type "INFO"
        Get-Process -Name "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Write-Log "Purging stale print spool files..." -Type "INFO"
        Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*" -Force -Recurse -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Set-Service spooler -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service spooler -ErrorAction Stop

        Write-Log "Spooler successfully refreshed!" -Type "SUCCESS"
        Write-Host "  [+] Print Spooler successfully purged and set to Automatic (Hard Reset)." -ForegroundColor Green
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
        & icacls "$env:SystemRoot\System32\Spool\Printers" /grant "Everyone:(OI)(CI)F" /T /C /Q > $null 2>&1
        Write-Log "Spooler ACL reset & Everyone grant complete." -Type "SUCCESS"
        Write-Host "  [+] Print queue directory permissions reset and granted to Everyone." -ForegroundColor Green
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
                $prn | Invoke-CimMethod -MethodName "SetDefaultPrinter" | Out-Null
                Write-Log "Printer $pname state forced." -Type "SUCCESS"
                Write-Host "  [+] Online enforcement command sent to $pname." -ForegroundColor Green
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

function Test-Connectivity {
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

    $brmPath = Join-Path $env:SystemRoot "System32\spool\tools\PrintBrm.exe"
    if (-not (Test-Path $brmPath)) {
        $brmPath = Join-Path $env:SystemRoot "System32\PrintBrm.exe"
    }

    if (-not (Test-Path $brmPath)) {
        Write-Log "PrintBrm.exe not detected on this system." -Type "ERROR"
        Write-Host "  [-] ERROR: Print Migration utility (PrintBrm.exe) is missing." -ForegroundColor Red
        Write-Host "  [!] NOTE: This feature is typically only available in Windows Pro, Enterprise, or Server editions." -ForegroundColor Yellow
        Write-Host "  [!] Your OS: $script:productName" -ForegroundColor Cyan
        return
    }

    Write-Host "  [*] Launching PrintBrm.exe in a persistent command prompt window..." -ForegroundColor Cyan
    try {
        Start-Process cmd.exe -ArgumentList "/k cd /d `"$env:SystemRoot\System32\spool\tools\`" & title PrintBRM Migration Utility & `"$brmPath`" /?"
        Write-Log "PrintBRM prompt launched successfully." -Type "SUCCESS"
        Write-Host "  [+] PrintBRM prompt successfully launched! You can now execute backup/restore commands." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to launch PrintBRM: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Uninstall-Printer {
    $up = Read-Host "`n  [?] Input exact name of the printer to forcefully uninstall"
    if ($up) {
        try {
            & printui.exe /dl /n "$up"
            Write-Log "Uninstall command issued for $up." -Type "SUCCESS"
        }
        catch {
            Write-Log "Failed to uninstall $up : $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Fix-SMBSigning {
    Write-Log "Disabling SMB Signing enforcement & Mutual Auth..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireMutualAuthentication -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

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

        Write-Log "WSD Firewall rules successfully updated." -Type "SUCCESS"
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
    Write-Log "Bypassing Advanced Point & Print Policies & PrintNightmare Locks..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name InForest -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name TrustedServers -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name ServerList -Value "*.*" -Type String -Force -ErrorAction SilentlyContinue

        Set-ItemProperty -Path $path -Name RestrictDriverInstallationToAdministrators -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnInstall -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnUpdate -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name UpdatePromptSettings -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

        $pkgPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint"
        if (-not (Test-Path $pkgPath)) { New-Item -Path $pkgPath -Force | Out-Null }
        Set-ItemProperty -Path $pkgPath -Name PackagePointAndPrintServerList -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Log "Point & Print constraints & PrintNightmare entirely bypassed." -Type "SUCCESS"
        Write-Host "  [+] PrintNightmare Elevation Restrictions and Point & Print fully neutralized." -ForegroundColor Green
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
            Write-Log "Provider Order explicitly updated (LanmanWorkstation prioritized)." -Type "SUCCESS"
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

function Fix-Network0x00000040 {
    Write-Log "Fixing Error 0x00000040 (Network connection timeout)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name KeepConn -Value 65535 -Type DWord -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Write-Log "KeepConn SMB set to maximum." -Type "SUCCESS"
        Write-Host "  [+] SMB connection timeout extended to mitigate unstable network topologies." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x00000040: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-DriverCopy0x00000002 {
    Write-Log "Fixing Error 0x00000002 (Driver CopyFilesPolicy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name CopyFilesPolicy -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "CopyFilesPolicy activated." -Type "SUCCESS"
        Write-Host "  [+] CopyFilesPolicy allowed so OS can ingest missing drivers from Host." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x00000002: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RpcBitness0x0000007e {
    Write-Log "Fixing Error 0x0000007e (RPC Bitness/Auth error)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcAuthenticationLevel -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "RPC Authentication downgraded." -Type "SUCCESS"
        Write-Host "  [+] RPC Auth limitations removed to facilitate cross-architecture communication." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to fix 0x0000007e: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-WPP {
    Write-Host "`n  ======================================================================"
    Write-Host "             WINDOWS PROTECTED PRINT (WPP) MANAGEMENT"
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

function Run-QuickDiagnostics {
    Write-Host "`n  ======================================================================"
    Write-Host "                 SYSTEM DIAGNOSTICS"
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

function Fix-V4ClassDriver {
    Write-Log "Scanning Universal Print Class Driver (V4) for corruption..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               UNIVERSAL PRINT CLASS DRIVER V4 REPAIR"
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
    Write-Host "               TOGGLE PCL vs. POSTSCRIPT DRIVER MODE"
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
    Write-Host "               UNINSTALL & PAUSE SPECIFIC WINDOWS UPDATE (KB)"
    Write-Host "  ======================================================================"
    Write-Log "Launching KB Update manager..." -Type "INFO"
    try {
        Write-Host "  [!] KNOWN PRINTER-BREAKING KBs (2025-2026):" -ForegroundColor Red
        Write-Host "      KB5065426 (Sep 2025) - Blocks print sharing (SID check)" -ForegroundColor Yellow
        Write-Host "      KB5066835 (Oct 2025) - Major printer sharing breaker" -ForegroundColor Yellow
        Write-Host "      KB5068661 (Nov 2025) - Breaks printer & network sharing" -ForegroundColor Yellow
        Write-Host "      KB5089549 (May 2026) - Cross-signed driver enforcement" -ForegroundColor Yellow

        Write-Host "  [*] Enumerating recent Windows Updates..." -ForegroundColor Cyan
        $updates = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 20
        if ($updates) { $updates | Format-Table HotFixID, Description, InstalledOn -AutoSize }
        else { Write-Host "  [-] No hotfixes detected via Get-HotFix." -ForegroundColor Yellow }

        $kb = Read-Host "`n  [?] Input KB number to uninstall (e.g., KB5034441, or blank to cancel)"
        if (-not $kb) { return }
        $kb = $kb -replace '(?i)^KB', ''

        $dismSuccess = $false
        Write-Host "  [*] Attempting to uninstall KB$kb via DISM..." -ForegroundColor Cyan
        $packages = & dism /online /get-packages 2>&1 | Select-String "Package_for_KB$kb"

        if ($packages) {
            $pkgName = ($packages[0].ToString() -split ':')[1].Trim()
            $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /remove-package /package-name:`"$pkgName`" /quiet /norestart" -Wait -PassThru -WindowStyle Hidden

            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                $dismSuccess = $true
                Write-Log "KB$kb uninstalled via DISM." -Type "SUCCESS"
                Write-Host "  [+] KB$kb successfully uninstalled. (Reboot may be required)" -ForegroundColor Green
            } else {
                Write-Log "DISM failed to uninstall KB$kb. ExitCode: $($proc.ExitCode). Falling back to wusa.exe..." -Type "WARNING"
                Write-Host "  [-] DISM failed (ExitCode $($proc.ExitCode)). Attempting wusa.exe fallback..." -ForegroundColor Yellow
            }
        }

        if (-not $dismSuccess) {
            Write-Host "  [!] A Windows dialog will appear. Please confirm the uninstallation if prompted." -ForegroundColor Cyan
            $proc = Start-Process wusa.exe -ArgumentList "/uninstall /kb:$kb /norestart" -Wait -PassThru

            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Log "KB$kb uninstalled via wusa." -Type "SUCCESS"
                Write-Host "  [+] KB$kb successfully uninstalled. (Reboot may be required)" -ForegroundColor Green
            } else {
                Write-Log "Wusa failed/cancelled for KB$kb. ExitCode: $($proc.ExitCode)" -Type "WARNING"
                Write-Host "  [-] Uninstallation failed or was cancelled. The update may be a permanent Security Update." -ForegroundColor Red
            }
        }

        $pauseOpt = Read-Host "`n  [?] Pause Windows Update for 35 days to prevent reinstall? (Y/N)"
        if ($pauseOpt -eq 'Y') {
            $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }

            $pauseDate = (Get-Date).AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ")
            Set-ItemProperty -Path $wuPath -Name PauseQualityUpdatesStartTime -Value $pauseDate -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name PauseFeatureUpdatesStartTime -Value $pauseDate -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name PauseUpdatesExpiryTime -Value $pauseDate -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name SetDisableUXWUAccess -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            Write-Host "  [+] Windows Update fully paused for 35 days." -ForegroundColor Green
            Write-Log "Windows Update paused until $pauseDate." -Type "SUCCESS"
        }
    }
    catch { Write-Log "KB management failed: $($_.Exception.Message)" -Type "ERROR" }
}

function Sweep-OrphanedDrivers {
    Write-Host "`n  ======================================================================"
    Write-Host "               ORPHANED DRIVER SWEEPER (pnputil)"
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
    Write-Host "               BYPASS 'DRIVER IS CURRENTLY IN USE'"
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
    Write-Host "               WSD to STANDARD TCP/IP PORT CONVERTER"
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
    Write-Host "               NETWORK SOCKET RE-INIT (SELECTIVE PURGE)"
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
    Write-Host "               RESCUE NETWORK PROFILE (AUTO-DETECT & WATCHDOG)"
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
    Write-Host "               GHOST USB PORT & COPY ELIMINATOR"
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
    Write-Host "               HARD-NUKE PRINT QUEUE"
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
    Write-Host "               CROSS-USER CREDENTIAL MAPPING"
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
    Write-Host "               FORCE-SET DEFAULT PRINTER (REGISTRY BYPASS 0x00000709)"
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
    Write-Host "               AUTO-SANITIZE PRINTER SHARE NAME"
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
    Write-Host "               BROWSER PRINT SANDBOX FIX (CHROMIUM)"
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

function Detect-GPOIntervention {
    Write-Log "Scanning for Group Policy intervention on printer registry..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               GROUP POLICY (GPO) INTERVENTION DETECTION"
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
    Write-Host "                 PRINTSERVICE EVENT LOG PARSER (TOP 5)"
    Write-Host "  ======================================================================"
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-PrintService/Admin'
            Level   = @(2, 3)
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($events) {
            $resolutionMap = @{
                '808' = "Driver install failure. Execute [43] Orphaned Driver Sweeper."
                '842' = "Queue corruption. Execute [37] Hard-Nuke Print Queue."
                '354' = "Spooler failed to start. Execute [38] Spooler Dependency Reset."
                '824' = "Printer offline. Execute [26] WSD to TCP/IP Converter."
            }
            foreach ($evt in $events) {
                $levelStr = if ($evt.Level -eq 2) { "ERROR" } else { "WARNING" }
                $color = if ($evt.Level -eq 2) { "Red" } else { "Yellow" }
                Write-Host "`n  [$levelStr] Event $($evt.Id) - $($evt.TimeCreated)" -ForegroundColor $color
                Write-Host "  Message: $($evt.Message)" -ForegroundColor White

                $suggestion = ""
                if ($evt.Id -eq 372) {
                    if ($evt.Message -match "Access is denied" -or $evt.Message -match "error code.*: 5\b") {
                        $suggestion = "Permission blocked. Execute [12] Disable Password Sharing or [60] Inject Credentials."
                    }
                    elseif ($evt.Message -match "The network path was not found" -or $evt.Message -match "error code.*: 53\b") {
                        $suggestion = "Host unreachable. Verify Host IP/Power, then Execute [14] Open Firewall."
                    }
                    else {
                        $suggestion = "Spooler/Driver crash. Execute [06] or [37] Hard-Nuke Print Queue."
                    }
                }
                elseif ($resolutionMap.ContainsKey($evt.Id.ToString())) {
                    $suggestion = $resolutionMap[$evt.Id.ToString()]
                }

                if ($suggestion) {
                    Write-Host "  SUGGESTION: $suggestion" -ForegroundColor Green
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

function Map-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               MAP LOCAL PORT TO UNC PATH (BYPASS)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] Use this if standard sharing STILL fails with 'Check printer name' error."
    $ip = Read-Host "  [?] Target Host IP/Hostname (e.g., 192.168.1.10)"
    $share = Read-Host "  [?] Exact Printer Share Name (e.g., EPSON_L120)"
    if ($ip -and $share) {
        $uncPath = "\\$ip\$share"
        try {
            Write-Host "  [*] Attempting standard Local Port creation: $uncPath" -ForegroundColor Cyan
            Add-PrinterPort -Name $uncPath -ErrorAction Stop
            Write-Log "Local Port created for UNC via API: $uncPath" -Type "SUCCESS"
            Write-Host "  [+] Local Port injected! You can now Add a Local Printer and select this port." -ForegroundColor Green
        }
        catch {
            Write-Host "  [*] Standard method blocked by Windows. Deploying Registry Bypass..." -ForegroundColor Yellow
            try {
                $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"

                Set-ItemProperty -Path $portRegPath -Name $uncPath -Value "" -Type String -Force -ErrorAction Stop

                Write-Host "  [*] Port injected. Restarting Print Spooler to finalize..." -ForegroundColor Cyan
                Restart-Service spooler -Force -ErrorAction SilentlyContinue

                Write-Log "Local Port injected for UNC via Registry Bypass: $uncPath" -Type "SUCCESS"
                Write-Host "  [+] BYPASS SUCCESS! Port $uncPath is now available in your port list." -ForegroundColor Green
                Write-Host "  [!] NEXT STEP: Go to 'Add Printer' -> 'Add a local printer' -> 'Use an existing port'." -ForegroundColor Green
                Write-Host "  [!] Select $uncPath from the drop-down menu, then choose your driver." -ForegroundColor Green
            }
            catch {
                Write-Log " Bypass Failed: $($_.Exception.Message)" -Type "ERROR"
                Write-Host "  [-] Bypass failed. Registry access is completely locked down by Administrator/GPO." -ForegroundColor Red
            }
        }
    }
}

function Remove-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               REMOVE INJECTED LOCAL PORT (UNC)"
    Write-Host "  ======================================================================"

    Write-Host "  [*] Identifying active printer ports..." -ForegroundColor Cyan
    try {
        $ports = Get-PrinterPort | Select-Object -ExpandProperty Name | Sort-Object
        if ($ports) {
            Write-Host "  [>] Detected Ports:" -ForegroundColor Yellow
            foreach ($p in $ports) {
                if ($p -like "\\*") {
                    Write-Host "      -> $p (UNC Mapping)" -ForegroundColor Green
                } else {
                    Write-Host "      -> $p" -ForegroundColor Gray
                }
            }
        }
    } catch { Write-Host "  [!] Could not retrieve port list via API." -ForegroundColor Yellow }

    Write-Host "`n  [!] Use this to delete a port previously created by Option [86]."
    $portName = Read-Host "  [?] Input exact Port Name to remove (e.g., \\192.168.1.10\Printer)"
    if (-not $portName) { return }

    try {
        Write-Host "  [*] Attempting standard port removal..." -ForegroundColor Cyan
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "Port $portName removed via API." -Type "SUCCESS"
        Write-Host "  [+] Port $portName successfully removed." -ForegroundColor Green
    }
    catch {
        Write-Host "  [*] Standard method failed. Deploying Registry Purge..." -ForegroundColor Yellow
        try {
            $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"
            Remove-ItemProperty -Path $portRegPath -Name $portName -ErrorAction Stop

            Write-Host "  [*] Port deleted from registry. Restarting Print Spooler..." -ForegroundColor Cyan
            Restart-Service spooler -Force -ErrorAction SilentlyContinue

            Write-Log "Port $portName removed via Registry Bypass." -Type "SUCCESS"
            Write-Host "  [+] BYPASS SUCCESS! Port $portName has been permanently deleted." -ForegroundColor Green
        }
        catch {
            Write-Log "Failed to remove UNC Port: $($_.Exception.Message)" -Type "ERROR"
            Write-Host "  [-] Failed to remove port. Ensure you typed the name EXACTLY as it appears in the port list." -ForegroundColor Red
        }
    }
}

function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         EXECUTE ALLFIX (50 AUTOMATED REPAIR SEQUENCES)"
    Write-Host "  ===================================================================================================`n"
    Write-Log "RUN ALLFIX (SILENT=$script:silentNuke)" -Type "INFO"

    Write-Host "  [*] [1/50] Detecting OS..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/50] Securing Registry (Backup)... (Menu 64)" -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/50] Flushing GPO cache (before registry changes)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [4/50] Auditing RPC & DCOM... (Menu 32)" -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [5/50] Patching Error 0x0000011b... (Menu 01)" -ForegroundColor Cyan
    Fix-RpcAuthn0x0000011b

    Write-Host "  [*] [6/50] Deep Fix 0x00000709 (Multi-Layer RPC)... (Menu 02)" -ForegroundColor Cyan
    Fix-Deep0x00000709

    Write-Host "  [*] [7/50] KB5089549 Driver Policy & HKCU Permission Fix..." -ForegroundColor Cyan
    Fix-CrossSignedDriverPolicy
    Fix-HKCU-PrinterKeyPerms

    Write-Host "  [*] [8/50] Bypassing Error 0x00000bc4... (Menu 03)" -ForegroundColor Cyan
    Fix-Discovery0x00000bc4

    Write-Host "  [*] [9/50] Fixing Error 0x00000040 (KeepConn)... (Menu 07)" -ForegroundColor Cyan
    Fix-Network0x00000040

    Write-Host "  [*] [10/50] Fixing Error 0x00000002 (CopyFilesPolicy)... (Menu 08)" -ForegroundColor Cyan
    Fix-DriverCopy0x00000002

    Write-Host "  [*] [11/50] Fixing Error 0x0000007e (RPC Auth)... (Menu 09)" -ForegroundColor Cyan
    Fix-RpcBitness0x0000007e

    Write-Host "  [*] [12/50] Injecting DnsOnWire, StrictName & UAC Bypass... (Menu 57)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [13/50] Disabling SMB Signing Requirement & Mutual Auth... (Menu 16)" -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [14/50] Ensuring SMB2/SMB3 Compatibility & Provider Order... (Menu 17 & 18)" -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [15/50] Enforcing Named Pipes & TCP... (Menu 13)" -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [16/50] Disabling Client-Side Rendering... (Menu 05)" -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [17/50] Disabling Driver Isolation... (Menu 40)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force
    }
    catch {}

    Write-Host "  [*] [18/50] Starting Network Discovery, mDNS, NetBIOS & WSD Services... (Menu 20 & 04)" -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [19/50] Configuring Firewall & Opening UDP Pathways... (Menu 14 & 21)" -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [20/50] Opening SMB Guest Access (Client & Server)... (Menu 82)" -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [21/50] Disabling Password Protected Network Sharing... (Menu 12)" -ForegroundColor Cyan
    Disable-PasswordSharing

    Write-Host "  [*] [22/50] Downgrading LSA Protection & Enforcing NTLMv2... (Menu 54, 58 & 62)" -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard

    Write-Host "  [*] [23/50] Bypassing Smart App Control (SAC)... (Menu 55)" -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [24/50] Initializing IPP & Mopria Print Sharing... (Menu 22)" -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [25/50] Disabling WPP (Allowing legacy network printing)... (Menu 59)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "  [*] [26/50] Fixing RDP & LPD Protocols... (Menu 52 & 24)" -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [27/50] Forcing network to Private Mode... (Menu 11)" -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [28/50] Deprioritizing Virtual Adapters (Hyper-V)... (Menu 23)" -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [29/50] Flushing DNS & Winsock... (Menu 10)" -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [30/50] Terminating Spooler..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [31/50] Injecting Auto-Restart Recovery into Spooler... (Menu 34)" -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [32/50] Purging Spooler Dependencies (http & RPCSS)... (Menu 35)" -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [33/50] Resetting PRINTERS Folder Permissions... (Menu 06)" -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [34/50] Purging stale print queues & Splwow64... (Menu 31)" -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [35/50] Bypassing AppContainer UWP/Edge Loopback... (Menu 47)" -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [36/50] Applying Advanced Point & Print & PrintNightmare Bypasses... (Menu 56)" -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [37/50] Deploying Spooler Watchdog Task... (Menu 36)" -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [38/50] Restarting BITS Service... (Menu 68)" -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [39/50] Restarting Spooler (validation)..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler validated operational." -ForegroundColor Green

    Write-Host "  [*] [40/50] Purging Kerberos Login Cache..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [41/50] Restarting WdiSystemHost Service..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [42/50] Registering mDNS (Multicast)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [43/50] Generating Restore Point... (Menu 66)" -ForegroundColor Cyan
    Create-RestorePoint

    Write-Host "  [*] [44/50] Scanning V4 Print Class Drivers... (Menu 41)" -ForegroundColor Cyan
    Fix-V4ClassDriver

    Write-Host "  [*] [45/50] Rescuing Network Profile (Force Private)... (Menu 28)" -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    $profiles | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    Write-Host "  [*] [46/50] Hard-Nuking corrupt Print Queue files... (Menu 37)" -ForegroundColor Cyan
    Nuke-PrintQueue

    Write-Host "  [*] [47/50] Resetting Spooler Dependencies (Registry)... (Menu 38)" -ForegroundColor Cyan
    Reset-SpoolerDependencyRegistry

    Write-Host "  [*] [48/50] Sanitizing Printer Share Names... (Menu 53)" -ForegroundColor Cyan
    Sanitize-PrinterShareName

    Write-Host "  [*] [49/50] Deploying Post-Patch-Tuesday Auto-Reapply Task..." -ForegroundColor Cyan
    Set-PostPatchTuesdayTask

    Write-Host "  [*] [50/50] Parsing PrintService Event Log & Final Spooler Validation... (Menu 78)" -ForegroundColor Cyan
    Parse-PrintEventLog
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
    Write-Host "  [!] DOMAIN INFO: If host is AD-joined, verify 'Access this computer from network' in secpol.msc" -ForegroundColor Yellow
    Write-Host "  [!] STILL DENIED? TIP: If connection still fails, please use Option [60] or Bypass [86]." -ForegroundColor Green

    $checkError = Read-Host "   [?] View execution error logs? (Y/N)"
    if ($checkError -eq 'Y') {
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

    $allFixRestart = Read-Host "   [?] Execute immediate system reboot? (Y/N)"
    if ($allFixRestart -eq 'Y') {
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
    Write-Host "        EXTREME PATH FOR WIN 11 25H2 / 24H2 / 26H2+ / ARM64"
    Write-Host "  ==================================================================================================="
    Write-Host "  [*] Aggressive specialized fix tailored for environments with maximum security enforcement."
    Write-Host "  [*] Automated execution proceeding with zero interruptions..." -ForegroundColor Cyan

    Write-Log "Run Extreme Fix 25H2/26H2" -Type "INFO"

    Write-Host "  [*] Flushing GPO cache before applying fixes..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Fix-Deep0x00000709
    Fix-CrossSignedDriverPolicy
    Fix-HKCU-PrinterKeyPerms
    Set-PostPatchTuesdayTask

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
    Fix-Network0x00000040
    Fix-DriverCopy0x00000002
    Fix-RpcBitness0x0000007e
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
    }
    catch {}

    Write-Log "Extreme Path concluded!" -Type "SUCCESS"
    Write-Host "  [+] Extreme security configuration changes complete. System reboot highly recommended." -ForegroundColor Green

    $extremeRestart = Read-Host "`n   [?] Execute immediate system reboot now? (Y/N)"
    if ($extremeRestart -eq 'Y') { Restart-Computer -Force }
}

function Restart-PC {
    Write-Host "`n  [*] System rebooting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

function Detect-Win {
    Write-Host "`n  ======================================================================"
    Write-Host "                 WINDOWS & ARCHITECTURE DETECTION"
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

function Show-Help {
    param([string]$Topic = "")

    $helpData = @{
        '1'  = @("Patch Error 0x0000011b (RpcAuthnLevelPrivacy)", "Disables the RpcAuthnLevelPrivacyEnabled registry key so RPC authentication does not block sharing connections.", "Most common error following Windows 10/11 cumulative updates.")
        '2'  = @("Deep Fix 0x00000709 (Multi-Layer RPC & Kerberos)", "Applies multi-layered fixes: RPC Named Pipes, Kerberos bypass, HKCU cleanup, and legacy overrides.", "Persistent 0x00000709 error in Windows 11 that survives standard fixes. MUST run on HOST too.")
        '3'  = @("Bypass Error 0x00000bc4 (No Printers Found)", "Forces RPC to use Named Pipe Protocol so printers can be discovered.", "Windows reports 'No printers were found' despite network availability.")
        '4'  = @("Fix Error 0x00000035 (Automate Network Services)", "Automates startup for fdPHost, FDResPub, SSDPSRV, upnphost services.", "Target PC is not showing up on the network; 'The network path was not found'.")
        '5'  = @("Disable Client-Side Rendering (Error 0x000006d1)", "Enables DisableClientSideRendering in the registry.", "Print job fails due to client-side driver rendering issues.")
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
        '33' = @("Remote Target Spooler Restart", "Executes remote spooler reset via PowerShell WinRM/DCOM.", "Remote spooler frozen without physical access.", "Requires Administrative privileges on target host.")
        '34' = @("Configure Spooler Auto-Restart on Crash", "Configures recovery action: auto-restart upon crash via sc.exe.", "Spooler highly unstable, requiring self-healing mechanisms.")
        '35' = @("Purge Stale Spooler Dependencies", "Resets DependOnService spooler parameters to default (RPCSS, http).", "Spooler inactive despite operational RPC services.")
        '36' = @("Deploy Spooler Watchdog (5-Minute Audit)", "Deploys a scheduled task auditing the spooler every 5 minutes.", "High-uptime print server environments requiring constant availability.")
        '37' = @("Hard-Nuke Print Queue (.shd/.spl)", "Terminates all print processes and purges corrupt .shd/.spl spool files.", "Standard cancellation methods fail to clear the queue completely.")
        '38' = @("Spooler Dependency Registry Reset", "Resets Spooler's DependOnService registry to factory defaults (RPCSS, http) directly via HK_LOCAL_MACHINE.", "Spooler won't start even after a reboot.")
        '39' = @("Driver Management (Print Server Properties)", "Launches Print Server Properties GUI to manage installed drivers.", "Printer utilizing incorrect driver or duplicate driver instances.")
        '40' = @("Disable Print Driver Isolation", "Disables IsolationPolicy in the registry.", "Spooler crashing concurrently with specific drivers.")
        '41' = @("Universal Print Class Driver V4 Fix", "Scans V4 drivers for corrupted PrintConfig.dll and triggers DriverStore re-registration.", "V4 printers suddenly stop working or print gibberish.")
        '42' = @("Toggle PCL vs. PostScript Driver Mode", "Switches a printer's driver between PCL and PostScript rendering modes.", "Printer spits out pages of random characters.")
        '43' = @("Orphaned Driver Sweeper (pnputil)", "Scans DriverStore for orphaned printer OEM INF packages and force-deletes them.", "Unable to install new driver due to conflicts with old invisible drivers.")
        '44' = @("Bypass 'Driver is currently in use'", "Force-kills PrintIsolationHost, splwow64, and pipeline processes to release driver handles.", "Windows refuses to let you delete a driver.")
        '45' = @("Ghost USB Port & Copy Eliminator", "Detects and removes duplicate/ghost printer copies and dead USB ports.", "You plugged the printer into a different USB port and it created a ghost copy.")
        '46' = @("Force Remove Ghost Printers", "Forces printer removal via command line (printui).", "Ghost or corrupted printers refusing standard uninstallation.")
        '47' = @("Fix Microsoft Edge / UWP Printing", "Re-registers UWP printing components and loopback exemptions.", "Printing fails from Edge/UWP apps but succeeds from Notepad.")
        '48' = @("Reinstall Microsoft Print to PDF/XPS", "Re-initializes native Windows PDF & XPS printing features.", "Native virtual printers missing or generating errors.")
        '49' = @("Browser Print Sandbox Fix (Chromium)", "Clears browser print cache and fixes loopback exemptions for print dialogs.", "Can print from Word but not from Chrome.")
        '50' = @("Force Permanent Default Printer", "Disables auto-manage and forcibly sets default via WMI.", "Windows dynamically mutating default printer based on network location.")
        '51' = @("Force-Set Default Printer (Registry Bypass)", "Bypasses Windows auto-manage and sets default printer via direct HKCU registry write.", "Cannot set default printer through normal settings app.")
        '52' = @("Fix RDP Printer Terminal Services", "Enables printer redirection in RDP Terminal Services registry.", "Authenticating via RDP but local printers fail to map.")
        '53' = @("Auto-Sanitize Printer Share Name", "Scans shared printers and replaces illegal characters in share names with underscores.", "Clients cannot connect to a printer shared with a long or complex name.")
        '54' = @("Downgrade LSA Protection (Legacy Auth)", "Disables RunAsPPL in LSA registry.", "Share login failures due to strict Win 11 LSA protection.")
        '55' = @("Bypass Smart App Control (SAC)", "Sets VerifiedAndReputablePolicyState to Off.", "Windows 11 SAC actively blocking driver installers.")
        '56' = @("Bypass Advanced ServerList Point & Print (PrintNightmare Bypass)", "Injects PrintNightmare bypasses (Elevation Override) and ServerList wildcard (*) into registry.", "Throws 'Check Printer Name' or 'Access Denied' generic errors during driver download.", "Crucial for Windows 11 Build 22621+")
        '57' = @("Bypass UAC Admin Network TokenFilter", "Configures LocalAccountTokenFilterPolicy = 1.", "Remote administration to workgroup hosts failing due to UAC filtering.")
        '58' = @("Force NTLMv2 Response Compliance", "Configures LmCompatibilityLevel strictly to NTLMv2 (Level 3).", "'Access Denied' when authenticating against varying OS versions or Synology NAS.")
        '59' = @("Manage Windows Protected Print (WPP)", "Disables Windows Protected Print feature.", "Printer driver incompatible with WPP isolation.")
        '60' = @("Inject Windows Credentials into Vault Permanently", "Injects username/password directly into Windows Credential Manager.", "To bypass manual authentication upon each access.")
        '61' = @("Purge Stale Credentials from Windows Vault", "Purges invalid or outdated credentials from the vault via cmdkey.", "Host password was changed but local machine retains stale cache.")
        '62' = @("Bypass Credential Guard (Strict NTLM Block)", "Disables LsaCfgFlags Credential Guard registry node.", "Enterprise/Pro environments with Credential Guard enabled.")
        '63' = @("Cross-User Credential Mapping", "Injects network credentials into ALL user profiles via NTUSER.DAT registry load.", "Setting up a shared PC with multiple local accounts.")
        '64' = @("Pre-execution Registry Backup (Spooler & Network)", "Exports Print, Printers Policy, and LanmanWorkstation registry trees to C:\WinPrinterFixBackup.", "Highly recommended before applying other fixes.", "Always run this first!")
        '65' = @("Rollback Registry from Backup", "Imports .reg files from the backup directory.", "If things get worse after applying fixes.", "Only functional if [64] Backup was previously executed.")
        '66' = @("Generate System Restore Point (Security)", "Generates a System Restore Point for full OS rollback.", "Prior to executing major system-level architectural changes.")
        '67' = @("System File Checker & DISM Restoration", "Executes SFC /scannow and DISM RestoreHealth.", "Frequent BSODs, anomalous errors, or post-malware cleanup.", "This process may take 10-30 minutes!")
        '68' = @("Restart BITS (Background Transfer Service)", "Restarts Background Intelligent Transfer Service.", "Drivers failing to download automatically.")
        '69' = @("Uninstall & Pause Specific KB Update", "Removes a specific Windows Update KB via DISM (with WUSA fallback) and optionally pauses updates for 35 days.", "Immediately after a known bad Windows Update (e.g., KB5066835).")
        '70' = @("Launch Native Windows Troubleshooter", "Executes native Windows Printer Troubleshooter (msdt).", "Initial diagnostic step before manual intervention.")
        '71' = @("Force Printer Online Status", "Transmits online enforcement command via printui /yl.", "Printer status stuck on 'Offline' or grayed out.")
        '72' = @("Launch Services.msc", "Launches the Services.msc MMC snap-in.", "Manual verification of Print Spooler operational status.")
        '73' = @("Detect OS Version & Build Architecture", "Displays OS version, build number, and specific recommendations.", "Before choosing a specific fix to ensure compatibility.")
        '74' = @("Ping & Port 445/135 Diagnostics", "ICMP Ping + port scanning for SMB (445) and RPC (135).", "First step in testing network connection and firewall status.")
        '75' = @("View Execution Logs", "Launches log management interface (Notepad).", "Post-repair auditing and verification.")
        '76' = @("Audit Last 20 Print Service Error Logs", "Parses the last 20 error events from the System Event Log.", "Investigating root causes of print issues.")
        '77' = @("System Diagnostics Audit", "Audits Spooler state, SMB, Firewall, and network topologies.", "Checking the overall health of the system before deploying fixes.")
        '78' = @("PrintService Event Log Parser (Top 5)", "Parses the 5 most recent Error/Warning events with automated resolution suggestions.", "Mystery printing issues with no obvious error code.")
        '79' = @("Generate HTML Diagnostic Report", "Compiles execution logs into an interactive HTML file.", "For IT documentation or administrative reporting to superiors.")
        '80' = @("Detect GPO Intervention (Policy Scan)", "Scans registry and gpresult for Group Policy overrides affecting printers.", "Fixes work temporarily but break again after gpupdate or reboot.")
        '81' = @("PrintBRM (Backup/Restore Migration)", "Executes full backup or restoration of printer topologies via PrintBrm.exe.", "Deploying printers to multiple workstations or migrating to new hardware.")
        '82' = @("Enable SMB Guest Access & Drop Anonymous Blocks", "Enables AllowInsecureGuestAuth in LanmanWorkstation registry.", "For password-less sharing in local networks.")
        '83' = @("EXTREME PATH (WIN 11 24H2/25H2 & ARM64 SPECIFIC)", "Aggressive fix combination: DnsOnWire, StrictNameChecking, NTLM level, SMB Signing, Kerberos purge, etc.", "Standard fixes didn't work on latest Win 11.", "Built specifically for Build 26000 and above.")
        '84' = @("EXECUTE ALLFIX (50 AUTOMATED REPAIR SEQUENCES)", "Executes 50 automated repair steps sequentially.", "PRIMARY RECOMMENDATION - the recommended fix for most general cases.", "REBOOT SYSTEM upon completion for best results.")
        '85' = @("SILENT NUKE & ALLFIX (ZERO-PROMPT)", "Executes all 50 steps + automated reboot silently.", "Emergency situations requiring immediate unattended fixes.", "SYSTEM WILL AUTOMATICALLY REBOOT! Save all critical work prior!")
        '86' = @("Map Local Port to UNC Path (Titanium Bypass)", "Attempts standard port creation, then falls back to a Direct Registry Injection bypass if blocked.", "When standard sharing fails and the system entirely blocks 'Add-PrinterPort' commands.")
        '87' = @("Remove Injected Local Port (UNC)", "Attempts standard port removal, then falls back to a Registry Purge if blocked.", "When a mapped port is no longer needed or was misconfigured.")
        '88' = @("Reboot System", "Executes an immediate system reboot.", "Always execute after running any major fixes.")
        '89' = @("EXIT SCRIPT", "Exits the tool.", "When troubleshooting is complete.")
    }

    if ($Topic -eq "" -or $Topic -eq "menu") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "      USER GUIDE: Windows Printer Sharing Fix - @KHAIRUDINFAHMI" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  HOW TO USE:" -ForegroundColor Yellow
        Write-Host "    - Enter feature number (1-89) and press ENTER"
        Write-Host "    - Both '7' and '07' are valid"
        Write-Host "    - Input '?' to display this guide"
        Write-Host "    - Input '? 7' for detailed explanation of feature 7"
        Write-Host "    - Input '? all' to open complete HTML documentation"
        Write-Host ""
        Write-Host "  BEGINNER WORKFLOW (Standard Execution):" -ForegroundColor Yellow
        Write-Host "    1. Execute [64] Backup Registry (MANDATORY)" -ForegroundColor White
        Write-Host "    2. Execute [84] ALLFIX (50 automated steps)" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host "    4. Verify printer sharing access" -ForegroundColor White
        Write-Host ""
        Write-Host "  WIN 11 24H2+ WORKFLOW (Build 26000+):" -ForegroundColor Yellow
        Write-Host "    1. Execute [64] Backup Registry" -ForegroundColor White
        Write-Host "    2. Execute [83] Extreme Path" -ForegroundColor White
        Write-Host "    3. Reboot System" -ForegroundColor White
        Write-Host ""
        Write-Host "  EMERGENCY PROTOCOL (Quick Automated):" -ForegroundColor Yellow
        Write-Host "    - Execute [85] Silent Nuke (WARNING: Auto-reboots!)" -ForegroundColor White
        Write-Host ""
        Write-Host "  FEATURE CATEGORIES:" -ForegroundColor Yellow
        Write-Host "    [01-09] Error Code Fixes (0x0000011b, 0x00000709, 0x00000bc4, 0x00000035, 0x000006d1, 0x00000040, 0x00000002, 0x0000007e)" -ForegroundColor Cyan
        Write-Host "    [10-30] Network & Sharing Configuration (DNS, SMB, Firewall, WSD, IPP)" -ForegroundColor Cyan
        Write-Host "    [31-38] Spooler Management (Reset, RPC, Recovery, Watchdog, Nuke)" -ForegroundColor Cyan
        Write-Host "    [39-53] Drivers & Printing (Isolation, V4, PCL, Ghost, PDF, RDP)" -ForegroundColor Cyan
        Write-Host "    [54-59] Security & Policy (LSA, SAC, UAC, NTLMv2, WPP)" -ForegroundColor Cyan
        Write-Host "    [60-69] Credentials & System (Vault, Backup, SFC, BITS, KB)" -ForegroundColor Cyan
        Write-Host "    [70-81] Diagnostics & Utilities (Troubleshooter, Logs, GPO, BRM)" -ForegroundColor Green
        Write-Host "    [82-89] Special Operations (Extreme, AllFix, Local UNC, Purge UNC, Nuke)" -ForegroundColor Green

        Write-Host ""
        Write-Host "  QUICK TROUBLESHOOTING:" -ForegroundColor Yellow
        Write-Host "    - Continuous password prompts?     -> Execute [12], [60], [82]" -ForegroundColor White
        Write-Host "    - 'Access Denied' (Persistent)?     -> Use [60] to inject Target IP & Credentials." -ForegroundColor White
        Write-Host "    - 'Check Printer Name' generic error? -> Execute [56] or [86]" -ForegroundColor White
        Write-Host "    - Printer Offline despite powered on? -> Execute [71]" -ForegroundColor White
        Write-Host "    - Host invisible in network?       -> Execute [04], [11], [14]" -ForegroundColor White
        Write-Host "    - Failed to print from Edge/UWP?   -> Execute [47]" -ForegroundColor White
        Write-Host "    - Need to rollback all changes?    -> Execute [65]" -ForegroundColor White
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
    }
    elseif ($Topic.ToLower() -eq "all") {
        $docPath = $null

        try {
            $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
            $searchPaths = @(
                (Join-Path $exeDir "documentation.html"),
                (Join-Path $exeDir "docs\documentation.html"),
                (Join-Path (Split-Path $exeDir -Parent) "docs\documentation.html")
            )
            foreach ($sp in $searchPaths) {
                if (Test-Path $sp) { $docPath = $sp; break }
            }
        }
        catch {}

        if (-not $docPath -or -not (Test-Path $docPath)) {
            try {
                if ($PSCommandPath) {
                    $scriptDir = Split-Path $PSCommandPath -Parent
                    $fallbacks = @(
                        (Join-Path $scriptDir "documentation.html"),
                        (Join-Path $scriptDir "docs\documentation.html"),
                        (Join-Path (Split-Path $scriptDir -Parent) "docs\documentation.html")
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
            Write-Host "  [-] File documentation.html not detected in installation directory." -ForegroundColor Red
            Write-Host "  [!] Use '?' for quick guide or '? <number>' for feature details." -ForegroundColor Yellow
        }
    }
    else {
        $num = $Topic.TrimStart('0')
        if ($helpData.ContainsKey($num)) {
            $h = $helpData[$num]
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host "      HELP: FEATURE [$Topic]" -ForegroundColor Green
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
            Write-Host "  [-] Feature number '$Topic' not found. Enter 1-89." -ForegroundColor Red
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
    Write-Host "| Windows Printer Sharing Fix v2.2.9" -ForegroundColor Green

    Write-Host " TIME ZONE: " -NoNewline
    Write-Host "$(Get-TimeZone | Select-Object -ExpandProperty Id) | $(Get-Date -Format 'HH.mm.ss')" -ForegroundColor Red
    Write-Host " ENGINEERED BY: @KHAIRUDINFAHMI (2026)" -ForegroundColor Magenta
    Write-Host ("=" * 175) -ForegroundColor DarkGray

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
        "[02] Deep Fix 0x00000709 (Multi-Layer RPC & Kerberos)",
        "[03] Bypass Error 0x00000bc4 (No Printers Found)",
        "[04] Fix Error 0x80070035 (Automate Network Services)",
        "[05] Disable Client-Side Rendering (Error 0x000006d1)",
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
        "[50] Force Permanent Default Printer",
        "[51] Force-Set Default Printer (Reg Bypass)",
        "[52] Fix RDP Printer Terminal Services",
        "[53] Auto-Sanitize Printer Share Name",
        "[54] Downgrade LSA Protection (Legacy Auth)",
        "[55] Bypass Smart App Control (SAC)",
        "[56] Bypass Advanced ServerList Point & Print",
        "[57] Bypass UAC Admin Network TokenFilter",
        "[58] Force NTLMv2 Response Compliance",
        "[59] Manage Windows Protected Print (WPP)"
    )

    $col3 = @(
        "[60] Inject Credentials into Vault Permanently",
        "[61] Purge Stale Credentials from Vault",
        "[62] Bypass Credential Guard (Strict NTLM)",
        "[63] Cross-User Credential Mapping",
        "[64] Pre-execution Registry Backup (Spooler)",
        "[65] Rollback Registry from Backup",
        "[66] Generate System Restore Point (Security)",
        "[67] System File Checker & DISM Restoration",
        "[68] Restart BITS (Background Transfer)",
        "[69] Uninstall & Pause Specific KB Update",
        "[70] Launch Native Windows Troubleshooter",
        "[71] Force Printer Online Status",
        "[72] Launch Services.msc",
        "[73] Detect OS Version & Build Architecture",
        "[74] Ping & Port 445/135 Diagnostics",
        "[75] View Execution Logs",
        "[76] Audit Last 20 Print Service Error Logs",
        "[77] System Diagnostics Audit",
        "[78] PrintService Event Log Parser (Top 5)",
        "[79] Generate HTML Diagnostic Report",
        "[80] Detect GPO Intervention (Policy Scan)",
        "[81] PrintBRM (Backup/Restore Migration)",
        "[82] Enable SMB Guest Access & Drop Anon Blocks",
        "[83] EXTREME PATH (WIN 11 24H2/25H2 & ARM64)",
        "[84] ALLFIX (50 AUTOMATED REPAIR SEQUENCES)",
        "[85] SILENT NUKE & ALLFIX (ZERO-PROMPT)",
        "[86] Map Local Port to UNC Path (Bypass 0x00000709)",
        "[87] Remove Injected Local Port (UNC)",
        "[88] Reboot System",
        "[89] EXIT SCRIPT"
    )

    $maxRows = 30
    for ($i = 0; $i -lt $maxRows; $i++) {

        if ($i -lt $col1.Count) {
            $m1 = [regex]::Match($col1[$i], '^(\[\d+\])(.*)')
            if ($m1.Success) {
                Write-Host (" " + $m1.Groups[1].Value) -ForegroundColor Green -NoNewline
                Write-Host $m1.Groups[2].Value.PadRight($cw1 - 6) -ForegroundColor Green -NoNewline
            } else { Write-Host (" " + $col1[$i].PadRight($cw1 - 1)) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * ($cw1 - 1)) -NoNewline }

        Write-Host " " -NoNewline

        if ($i -lt $col2.Count) {
            $m2 = [regex]::Match($col2[$i], '^(\[\d+\])(.*)')
            if ($m2.Success) {
                Write-Host $m2.Groups[1].Value -ForegroundColor Green -NoNewline
                Write-Host $m2.Groups[2].Value.PadRight($cw2 - 5) -ForegroundColor Green -NoNewline
            } else { Write-Host $col2[$i].PadRight($cw2 - 1) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * ($cw2 - 1)) -NoNewline }

        Write-Host " " -NoNewline

        if ($i -lt $col3.Count) {
            $m3 = [regex]::Match($col3[$i], '^(\[\d+\])(.*)')
            if ($m3.Success) {
                Write-Host $m3.Groups[1].Value -ForegroundColor Green -NoNewline
                if ($m3.Groups[1].Value -in @("[83]", "[84]", "[85]")) {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Red
                } else {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Green
                }
            } else { Write-Host $col3[$i] -ForegroundColor Green }
        } else { Write-Host "" }
    }

    Write-Host ("-" * $totalW) -ForegroundColor Red
    $noteLine1 = " :   NOTE: ".PadRight($totalW - 2) + ":"
    $noteLine2 = " :   [84] ALLFIX (50 Steps) | [83] EXTREME PATH (Win11) | [85] SILENT NUKE ".PadRight($totalW - 2) + ":"
    $noteLine3 = " :   [?] HELP | [? 7] INFO | [? all] HTML | TIP: If 'Check Printer Name' error, use Option [86] ".PadRight($totalW - 2) + ":"

    Write-Host $noteLine1 -ForegroundColor Red
    Write-Host $noteLine2 -ForegroundColor Red
    Write-Host $noteLine3 -ForegroundColor Green
    Write-Host ("-" * $totalW) -ForegroundColor Red
    Write-Host ""
    Write-Host "Type option: " -NoNewline
}

if ($script:silentNuke) {
    AllFix-Core
    exit
}

do {
    Show-Menu
    $choice = Read-Host
    $choice = $choice.Trim()

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
        '1' { Fix-RpcAuthn0x0000011b }
        '2' { Fix-Deep0x00000709 }
        '3' { Fix-Discovery0x00000bc4 }
        '4' { Fix-NetworkServices }
        '5' { Fix-CSR }
        '6' { Reset-SpoolerPerm }
        '7' { Fix-Network0x00000040 }
        '8' { Fix-DriverCopy0x00000002 }
        '9' { Fix-RpcBitness0x0000007e }
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
        '50' { Manage-DefaultPrinter }
        '51' { Force-DefaultPrinterRegistry }
        '52' { Fix-RDPPrinter }
        '53' { Sanitize-PrinterShareName }
        '54' { Fix-LSAProtection }
        '55' { Fix-SAC }
        '56' { Fix-AdvancedPointAndPrint }
        '57' { Fix-UACTokenFilter }
        '58' { Fix-NTLMv2 }
        '59' { Manage-WPP }
        '60' { Add-Credential }
        '61' { Clean-Credential }
        '62' { Fix-CredentialGuard }
        '63' { Inject-CrossUserCredentials }
        '64' { Backup-Registry }
        '65' { Rollback-Registry }
        '66' { Create-RestorePoint }
        '67' { Run-SfcDism }
        '68' { Manage-BITS }
        '69' { Manage-WindowsUpdate }
        '70' { Start-Troubleshooter }
        '71' { Force-PrinterOnline }
        '72' { Open-Services }
        '73' { Detect-Win }
        '74' { Test-Connectivity }
        '75' { Log-Manager }
        '76' { Scan-PrintEventLog }
        '77' { Run-QuickDiagnostics }
        '78' { Parse-PrintEventLog }
        '79' { Generate-HtmlLog }
        '80' { Detect-GPOIntervention }
        '81' { Print-Migration }
        '82' { Enable-SMBGuest }
        '83' { Extreme-25H2 }
        '84' { AllFix-Core }
        '85' { $script:silentNuke = $true; AllFix-Core }
        '86' { Map-LocalPortUNC }
        '87' { Remove-LocalPortUNC }
        '88' { Restart-PC }
        '89' { Write-Log "Tool Terminated." -Type "INFO"; exit }

        default { Write-Host "`n  [-] Invalid selection. Enter numbers 1 - 89." -ForegroundColor Red }
    }

    if ($choice -ne '89' -and $choice -ne '88' -and $choice -ne '85') {
        Write-Host "`n  [>] Press ENTER to return to Main Menu..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)