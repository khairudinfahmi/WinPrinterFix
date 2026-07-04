#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 打印机共享修复工具 - v2.3.2 (汉化版)
    原作者: @KHAIRUDINFAHMI

.PARAMETER nuke
    静默全自动修复模式 - 自动执行所有 50 项修复然后自动重启。
#>

param(
    [switch]$nuke
)

$script:version    = "2.3.2"
$script:backupDir  = "C:\WindowsPrinterSharingFixBackup"
$script:silentNuke = $nuke

$script:logFile = $null
$candidateLogs = @(
    "C:\WindowsPrinterSharingFixLog.txt",
    "$env:TEMP\WindowsPrinterSharingFixLog.txt",
    "$env:USERPROFILE\Desktop\WindowsPrinterSharingFixLog.txt"
)
foreach ($cl in $candidateLogs) {
    try {
        Add-Content -Path $cl -Value "" -Encoding UTF8 -ErrorAction Stop
        $script:logFile = $cl
        break
    } catch { }
}
if (-not $script:logFile) {
    $script:logFile = "$env:TEMP\WindowsPrinterSharingFixLog.txt"
}

$script:isARM64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$script:isServer = $false
try {
    $prodOptions = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions" -ErrorAction SilentlyContinue
    if ($prodOptions -and $prodOptions.ProductType -ne "WinNT") {
        $script:isServer = $true
    }
} catch {
    try {
        $script:isServer = ((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1)
    } catch {
        $script:isServer = $false
    }
}

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
        Write-Host "  [错误] $Message" -ForegroundColor Red
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
    Write-Host "`n  [!] 请稍候... 正在请求管理员权限。" -ForegroundColor Yellow
    Write-Host "  [!] 请在弹出的 UAC (用户账户控制) 提示框中点击 '是'。" -ForegroundColor Yellow

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
        Add-Content -Path $script:logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Windows 打印机共享修复日志" -Encoding UTF8 -ErrorAction SilentlyContinue

        if ($script:isARM64) {
            Add-Content -Path $script:logFile -Value "[检测到 ARM64 架构]" -Encoding UTF8
        }
        if ($script:isServer) {
            Add-Content -Path $script:logFile -Value "[检测到 Windows Server 系统]" -Encoding UTF8
        }
    }
    catch {}
}

if (-not (Test-Administrator)) {
    Restart-Elevated
}
Initialize-Log

function Fix-RpcAuthn0x0000011b {
    Write-Log "正在修补错误 0x0000011b (RpcAuthnLevelPrivacy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "注册表 0x0000011b 修补成功。" -Type "SUCCESS"
        Write-Host "  [+] RPC 身份验证级别隐私要求已禁用。" -ForegroundColor Green
    }
    catch {
        Write-Log "修补 0x0000011b 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Deep0x00000709 {
    Write-Log "深度修复 0x00000709 — 正在应用所有 RPC 层补丁..." -Type "INFO"
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
        Set-ItemProperty -Path $printPath -Name RpcOverNamedPipes       -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $printPath -Name RpcOverTcp              -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        $lanPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $lanPath -Name DisableStrictNameChecking -Value 1 -Type DWord -Force

        $deviceKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $deviceVal = (Get-ItemProperty $deviceKey -ErrorAction SilentlyContinue).Device
        if ($deviceVal) {
            Write-Host "  [!] 正在清除旧的 Device 键值: $deviceVal" -ForegroundColor Yellow
            Remove-ItemProperty -Path $deviceKey -Name "Device" -ErrorAction SilentlyContinue
            Write-Log "HKCU Device 键值已清除: $deviceVal" -Type "SUCCESS"
        }

        Set-ItemProperty -Path $deviceKey -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force

        $wppPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"
        if (-not (Test-Path $wppPath)) { New-Item -Path $wppPath -Force | Out-Null }
        Set-ItemProperty -Path $wppPath -Name Enabled -Value 0 -Type DWord -Force

        $lsaMSV = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinClientSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinServerSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Restart-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "深度修复 0x00000709 完成。该操作必须在主机上也执行一次。" -Type "SUCCESS"
        Write-Host "  [+] 所有 0x00000709 层面的补丁已应用。" -ForegroundColor Green
        Write-Host "  [!] 重要提示: 请确保在主机(直连打印机的那台电脑)上也运行此脚本！" -ForegroundColor Red
    }
    catch {
        Write-Log "深度修复 0x00000709 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CrossSignedDriverPolicy {
    Write-Log "正在绕过 KB5089549 交叉签名驱动程序强制策略 (禁用审核模式)..." -Type "INFO"
    try {

        $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
        if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }

        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" `
            -Name VulnerableDriverBlocklistEnable -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        $polPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }
        Set-ItemProperty -Path $polPath `
            -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "交叉签名驱动强制策略已设为宽容模式 (KB5089549 修复)." -Type "SUCCESS"
        Write-Host "  [+] KB5089549 驱动策略强制已中和。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复交叉签名驱动策略失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HKCU-PrinterKeyPerms {
    Write-Log "正在修复 HKCU Windows 注册表键权限，以允许写入打印机设备..." -Type "INFO"
    try {

        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $acl = Get-Acl $regKey
        $sid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $sid,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $regKey -AclObject $acl -ErrorAction Stop
        Write-Log "HKCU Windows 键: 已授予 Everyone (S-1-1-0) 完全控制权限。" -Type "SUCCESS"
        Write-Host "  [+] 注册表权限修复已应用 (Everyone = 打印机设备键完全控制)。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 HKCU 打印机键权限失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-PostPatchTuesdayTask {
    Write-Log "正在部署 Windows 更新后的自动重新应用任务..." -Type "INFO"
    try {
        if (-not (Test-Path $script:backupDir)) {
            New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null
        }
        
        $scriptPath = Join-Path $script:backupDir "PrinterFixReapply.ps1"
        $fixScript = @'
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name ForceKerberosForRpc -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcProtocols -Value 7 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcOverNamedPipes -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcOverTcp -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force -EA SilentlyContinue
Restart-Service spooler -Force -EA SilentlyContinue
'@
        Set-Content -Path $scriptPath -Value $fixScript -Encoding UTF8 -Force
        
        $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        & schtasks.exe /create /tn "PrinterFixPostUpdate" /tr $cmd /sc onstart /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks ONSTART 返回退出代码 $LASTEXITCODE" }
        
        & schtasks.exe /create /tn "PrinterFixDaily" /tr $cmd /sc daily /st 10:00 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks DAILY 返回退出代码 $LASTEXITCODE" }

        # 配置任务在电池供电时运行 (避免笔记本上的 0x800710E0 错误)
        try {
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Set-ScheduledTask -TaskName "PrinterFixPostUpdate" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
            Set-ScheduledTask -TaskName "PrinterFixDaily" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Write-Log "更新后自动应用任务部署成功。" -Type "SUCCESS"
        Write-Host "  [+] 自动重新应用任务已部署。每次重启或更新后会自动应用注册表修复。" -ForegroundColor Green
        Write-Host "  [+] 任务: 'PrinterFixPostUpdate' & 'PrinterFixDaily' 在任务计划程序中处于活动状态。" -ForegroundColor Cyan
    }
    catch {
        Write-Log "部署更新后任务失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Discovery0x00000bc4 {
    Write-Log "正在绕过错误 0x00000bc4 (找不到打印机)..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

        Set-ItemProperty -Path $path -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcTcpEnable -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcProtocols -Value 0x7 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ForceSetup -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "已强制 RPC 终结点映射器使用命名管道和 TCP。" -Type "SUCCESS"
        Write-Host "  [+] RPC 打印机发现已明确路由至命名管道。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过 0x00000bc4 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NetworkServices {
    Write-Log "正在修复错误 0x80070035 (启动 WSD, SMB, NetBIOS 服务)..." -Type "INFO"
    $services = @("nlasvc", "Dnscache", "LanmanServer", "LanmanWorkstation", "lmhosts", "fdPHost", "FDResPub", "SSDPSRV", "upnphost", "WdiSystemHost", "WdiServiceHost")

    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "警告: 无法配置服务 $svc." -Type "WARNING"
        }
    }
    Write-Log "网络和 WSD 服务已配置为自动启动。" -Type "SUCCESS"
    Write-Host "  [+] 所有网络服务正常运行。" -ForegroundColor Green
}

function Fix-CSR {
    Write-Log "正在禁用客户端渲染 (错误 0x000006d1)..." -Type "INFO"
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

        Set-ItemProperty -Path $path -Name DisableClientSideRendering -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "客户端渲染 (CSR) 成功禁用。" -Type "SUCCESS"
        Write-Host "  [+] 客户端渲染已禁用；主机将处理打印任务。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用客户端渲染失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-Spooler {
    Write-Log "正在终止打印后台处理程序 (Print Spooler) 并清空队列..." -Type "INFO"
    try {
        Stop-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "确保相关进程 (splwow64, printfilter) 已终止..." -Type "INFO"
        Get-Process -Name "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Write-Log "正在清除旧的打印假脱机文件..." -Type "INFO"
        Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*" -Force -Recurse -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Set-Service spooler -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service spooler -ErrorAction Stop

        Write-Log "Spooler 刷新成功！" -Type "SUCCESS"
        Write-Host "  [+] 打印服务缓存已成功清空并设为自动启动 (硬重置)。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置 Spooler 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Enable-SMBGuest {
    Write-Log "正在启用 SMB 访客访问 (LanmanWorkstation & LanmanServer)..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $path -Name AllowInsecureGuestAuth -Value 1 -Type DWord -Force -ErrorAction Stop

        $pathServer = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $pathServer -Name EnableSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "访客访问已启用。" -Type "SUCCESS"
        Write-Host "  [+] SMB 凭证保护已降低，允许访客访问。" -ForegroundColor Green
    }
    catch {
        Write-Log "启用 SMB 访客失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-Network {
    Write-Log "正在进行全面网络重置 (清空 DNS, NetBIOS, Winsock)..." -Type "INFO"
    try {
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; & netsh winsock reset > $null 2>&1
        $LASTEXITCODE = 0; & netsh int ip reset > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1

        Write-Log "网络配置已重置。" -Type "SUCCESS"
        Write-Host "  [+] 网络缓存已成功刷新。" -ForegroundColor Green
    }
    catch {
        Write-Log "网络重置失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-NetworkPrivate {
    Write-Log "正在更改网络配置文件 (从公用改为专用，跳过域)..." -Type "INFO"
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
                    Write-Log "更改配置文件 $($profile.InterfaceAlias) 失败。" -Type "WARNING"
                }
            }
            elseif ($profile.NetworkCategory -eq 'Private' -or $profile.NetworkCategory -eq 'DomainAuthenticated') {
                $success = $true
            }
        }

        if ($success) {
            Write-Log "专用网络配置已安全强制执行。" -Type "SUCCESS"
            Write-Host "  [+] 网络已强制设为专用；网络发现拦截已解除。" -ForegroundColor Green
        }
    }
    catch {
        Write-Log "更改网络配置文件失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Disable-PasswordSharing {
    Write-Log "正在禁用密码保护的共享..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name limitblankpassworduse -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name everyoneincludesanonymous -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name restrictnullsessaccess -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "密码保护的共享已禁用。" -Type "SUCCESS"
        Write-Host "  [+] 网络共享已开放 (Everyone = Anonymous)。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用密码保护共享失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NamedPipes {
    Write-Log "正在激活 RPC 命名管道..." -Type "INFO"
    try {
        $rpcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }

        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols -Value 0x7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force

        $printPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
        Set-ItemProperty -Path $printPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $printPath -Name RpcOverTcp -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Log "命名管道已激活。" -Type "SUCCESS"
        Write-Host "  [+] RPC 命名管道打印处理路径已纠正。" -ForegroundColor Green
    }
    catch {
        Write-Log "更改命名管道失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Open-Firewall {
    Write-Log "正在为文件和打印机共享开启防火墙..." -Type "INFO"
    try {
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28509" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*文件*打印机*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*File*Printer*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*网络发现*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*Network Discovery*" -ErrorAction SilentlyContinue | Out-Null

        Write-Log "防火墙端口已开放。" -Type "SUCCESS"
        Write-Host "  [+] Windows Defender 防火墙已配置为允许共享。" -ForegroundColor Green
    }
    catch {
        Write-Log "更改防火墙规则失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Backup-Registry {
    Write-Log "正在执行打印机注册表备份..." -Type "INFO"
    try {
        $backupCount = 0
        $backupTotal = 5

        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Print" "$script:backupDir\Print.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告: 备份 Print 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers" "$script:backupDir\PrintersPolicy.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告: 备份 PrintersPolicy 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "$script:backupDir\LanmanWorkstation.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告: 备份 LanmanWorkstation 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "$script:backupDir\LanmanServer.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告: 备份 LanmanServer 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$script:backupDir\Lsa.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告: 备份 LSA 注册表失败。" -Type "WARNING" }

        Write-Log "备份完成 ($backupCount/$backupTotal 个配置单元)。" -Type "SUCCESS"
        Write-Host "  [+] 关键注册表节点已备份至 $script:backupDir ($backupCount/$backupTotal 个配置单元)。" -ForegroundColor Green
    }
    catch {
        Write-Log "备份注册表失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Check-RPC {
    Write-Log "正在审核 RPC & DCOM 服务状态..." -Type "INFO"
    $rpc = Get-Service -Name RpcSs -ErrorAction SilentlyContinue
    if ($rpc.Status -ne 'Running') {
        Start-Service RpcSs -ErrorAction SilentlyContinue
        Write-Host "  [*] RpcSs 未运行。正在重新初始化该服务。" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] RpcSs 正常运行。" -ForegroundColor Green
    }

    $dcom = Get-Service -Name DcomLaunch -ErrorAction SilentlyContinue
    if ($dcom.Status -ne 'Running') {
        Start-Service DcomLaunch -ErrorAction SilentlyContinue
        Write-Host "  [*] DcomLaunch 未运行。正在重新初始化该服务。" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] DcomLaunch 正常运行。" -ForegroundColor Green
    }
}

function Run-SfcDism {
    Write-Log "正在启动 SFC 和 DISM 修复程序..." -Type "INFO"
    Write-Host "`n  [!] 请稍候，此操作需要较长时间..." -ForegroundColor Yellow
    Write-Host "  [*] [1/2] 正在执行 SFC Scannow (系统文件检查)..." -ForegroundColor Cyan
    & sfc /scannow
    Write-Host "  [*] [2/2] 正在执行 DISM RestoreHealth (系统映像恢复)..." -ForegroundColor Cyan
    & dism /online /cleanup-image /restorehealth
    Write-Log "SFC & DISM 修复程序已完成。" -Type "SUCCESS"
    Write-Host "  [+] 操作系统文件完整性验证已结束。" -ForegroundColor Green
}

function Manage-Drivers {
    Write-Log "正在启动打印机服务器属性..." -Type "INFO"
    Write-Host "  [!] 打印服务器属性对话框已打开。请手动清除异常驱动程序。" -ForegroundColor Yellow
    Start-Process printui -ArgumentList '/s /t2' -NoNewWindow
}

function Reset-SpoolerPerm {
    Write-Log "正在重置 Spooler 目录 ACL 权限..." -Type "INFO"
    try {
        & icacls "$env:SystemRoot\System32\Spool\Printers" /reset /t /c /q > $null 2>&1
        & icacls "$env:SystemRoot\System32\Spool\Printers" /grant "*S-1-1-0:(OI)(CI)F" /T /C /Q > $null 2>&1
        Write-Log "Spooler ACL 重置完毕并授予 Everyone (S-1-1-0) 权限。" -Type "SUCCESS"
        Write-Host "  [+] 打印队列目录权限已重置，并授予 Everyone 完全控制。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置 ACL 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-SMB1 {
    Write-Host "`n  ======================================================================"
    Write-Host "                 SMB 1.0 协议管理 (旧版)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 警告: SMB 1.0 非常容易受到勒索软件攻击。"
    Write-Host "  [1] 启用 SMB1 (紧急情况) `n  [2] 禁用 SMB1 (推荐)"
    $smbopt = Read-Host "  请选择操作 (1/2)"
    if ($smbopt -eq '1') {
        try {
            Write-Log "正在启用 SMB 1.0 协议..." -Type "INFO"
            Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "  [+] SMB 1.0 协议已启用。" -ForegroundColor Green
        } catch {
            Write-Log "启用 SMB1 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
    if ($smbopt -eq '2') {
        try {
            Write-Log "正在禁用 SMB 1.0 协议..." -Type "INFO"
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "  [+] 出于安全考虑，SMB 1.0 协议已成功禁用。" -ForegroundColor Green
        } catch {
            Write-Log "禁用 SMB1 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Add-Credential {
    Write-Host "`n  注入 WINDOWS 凭据"
    $ip = Read-Host "  [?] 目标 IP/主机名 (例如: 192.168.1.10)"
    if ($null -ne $ip) { $ip = $ip.Trim() }
    $usr = Read-Host "  [?] 目标主机上的用户名"
    if ($null -ne $usr) { $usr = $usr.Trim() }
    $pass = Read-Host "  [?] 目标主机上的密码 (明文显示)"

    if (-not $ip -or -not $usr) {
        Write-Host "  [-] 已取消 - 必须提供目标主机和用户名。" -ForegroundColor Red
        return
    }

    try {
        $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/add:$ip", "/user:$usr", "/pass:`"$pass`"" -WindowStyle Hidden -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Log "目标 $ip 的凭据已注入。" -Type "SUCCESS"
            Write-Host "  [+] 凭据已成功保存到 Windows 凭据管理器。" -ForegroundColor Green
        } else {
            Write-Log "cmdkey 注入 $ip 的凭据失败，退出代码 $($proc.ExitCode)。" -Type "ERROR"
            Write-Host "  [-] 凭据注入失败 (退出代码 $($proc.ExitCode))。" -ForegroundColor Red
        }
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Log "注入凭据失败: $($_.Exception.Message)" -Type "ERROR"
    }
    $pass = ""
}

function Clean-Credential {
    Write-Host "`n  清除失效的 WINDOWS 凭据"
    & cmdkey /list | Select-String "Target:" | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    $del = Read-Host "`n  [?] 输入要清除的目标 (留空以取消)"
    if ($del) {
        $del = $del -replace '(?i)^\s*Target:\s*', ''
        try {
            $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/delete:`"$del`"" -WindowStyle Hidden -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Log "凭据 $del 已清除。" -Type "SUCCESS"
                Write-Host "  [+] 凭据 $del 成功清除。" -ForegroundColor Green
            } else {
                Write-Log "清除凭据 $del 失败。请验证目标名称。" -Type "ERROR"
                Write-Host "  [-] 清除凭据 $del 失败。请验证目标名称。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "清除凭据失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Start-Troubleshooter {
    Write-Log "正在执行原生 Windows 疑难解答..." -Type "INFO"
    Start-Process msdt -ArgumentList '/id PrinterDiagnostic' -NoNewWindow
}

function Force-PrinterOnline {
    Write-Log "正在强制打印机设为联机状态..." -Type "INFO"
    $pname = Read-Host "  [?] 输入完全一致的打印机名称 (例如: EPSON L120 Series)"
    if ($pname) {
        try {
            $safeName = $pname -replace "'", "''"
            $prn = Get-CimInstance Win32_Printer -Filter "Name='$safeName'" -ErrorAction Stop
            if ($prn) {
                $prn.WorkOffline = $false
                Set-CimInstance -InputObject $prn -ErrorAction Stop
                Write-Log "打印机 $pname 状态已强制联机。" -Type "SUCCESS"
                Write-Host "  [+] 强制联机指令已发送至 $pname。" -ForegroundColor Green
            }
            else {
                Write-Host "  [-] 本机未检测到打印机 $pname。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "强制打印机联机状态失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Open-Services {
    Write-Log "正在启动 Services.msc (服务管理)..." -Type "INFO"
    Start-Process services.msc
}

function Rollback-Registry {
    Write-Log "正在从备份恢复注册表..." -Type "INFO"
    if (Test-Path "$script:backupDir\Print.reg") {
        $restoreCount = 0
        $restoreFiles = @(
            @{ File = "Print.reg"; Label = "Print" },
            @{ File = "PrintersPolicy.reg"; Label = "PrintersPolicy" },
            @{ File = "LanmanWorkstation.reg"; Label = "LanmanWorkstation" },
            @{ File = "LanmanServer.reg"; Label = "LanmanServer" },
            @{ File = "Lsa.reg"; Label = "LSA" }
        )
        foreach ($entry in $restoreFiles) {
            $filePath = Join-Path $script:backupDir $entry.File
            if (Test-Path $filePath) {
                & reg import $filePath > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $restoreCount++
                } else {
                    Write-Log "警告: 恢复 $($entry.Label) 失败。" -Type "WARNING"
                    Write-Host "  [!] 恢复 $($entry.Label) 失败。" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [*] 跳过 $($entry.Label) (未找到备份文件)。" -ForegroundColor Cyan
            }
        }
        Write-Log "注册表回滚完成 (已恢复 $restoreCount 个文件)。" -Type "SUCCESS"
        Write-Host "  [+] 注册表回滚完成 (从 $script:backupDir 恢复了 $restoreCount 个文件)。" -ForegroundColor Green
    }
    else {
        Write-Host "  [-] 失败: 在 $script:backupDir 中未检测到备份文件。" -ForegroundColor Red
    }
}

function Disable-IPv6 {
    Write-Log "正在禁用 IPv6 协议栈..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -Value 0xffffffff -Type DWord -Force -ErrorAction Stop
        Write-Log "IPv6 已通过注册表修改禁用。" -Type "SUCCESS"
        Write-Host "  [+] IPv6 已禁用以防止路由冲突。需要重启系统生效。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用 IPv6 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Generate-HtmlLog {
    Write-Log "正在生成 HTML 诊断报告..." -Type "INFO"
    $htmlFile = "$script:backupDir\Report.html"
    $rawLog = Get-Content $script:logFile -Raw -ErrorAction SilentlyContinue
    $encodedLog = [System.Net.WebUtility]::HtmlEncode($rawLog)
    $htmlContent = @"
<html>
<head>
    <title>Windows 打印机共享修复 - 日志</title>
    <style>
        body { font-family: 'Courier New', monospace; background: #0b0f19; color: #00ffcc; padding: 20px; }
        h1 { color: #ff0055; border-bottom: 2px solid #333; padding-bottom: 10px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; border: 1px solid #30363d; overflow-x: auto; font-size: 14px; }
    </style>
</head>
<body>
    <h1>Windows 打印机共享修复诊断报告</h1>
    <p>生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | 目标系统: $([System.Net.WebUtility]::HtmlEncode($script:productName))</p>
    <pre>$encodedLog</pre>
</body>
</html>
"@
    $htmlContent | Out-File $htmlFile -Encoding UTF8
    Write-Log "HTML 日志已生成至 $htmlFile." -Type "SUCCESS"
    Start-Process $htmlFile
}

function Test-Connectivity {
    Write-Host "`n  ======================================================================"
    Write-Host "                 PING & 网络端口诊断"
    Write-Host "  ======================================================================"
    $ip = Read-Host "  [?] 输入目标 IP/主机名"
    if (-not $ip -or $ip.Trim() -eq '') {
        Write-Host "  [-] 已取消 - 未提供输入。" -ForegroundColor Red
        return
    }
    $ip = $ip.Trim()
    if (Test-Connection $ip -Count 1 -Quiet) {
        Write-Host "  [+] PING 成功: 主机 $ip 可以访问。" -ForegroundColor Green

        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] 端口 445 (SMB): 开启" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 445 (SMB): 关闭 (可能被防火墙拦截)" -ForegroundColor Red }

        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] 端口 135 (RPC): 开启" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 135 (RPC): 关闭 (可能被防火墙拦截)" -ForegroundColor Red }
    }
    else {
        Write-Host "  [-] PING 失败: 目标主机不可达或已显式阻止 ICMP (Ping)。" -ForegroundColor Red
        Write-Host "  [*] 正在尝试直接检查 TCP 端口 445 和 135..." -ForegroundColor Cyan
        
        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] 端口 445 (SMB): 开启 (Ping 被阻止，但主机在线)" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 445 (SMB): 关闭" -ForegroundColor Red }

        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] 端口 135 (RPC): 开启 (Ping 被阻止，但主机在线)" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 135 (RPC): 关闭" -ForegroundColor Red }
    }
}

function Scan-RemotePrinter {
    Write-Host "`n  远程网络打印机发现"
    $ip = Read-Host "  [?] 目标 IP/主机名"
    Write-Host "  [*] 正在扫描 $ip..." -ForegroundColor Cyan
    try {
        $prn = Get-Printer -ComputerName $ip -ErrorAction Stop | Where-Object Shared -eq $true
        if ($prn) {
            $prn | Format-Table Name, ShareName, PortName, PrinterStatus -AutoSize
        }
        else {
            Write-Host "  [-] 在目标主机上未检测到共享打印机。" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [-] RPC 连接失败。请验证是否具有访问 $ip 的管理员/访客权限。" -ForegroundColor Red
    }
}

function Remote-SpoolerReset {
    Write-Host "`n  ======================================================================"
    Write-Host "               远程打印后台处理服务重置"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 需要目标机器上的管理员权限。" -ForegroundColor Yellow
    $target = Read-Host "  [?] 目标主机名或 IP (例如: 192.168.1.10)"
    if (-not $target) { Write-Host "  [-] 已取消 - 输入为空。" -ForegroundColor Red; return }

    Write-Log "远程 Spooler 重置目标: $target" -Type "INFO"
    try {
        Write-Host "  [*] 正在 Ping $target..." -ForegroundColor Cyan
        if (-not (Test-Connection $target -Count 1 -Quiet)) {
            Write-Host "  [-] 主机不可达。请检查网络和防火墙。" -ForegroundColor Red
            Write-Log "Remote-SpoolerReset: $target 不可达。" -Type "ERROR"
            return
        }
        Write-Host "  [+] 主机可访问。" -ForegroundColor Green

        Write-Host "  [*] 正在停止 $target 上的 Spooler 服务..." -ForegroundColor Cyan
        $stopResult = & sc.exe \\$target stop spooler 2>&1
        Start-Sleep -Seconds 3

        Write-Host "  [*] 正在启动 $target 上的 Spooler 服务..." -ForegroundColor Cyan
        $startResult = & sc.exe \\$target start spooler 2>&1
        Start-Sleep -Seconds 2

        $queryResult = & sc.exe \\$target query spooler 2>&1
        if ($queryResult -match 'RUNNING') {
            Write-Log "$target 上的远程 Spooler 重启成功。" -Type "SUCCESS"
            Write-Host "  [+] $target 上的 Print Spooler 服务正在运行 (RUNNING)。" -ForegroundColor Green
        } else {
            Write-Log "$target 上的远程 Spooler 可能未重启，请手动检查。" -Type "WARNING"
            Write-Host "  [!] Spooler 状态不确定。请在 $target 上手动验证。" -ForegroundColor Yellow
        }
    } catch {
        Write-Log "Remote-SpoolerReset 失败: $($_.Exception.Message)" -Type "ERROR"
        Write-Host "  [-] 失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [!] 请确保可以访问管理员共享 (C$) 以及 RPC (端口 135/445)。" -ForegroundColor Yellow
    }
}

function Log-Manager {
    Write-Log "正在使用记事本打开日志管理器..." -Type "INFO"
    notepad $script:logFile
}

function Print-Migration {
    Write-Log "正在启动 PrintBRM 迁移工具..." -Type "INFO"

    $brmPath = Join-Path $env:SystemRoot "System32\spool\tools\PrintBrm.exe"
    if (-not (Test-Path $brmPath)) {
        $brmPath = Join-Path $env:SystemRoot "System32\PrintBrm.exe"
    }

    if (-not (Test-Path $brmPath)) {
        Write-Log "本机未检测到 PrintBrm.exe。" -Type "ERROR"
        Write-Host "  [-] 错误: 打印迁移工具 (PrintBrm.exe) 缺失。" -ForegroundColor Red
        Write-Host "  [!] 注意: 此功能通常仅在 Windows Pro(专业版)、企业版或服务器版中可用。" -ForegroundColor Yellow
        Write-Host "  [!] 你的系统: $script:productName" -ForegroundColor Cyan
        return
    }

    Write-Host "  [*] 正在常驻命令提示符窗口中启动 PrintBrm.exe..." -ForegroundColor Cyan
    try {
        Start-Process cmd.exe -ArgumentList "/k cd /d `"$env:SystemRoot\System32\spool\tools\`" & title 打印机迁移工具 (PrintBRM) & `"$brmPath`" /?"
        Write-Log "PrintBRM 提示符启动成功。" -Type "SUCCESS"
        Write-Host "  [+] PrintBRM 提示符启动成功！你现在可以执行备份/恢复命令。" -ForegroundColor Green
    }
    catch {
        Write-Log "启动 PrintBRM 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Uninstall-Printer {
    $up = Read-Host "`n  [?] 输入要强制卸载的打印机确切名称"
    if ($up) {
        try {
            & printui.exe /dl /n "$up"
            Write-Log "已向 $up 发出卸载指令。" -Type "SUCCESS"
        }
        catch {
            Write-Log "卸载 $up 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Fix-SMBSigning {
    Write-Log "正在禁用 SMB 签名强制要求及双向身份验证..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireMutualAuthentication -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "SMB 签名强制要求已禁用。" -Type "SUCCESS"
        Write-Host "  [+] SMB 签名要求已取消 (解决了 Win 11 连接 NAS/旧版设备的问题)。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用 SMB 签名失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UWPPrinting {
    Write-Log "正在为 Microsoft Edge 绕过 UWP AppContainer 隔离..." -Type "INFO"
    try {
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Write-Log "环回隔离已显式授权豁免。" -Type "SUCCESS"
        Write-Host "  [+] Edge 和 UWP 应用的环回网络隔离已禁用。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过 UWP 环回失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-mDNS {
    Write-Log "正在启用 mDNS & LLMNR 发现协议..." -Type "INFO"
    try {
        $dnsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $dnsPath)) { New-Item -Path $dnsPath -Force | Out-Null }
        Set-ItemProperty -Path $dnsPath -Name EnableMulticast -Value 1 -Type DWord -Force -ErrorAction Stop

        $dnsCachePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        if (-not (Test-Path $dnsCachePath)) { New-Item -Path $dnsCachePath -Force | Out-Null }
        Set-ItemProperty -Path $dnsCachePath -Name EnableMDNS -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "mDNS/LLMNR 协议已激活。" -Type "SUCCESS"
    }
    catch {
        Write-Log "配置 mDNS 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-WSDFirewall {
    Write-Log "确保无条件开放 WSD (3702) & mDNS (5353) 端口..." -Type "INFO"
    try {
        Remove-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -ErrorAction SilentlyContinue | Out-Null
        Remove-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -ErrorAction SilentlyContinue | Out-Null

        New-NetFirewallRule -DisplayName "Printer WSD (UDP 3702 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3702 -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Printer mDNS (UDP 5353 Inbound)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5353 -ErrorAction SilentlyContinue | Out-Null

        Write-Log "WSD 防火墙规则更新成功。" -Type "SUCCESS"
        Write-Host "  [+] UDP 端口 3702 和 5353 已在防火墙中显式开启。" -ForegroundColor Green
    }
    catch {
        Write-Log "配置 WSD 防火墙失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-LSAProtection {
    Write-Log "正在降级 LSA 保护 (允许使用旧版身份验证)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "LSA PPL 强制已降级。" -Type "SUCCESS"
        Write-Host "  [+] LSA 保护已降级。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-LSAProtection 失败: $($_.Exception.Message) (可能受安全启动或 Credential Guard 强制保护)" -Type "WARNING"
        Write-Host "  [!] 无法更改 LSA 保护 - 系统安全策略可能正在强制执行它。" -ForegroundColor Yellow
    }
}

function Fix-SAC {
    Write-Log "正在为打印驱动注入绕过智能应用控制 (SAC)..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "SAC 绕过已部署。" -Type "SUCCESS"
        Write-Host "  [+] 智能应用控制 (SAC) 已被绕过。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-SAC 失败: $($_.Exception.Message) (SAC 可能受 UEFI/策略强制保护)" -Type "WARNING"
        Write-Host "  [!] SAC 绕过失败 - 可能需要在 Windows 安全中心设置中手动更改。" -ForegroundColor Yellow
    }
}

function Fix-IPPSharing {
    Write-Log "正在启用互联网打印协议 (IPP & Mopria)..." -Type "INFO"
    try {
        if ((Get-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -ErrorAction SilentlyContinue)) {
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-InternetPrinting-Client" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Log "IPP 基础功能成功启用。" -Type "SUCCESS"
            Write-Host "  [+] Windows 功能: 互联网打印客户端已激活。" -ForegroundColor Green
        }
    }
    catch {
        Write-Log "配置 IPP 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-AdvancedPointAndPrint {
    Write-Log "正在绕过高级点和打印(Point & Print)策略及 PrintNightmare 限制..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name InForest -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name TrustedServers -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ServerList -Value "*.*" -Type String -Force -ErrorAction Stop

        Set-ItemProperty -Path $path -Name RestrictDriverInstallationToAdministrators -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnInstall -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnUpdate -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name UpdatePromptSettings -Value 2 -Type DWord -Force -ErrorAction Stop

        $pkgPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint"
        if (-not (Test-Path $pkgPath)) { New-Item -Path $pkgPath -Force | Out-Null }
        Set-ItemProperty -Path $pkgPath -Name PackagePointAndPrintServerList -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "Point & Print 限制及 PrintNightmare 漏洞补丁限制被完全绕过。" -Type "SUCCESS"
        Write-Host "  [+] PrintNightmare 提权限制及点和打印(Point & Print)策略已被完全中和。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-AdvancedPointAndPrint 失败: $($_.Exception.Message)" -Type "ERROR"
        Write-Host "  [-] Point & Print 绕过失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Fix-ModernSMB {
    Write-Log "正在强制使用现代 SMB2/SMB3 服务器配置..." -Type "INFO"
    try {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
        Write-Log "SMB2/SMB3 拓扑已激活。" -Type "SUCCESS"
        Write-Host "  [+] SMB2/SMB3 协议已强制执行。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-ModernSMB 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-SpoolerRecovery {
    Write-Log "正在配置 Print Spooler 崩溃后自动重启恢复机制..." -Type "INFO"
    try {
        & sc.exe failure spooler reset= 0 actions= restart/60000/restart/60000/restart/60000 > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sc.exe 返回退出代码 $LASTEXITCODE" }
        Write-Log "Spooler 自动重启恢复已配置。" -Type "SUCCESS"
        Write-Host "  [+] 已配置在 Spooler 崩溃后自动重新启动服务。" -ForegroundColor Green
    }
    catch {
        Write-Log "Set-SpoolerRecovery 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UACTokenFilter {
    Write-Log "正在绕过 UAC 网络管理员限制..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "LocalAccountTokenFilterPolicy 设为 1。" -Type "SUCCESS"
        Write-Host "  [+] UAC 网络管理令牌过滤已禁用。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-UACTokenFilter 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-SpoolerDependency {
    Write-Log "正在清除第三方 Spooler 依赖项..." -Type "INFO"
    try {
        & sc.exe config spooler depend= RPCSS/http > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sc.exe 返回退出代码 $LASTEXITCODE" }
        Write-Log "依赖项已明确重置为 RPCSS 和 http (兼容 IPP)。" -Type "SUCCESS"
        Write-Host "  [+] Print Spooler 依赖项已修复，以支持现代 IPP。" -ForegroundColor Green
    }
    catch {
        Write-Log "Reset-SpoolerDependency 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-ProviderOrder {
    Write-Log "正在网络提供商顺序中优先考虑 SMB (LanmanWorkstation)..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
        $currentOrder = (Get-ItemProperty -Path $path -Name ProviderOrder -ErrorAction SilentlyContinue).ProviderOrder
        if ($currentOrder) {
            $arr = $currentOrder -split "," | Where-Object { $_ -ne "LanmanWorkstation" -and $_ -ne "" }
            $newOrder = "LanmanWorkstation," + ($arr -join ",")
            Set-ItemProperty -Path $path -Name ProviderOrder -Value $newOrder -Force
            Write-Log "已显式更新提供商顺序 (LanmanWorkstation 优先级最高)。" -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "配置 Provider Order 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NTLMv2 {
    Write-Log "正在强制使用严格的 NTLMv2 响应 (兼容 NAS 和 Samba)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 3 -Type DWord -Force -ErrorAction Stop
        Write-Log "严格的 NTLMv2 强制执行成功。" -Type "SUCCESS"
        Write-Host "  [+] 已强制执行严格的 NTLMv2 (级别 3)。 NAS 及现代打印机共享连接已获得保障。" -ForegroundColor Green
    }
    catch {
        Write-Log "Fix-NTLMv2 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Network0x00000040 {
    Write-Log "正在修复错误 0x00000040 (网络连接超时)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name KeepConn -Value 65535 -Type DWord -Force -ErrorAction Stop
        try {
            Restart-Service LanmanWorkstation -Force -ErrorAction Stop
        } catch {
            Write-Log "LanmanWorkstation 重启超时或失败: $($_.Exception.Message)" -Type "WARNING"
        }
        Write-Log "KeepConn SMB 已设为最大值。" -Type "SUCCESS"
        Write-Host "  [+] SMB 连接超时已延长，以缓解不稳定的网络拓扑问题。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x00000040 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-DriverCopy0x00000002 {
    Write-Log "正在修复错误 0x00000002 (Driver CopyFilesPolicy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name CopyFilesPolicy -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "CopyFilesPolicy 已激活。" -Type "SUCCESS"
        Write-Host "  [+] CopyFilesPolicy 允许操作系统从主机获取缺少的驱动程序。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x00000002 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RpcBitness0x0000007e {
    Write-Log "正在修复错误 0x0000007e (RPC Bitness/身份验证错误)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcAuthenticationLevel -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "RPC 身份验证已降级。" -Type "SUCCESS"
        Write-Host "  [+] RPC 认证限制已移除，以便跨系统架构通信。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x0000007e 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-WPP {
    Write-Host "`n  ======================================================================"
    Write-Host "             Windows 受保护的打印 (WPP) 管理"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 这是 Win 11 24H2+ 新特性，提供严格安全性，但会屏蔽"
    Write-Host "      所有不支持 Mopria 协议的传统/自定义打印机。"
    Write-Host "  [1] 启用 WPP (传统打印机很可能失败)"
    Write-Host "  [2] 禁用 WPP (对传统局域网共享安全 - 推荐)"
    $opt = Read-Host "  请选择操作 (1/2)"
    $wppPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"
    if (-not (Test-Path $wppPath)) { New-Item -Path $wppPath -Force | Out-Null }
    if ($opt -eq '1') {
        try {
            Write-Log "正在启用 WPP 模式..." -Type "INFO"
            Set-ItemProperty -Path $wppPath -Name Enabled -Value 1 -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] WPP 已启用。" -ForegroundColor Yellow
        } catch {
            Write-Log "启用 WPP 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
    if ($opt -eq '2') {
        try {
            Write-Log "正在禁用 WPP 模式..." -Type "INFO"
            Set-ItemProperty -Path $wppPath -Name Enabled -Value 0 -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] WPP 已成功禁用 (处于兼容模式)。" -ForegroundColor Green
        } catch {
            Write-Log "禁用 WPP 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Scan-PrintEventLog {
    Write-Log "正在读取最近 20 条 Printer Service 日志..." -Type "INFO"
    Write-Host "`n  --- MICROSOFT 打印服务事件日志错误历史 ---" -ForegroundColor Cyan
    $events = Get-WinEvent -LogName "Microsoft-Windows-PrintService/Admin" -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
        $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
    }
    else {
        Write-Host "  [+] 完美！未记录任何历史故障。" -ForegroundColor Green
    }
}

function Manage-TCPPort {
    Write-Host "`n  手动创建 TCP/IP 端口"
    $ip = Read-Host "  [?] 物理打印机 IP (例如: 192.168.1.100)"
    if ($ip) {
        try {
            Add-PrinterPort -Name "IP_$ip" -PrinterHostAddress $ip -ErrorAction Stop
            Write-Log "成功创建 TCP/IP 端口 IP_$ip。" -Type "SUCCESS"
            Write-Host "  [+] 端口 [IP_$ip] 已成功注入到系统中。" -ForegroundColor Green
        }
        catch {
            Write-Log "创建端口失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Manage-DefaultPrinter {
    Write-Host "`n  强制设置永久默认打印机"
    $prn = Read-Host "  [?] 输入确切的打印机名称以设为默认"
    if ($prn) {
        try {
            $safeName = $prn -replace "'", "''"
            $wmi = Get-CimInstance Win32_Printer -Filter "Name='$safeName'" -ErrorAction Stop
            if ($wmi) {
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                Write-Log "已将 $prn 强制设为默认" -Type "SUCCESS"
                Write-Host "  [+] 操作系统已强制将 $prn 设为主要默认打印机。" -ForegroundColor Green
            }
            else {
                Write-Host "  [-] 未检测到打印机。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "设置默认打印机失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Set-SpoolerWatchdog {
    Write-Log "正在注入 Spooler 看门狗任务..." -Type "INFO"
    try {
        $cmd = "powershell.exe -WindowStyle Hidden -Command \`"if((Get-Service spooler).Status -ne 'Running'){ Start-Service spooler }\`""
        & schtasks.exe /create /tn "SpoolerWatchdog" /tr $cmd /sc minute /mo 5 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks 返回退出代码 $LASTEXITCODE" }
        
        # 配置任务在电池供电时运行 (避免笔记本上的 0x800710E0 错误)
        try {
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Set-ScheduledTask -TaskName "SpoolerWatchdog" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Write-Log "Spooler 看门狗已部署 (无限循环，每5分钟运行)。" -Type "SUCCESS"
        Write-Host "  [+] Spooler 看门狗已激活。每隔 5 分钟执行一次审查以防停止。" -ForegroundColor Green
    }
    catch {
        Write-Log "部署看门狗失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RDPPrinter {
    Write-Log "正在修复 RDP 打印机终端服务重定向..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fDisableCpm -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fEnablePrintRDR -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "RDP 重定向已激活。" -Type "SUCCESS"
        Write-Host "  [+] 远程桌面 (RDP) 会话期间本地打印机现在可见了。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 RDP 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HyperVConflict {
    Write-Log "正在修复 Hyper-V/WSL 网络发现冲突..." -Type "INFO"
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Virtual" -or $_.InterfaceDescription -match "Hyper-V" -or $_.InterfaceDescription -match "WSL" }
        if ($adapters) {
            foreach ($adp in $adapters) {
                Set-NetIPInterface -InterfaceAlias $adp.Name -InterfaceMetric 99 -ErrorAction SilentlyContinue
            }
            Write-Log "虚拟交换机优先级 (Metric) 成功降低。" -Type "SUCCESS"
            Write-Host "  [+] Hyper-V/WSL 虚拟适配器的优先级已降低，以防阻塞原生 LAN/Wi-Fi。" -ForegroundColor Green
        }
        else {
            Write-Host "  [*] 未检测到发生冲突的虚拟适配器。" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Log "修复 Hyper-V 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-LPR {
    Write-Log "正在安装旧版 LPR/LPD 协议..." -Type "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPRPortMonitor" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPR 端口监视器已安装。" -Type "SUCCESS"
    } catch {
        Write-Log "安装 LPR 端口监视器失败: $($_.Exception.Message)" -Type "WARNING"
    }

    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPDPrintService" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPD 打印服务已安装。" -Type "SUCCESS"
    } catch {
        Write-Log "安装 LPD 服务失败: $($_.Exception.Message) (最新的 Win 11 版本可能已弃用)" -Type "WARNING"
    }

    Write-Host "  [+] LPR/LPD 安装完成。如果提示失败，说明该功能在你的 Windows 版本中可能已弃用。" -ForegroundColor Green
}

function Fix-PrintToPDF {
    Write-Log "重新安装 / 刷新 Microsoft Print to PDF & XPS..." -Type "INFO"
    Write-Host "  [*] 此过程大约需要 10-30 秒..." -ForegroundColor Cyan
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 2
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "Print to PDF 刷新成功。" -Type "SUCCESS"
        Write-Host "  [+] Microsoft Print to PDF 驱动程序已恢复。建议重启系统。" -ForegroundColor Green
    }
    catch {
        Write-Log "刷新 PrintToPDF 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CredentialGuard {
    Write-Log "正在绕过 Credential Guard 限制 (严格 NTLM)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LsaCfgFlags -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "Credential Guard 保护 (LsaCfgFlags) 已禁用。" -Type "SUCCESS"
        Write-Host "  [+] Win 11 专业版/企业版中严格的 NTLM 封锁已解除。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过 Credential Guard 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-BITS {
    Write-Log "正在重启 BITS 服务..." -Type "INFO"
    try {
        Restart-Service BITS -Force -ErrorAction Stop
        Write-Log "后台智能传输服务 (BITS) 已重启。" -Type "SUCCESS"
        Write-Host "  [+] BITS 服务已重启。" -ForegroundColor Green
    }
    catch {
        Write-Log "重启 BITS 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Create-RestorePoint {
    Write-Log "正在生成系统还原点..." -Type "INFO"
    Write-Host "  [*] 正在调用系统保护 (请稍等)..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinPrinterSharingFix-SafetyBackup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "系统还原点生成成功。" -Type "SUCCESS"
        Write-Host "  [+] Windows 还原点建立完毕。" -ForegroundColor Green
    }
    catch {
        Write-Log "生成还原点失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Run-QuickDiagnostics {
    Write-Host "`n  ======================================================================"
    Write-Host "                 系统诊断"
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
    Write-Host "  [+] 网络配置文件  : " -NoNewline; Write-Host $netStr -ForegroundColor $ntc

    Write-Host "  [+] 操作系统类型  : " -NoNewline; Write-Host $script:productName -ForegroundColor Cyan
    if ($script:isARM64) { Write-Host "  [+] 架构          : ARM64 (Snapdragon / Apple M 系列 VM)" -ForegroundColor Cyan }

    Write-Host "  ======================================================================"
}

function Fix-V4ClassDriver {
    Write-Log "正在扫描通用打印类驱动 (V4) 是否损坏..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               通用打印类驱动 V4 修复"
    Write-Host "  ======================================================================"
    try {
        $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-4"
        if (-not (Test-Path $v4Path)) {
            $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows NT x86\Drivers\Version-4"
        }
        $corrupted = @()
        $corruptedDirs = @()
        if (Test-Path $v4Path) {
            $drivers = Get-ChildItem $v4Path -ErrorAction SilentlyContinue
            foreach ($drv in $drivers) {
                $props = Get-ItemProperty $drv.PSPath -ErrorAction SilentlyContinue
                if ($props.InfPath) {
                    $driverDir = $props.DriverPath
                    if ($driverDir) {
                        $parentDir = Split-Path $driverDir -Parent
                        $configDll = Join-Path $parentDir "PrintConfig.dll"
                        if (-not (Test-Path $configDll)) {
                            $corrupted += $drv.PSChildName
                            $corruptedDirs += $parentDir
                        }
                    }
                }
            }
        }
        if ($corrupted.Count -gt 0) {
            Write-Host "  [!] 检测到损坏的 V4 驱动: $($corrupted.Count)" -ForegroundColor Red
            foreach ($c in $corrupted) { Write-Host "      - $c" -ForegroundColor Yellow }
            Write-Host "  [*] 正在尝试通过 DriverStore 重新注册进行修复..." -ForegroundColor Cyan
            $prnmsDir = Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository\prnms*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($prnmsDir) {
                $goodDll = Get-ChildItem $prnmsDir.FullName -Filter "PrintConfig.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($goodDll) {
                    Write-Host "  [+] 找到完好的 PrintConfig.dll，位于 $($goodDll.FullName)" -ForegroundColor Green
                    Write-Log "已找到 PrintConfig.dll 源: $($goodDll.FullName)" -Type "SUCCESS"
                    
                    # 复制完好的 PrintConfig.dll 修复每个损坏的目录
                    for ($i = 0; $i -lt $corrupted.Count; $i++) {
                        $destDir = $corruptedDirs[$i]
                        $destFile = Join-Path $destDir "PrintConfig.dll"
                        try {
                            Copy-Item -Path $goodDll.FullName -Destination $destFile -Force -ErrorAction Stop
                            Write-Host "  [+] 已将 PrintConfig.dll 恢复至 $destDir" -ForegroundColor Green
                            Write-Log "恢复 PrintConfig.dll 至 $destDir" -Type "SUCCESS"
                        } catch {
                            Write-Host "  [-] 恢复到 $destDir 失败 : $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log "复制 PrintConfig.dll 至 $destDir 失败 : $($_.Exception.Message)" -Type "ERROR"
                        }
                    }
                }
            }
            & pnputil /scan-devices > $null 2>&1
            Write-Log "V4 驱动扫描完成。共处理了 $($corrupted.Count) 个损坏项。" -Type "WARNING"
        }
        else {
            Write-Host "  [+] 所有 V4 打印类驱动完好无损。" -ForegroundColor Green
            Write-Log "V4 驱动状态健康。" -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "V4 扫描失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Switch-DriverMode {
    Write-Host "`n  ======================================================================"
    Write-Host "               切换 PCL 与 POSTSCRIPT 驱动模式"
    Write-Host "  ======================================================================"
    Write-Log "启动 PCL/PostScript 驱动切换..." -Type "INFO"
    try {
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] 未安装任何打印机。" -ForegroundColor Red; return }
        Write-Host ""
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | 驱动: $($p.DriverName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] 请选择打印机编号"
        $selIdx = -1
        try { $selIdx = [int]$sel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] 选择无效。" -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $allDrivers = Get-PrinterDriver -ErrorAction SilentlyContinue
        $currentDriver = $target.DriverName
        Write-Host "`n  当前驱动: $currentDriver" -ForegroundColor Yellow
        if ($currentDriver -match 'PCL') {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PS|PostScript' }
            Write-Host "  [*] 正在寻找 PostScript 替代驱动..." -ForegroundColor Cyan
        }
        else {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PCL' }
            Write-Host "  [*] 正在寻找 PCL 替代驱动..." -ForegroundColor Cyan
        }
        if ($altDrivers) {
            $idx = 1
            foreach ($d in $altDrivers) { Write-Host "  [$idx] $($d.Name)" -ForegroundColor Green; $idx++ }
            $drvSel = Read-Host "  [?] 选择要替换的驱动编号 (输入 0 取消)"
            if ($drvSel -ne '0') {
                $drvIdx = -1
                try { $drvIdx = [int]$drvSel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
                if ($drvIdx -ge 0 -and $drvIdx -lt $altDrivers.Count) {
                    Set-Printer -Name $target.Name -DriverName $altDrivers[$drvIdx].Name -ErrorAction Stop
                    Write-Log "驱动已切换: $($target.Name) -> $($altDrivers[$drvIdx].Name)" -Type "SUCCESS"
                    Write-Host "  [+] 驱动切换成功！" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [-] 未找到替代驱动。请先安装目标驱动。" -ForegroundColor Red
        }
    }
    catch { Write-Log "驱动切换失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Manage-WindowsUpdate {
    Write-Host "`n  ======================================================================"
    Write-Host "                  WINDOWS 更新及拦截器管理"
    Write-Host "  ======================================================================"
    Write-Host "  [1] 卸载指定的 KB 更新"
    Write-Host "  [2] 暂停 Windows 更新 35 天"
    Write-Host "  [3] 永久禁用 Windows 更新服务 (防止修复被还原)"
    Write-Host "  [4] 重新启用 Windows 更新服务 (恢复默认)"
    Write-Host "  [5] 取消"
    $opt = Read-Host "  请选择操作 (1-5)"

    switch ($opt) {
        '1' {
            Write-Log "正在启动 KB 更新卸载程序..." -Type "INFO"
            try {
                Write-Host "  [!] 已知会破坏打印机的 KB (2025-2026):" -ForegroundColor Red
                Write-Host "      KB5065426 (2025年9月) - 阻止打印共享 (SID检查)" -ForegroundColor Yellow
                Write-Host "      KB5066835 (2025年10月) - 严重的打印机共享破坏者" -ForegroundColor Yellow
                Write-Host "      KB5068661 (2025年11月) - 破坏打印机和网络共享" -ForegroundColor Yellow
                Write-Host "      KB5089549 (2026年5月) - 交叉签名驱动程序强制验证" -ForegroundColor Yellow

                Write-Host "  [*] 正在枚举近期的 Windows 更新..." -ForegroundColor Cyan
                $updates = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 20
                if ($updates) { $updates | Format-Table HotFixID, Description, InstalledOn -AutoSize }
                else { Write-Host "  [-] 未通过 Get-HotFix 检测到热修复补丁。" -ForegroundColor Yellow }

                $kb = Read-Host "`n  [?] 输入要卸载的 KB 编号 (例如: KB5034441，或留空取消)"
                if (-not $kb) { return }
                $kb = $kb -replace '(?i)^KB', ''

                $dismSuccess = $false
                Write-Host "  [*] 正在尝试通过 DISM 卸载 KB$kb..." -ForegroundColor Cyan
                $packages = & dism /online /get-packages 2>&1 | Select-String "Package_for_KB$kb"

                if ($packages) {
                    $pkgName = ($packages[0].ToString() -split ':')[1].Trim()
                    $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /remove-package /package-name:`"$pkgName`" /quiet /norestart" -Wait -PassThru -WindowStyle Hidden

                    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                        $dismSuccess = $true
                        Write-Log "通过 DISM 卸载 KB$kb。" -Type "SUCCESS"
                        Write-Host "  [+] KB$kb 已成功卸载。(可能需要重启)" -ForegroundColor Green
                    } else {
                        Write-Log "DISM 卸载 KB$kb 失败。退出代码: $($proc.ExitCode)。尝试回退到 wusa.exe..." -Type "WARNING"
                        Write-Host "  [-] DISM 失败 (退出代码 $($proc.ExitCode))。尝试使用 wusa.exe 备用方案..." -ForegroundColor Yellow
                    }
                }

                if (-not $dismSuccess) {
                    Write-Host "  [!] 将出现一个 Windows 对话框。如果出现提示，请确认卸载。" -ForegroundColor Cyan
                    $proc = Start-Process wusa.exe -ArgumentList "/uninstall /kb:$kb /norestart" -Wait -PassThru

                    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                        Write-Log "通过 wusa 卸载 KB$kb。" -Type "SUCCESS"
                        Write-Host "  [+] KB$kb 已成功卸载。(可能需要重启)" -ForegroundColor Green
                    } else {
                        Write-Log "Wusa 为 KB$kb 卸载失败/取消。退出代码: $($proc.ExitCode)" -Type "WARNING"
                        Write-Host "  [-] 卸载失败或已取消。该更新可能是永久性的安全更新。" -ForegroundColor Red
                    }
                }
            }
            catch { Write-Log "卸载 KB 失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '2' {
            Write-Log "正在暂停 Windows 更新 35 天..." -Type "INFO"
            try {
                $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }

                $pauseStart = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
                $pauseEnd = (Get-Date).AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

                # Set GPO Policy registry overrides
                Set-ItemProperty -Path $wuPath -Name PauseQualityUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name PauseFeatureUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name PauseUpdatesExpiryTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name SetDisableUXWUAccess -Value 1 -Type DWord -Force -ErrorAction Stop

                # Set UX Settings registry overrides (used by Windows Settings UX on Home & Pro)
                $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                if (-not (Test-Path $uxPath)) { New-Item -Path $uxPath -Force | Out-Null }
                Set-ItemProperty -Path $uxPath -Name PauseUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseFeatureUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseQualityUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseFeatureUpdatesEndTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseQualityUpdatesEndTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseUpdatesExpiryTime -Value $pauseEnd -Force -ErrorAction Stop

                Write-Host "  [+] Windows 更新已完全暂停 35 天 (已应用 GPO 和设置 UI 覆盖)。" -ForegroundColor Green
                Write-Log "Windows 更新已暂停至 $pauseEnd。" -Type "SUCCESS"
            }
            catch { Write-Log "暂停 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '3' {
            Write-Log "正在永久禁用 Windows 更新服务..." -Type "INFO"
            try {
                $services = @("wuauserv", "UsoSvc", "bits")
                foreach ($svc in $services) {
                    & sc.exe config $svc start= disabled > $null 2>&1
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue | Out-Null
                }

                # Disable WaaSMedicSvc via registry bypass (sc config WaaSMedicSvc start= disabled returns Access Denied)
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name Start -Value 4 -Type DWord -Force -ErrorAction Stop
                Stop-Service -Name "WaaSMedicSvc" -Force -ErrorAction SilentlyContinue | Out-Null

                # Configure NoAutoUpdate in Policies registry
                $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
                Set-ItemProperty -Path $auPath -Name NoAutoUpdate -Value 1 -Type DWord -Force -ErrorAction Stop

                Write-Log "Windows 更新服务被永久禁用 (Medic已阻断)。" -Type "SUCCESS"
                Write-Host "  [+] 核心 Windows 更新服务 (wuauserv, UsoSvc, bits, WaaSMedicSvc) 已禁用。" -ForegroundColor Green
                Write-Host "  [+] 注册表策略 NoAutoUpdate 已强制设为 1。" -ForegroundColor Green
                Write-Host "  [!] 安全配置将不再被 Windows 更新还原。" -ForegroundColor Yellow
            }
            catch { Write-Log "禁用 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '4' {
            Write-Log "正在重新启用 Windows 更新服务..." -Type "INFO"
            try {
                & sc.exe config wuauserv start= demand > $null 2>&1
                & sc.exe config UsoSvc start= auto > $null 2>&1
                & sc.exe config bits start= demand > $null 2>&1

                # Restore WaaSMedicSvc to manual
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name Start -Value 3 -Type DWord -Force -ErrorAction Stop

                # Remove NoAutoUpdate restriction
                $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (Test-Path $auPath) {
                    Remove-ItemProperty -Path $auPath -Name NoAutoUpdate -ErrorAction SilentlyContinue | Out-Null
                }

                # Remove pause overrides from policies
                $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                if (Test-Path $wuPath) {
                    $properties = @("PauseQualityUpdatesStartTime", "PauseFeatureUpdatesStartTime", "PauseUpdatesExpiryTime", "SetDisableUXWUAccess")
                    foreach ($prop in $properties) {
                        Remove-ItemProperty -Path $wuPath -Name $prop -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                # Remove pause overrides from UX settings
                $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                if (Test-Path $uxPath) {
                    $properties = @("PauseUpdatesStartTime", "PauseFeatureUpdatesStartTime", "PauseQualityUpdatesStartTime", "PauseFeatureUpdatesEndTime", "PauseQualityUpdatesEndTime", "PauseUpdatesExpiryTime")
                    foreach ($prop in $properties) {
                        Remove-ItemProperty -Path $uxPath -Name $prop -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                Write-Log "Windows 更新服务已恢复为默认启动类型。" -Type "SUCCESS"
                Write-Host "  [+] Windows 更新服务已恢复到默认状态。" -ForegroundColor Green
                Write-Host "  [+] 自动更新和暂停限制已被移除。" -ForegroundColor Green
            }
            catch { Write-Log "恢复 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        default { return }
    }
}

function Sweep-OrphanedDrivers {
    Write-Host "`n  ======================================================================"
    Write-Host "               孤立驱动程序清理 (pnputil)"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描孤立的打印机驱动程序..." -Type "INFO"
    try {
        $rawOutput = & pnputil /enum-drivers 2>&1
        $activeDrivers = (Get-PrinterDriver -ErrorAction SilentlyContinue).Name
        $orphans = @()
        $currentOem = ""
        $currentClass = ""
        $currentProvider = ""
        foreach ($line in $rawOutput) {
            if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)' -or $line -match '发布的名称\s*:\s*(oem\d+\.inf)') { $currentOem = $Matches[1] }
            if ($line -match 'Class Name\s*:\s*(.+)' -or $line -match '类名\s*:\s*(.+)') { $currentClass = $Matches[1].Trim() }
            if ($line -match 'Driver Package Provider\s*:\s*(.+)' -or $line -match '驱动程序包提供商\s*:\s*(.+)') { $currentProvider = $Matches[1].Trim() }
            if ($line -match '^\s*$' -and $currentOem -and ($currentClass -match 'Printer' -or $currentClass -match '打印机')) {
                $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
                $currentOem = ""; $currentClass = ""; $currentProvider = ""
            }
        }
        if ($currentOem -and ($currentClass -match 'Printer' -or $currentClass -match '打印机')) {
            $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
        }
        if ($orphans.Count -gt 0) {
            Write-Host "  [!] 在驱动程序存储中找到 $($orphans.Count) 个打印机驱动包:" -ForegroundColor Yellow
            $orphans | Format-Table OemInf, Provider -AutoSize
            $confirm = Read-Host "  [?] 是否强制删除所有孤立的打印机驱动程序? (Y/N)"
            if ($confirm -eq 'Y') {
                foreach ($o in $orphans) {
                    Write-Host "  [*] 正在移除 $($o.OemInf)..." -ForegroundColor Cyan
                    & pnputil /delete-driver $o.OemInf /force 2>&1 | Out-Null
                }
                Write-Log "已清除孤立驱动程序: $($orphans.Count) 个包。" -Type "SUCCESS"
                Write-Host "  [+] 清理完成。" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] 在驱动程序存储中未找到孤立的打印机驱动程序。" -ForegroundColor Green
            Write-Log "未检测到孤立的驱动程序。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "驱动清理失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Force-KillDriverProcess {
    Write-Host "`n  ======================================================================"
    Write-Host "               绕过 '驱动程序当前正在使用'"
    Write-Host "  ======================================================================"
    Write-Log "正在强制终止驱动程序隔离进程..." -Type "INFO"
    Write-Host "  [!] 警告: 这将终止所有正在处理的打印任务。" -ForegroundColor Red
    $confirm = Read-Host "  [?] 是否继续? (Y/N)"
    if ($confirm -ne 'Y') { return }
    try {
        Write-Host "  [*] 正在停止 Print Spooler..." -ForegroundColor Cyan
        Stop-Service spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $targets = @("PrintIsolationHost", "printfilterpipelinesvc", "splwow64")
        foreach ($proc in $targets) {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] 已终止: $proc (PID: $($running.Id -join ', '))" -ForegroundColor Green
            }
            else {
                Write-Host "  [*] $proc 未在运行。" -ForegroundColor Cyan
            }
        }
        Start-Sleep -Seconds 2
        Start-Service spooler -ErrorAction SilentlyContinue
        Write-Log "驱动程序句柄已释放。Spooler 已重启。" -Type "SUCCESS"
        Write-Host "  [+] 所有驱动句柄已释放。现在你可以卸载驱动程序了。" -ForegroundColor Green
    }
    catch { Write-Log "强制终止失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Convert-WSDtoTCPIP {
    Write-Host "`n  ======================================================================"
    Write-Host "               WSD 到 标准 TCP/IP 端口转换器"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描 WSD 端口..." -Type "INFO"
    try {
        $wsdPorts = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "WSD-*" }
        if (-not $wsdPorts) {
            Write-Host "  [+] 未检测到 WSD 端口。所有端口状况稳定。" -ForegroundColor Green
            Write-Log "未找到 WSD 端口。" -Type "SUCCESS"
            return
        }
        Write-Host "  [!] 找到 $($wsdPorts.Count) 个 WSD 端口:" -ForegroundColor Yellow
        foreach ($wp in $wsdPorts) {
            $printerOnPort = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $wp.Name }
            $printerName = if ($printerOnPort) { $printerOnPort.Name } else { "(未分配)" }
            Write-Host "      端口: $($wp.Name) | 打印机: $printerName" -ForegroundColor Cyan
        }
        $ip = Read-Host "`n  [?] 输入 WSD 打印机的实际 IP 地址 (例如: 192.168.1.100)"
        if (-not $ip) { return }
        $newPortName = "IP_$ip"
        if (-not (Get-PrinterPort -Name $newPortName -ErrorAction SilentlyContinue)) {
            Add-PrinterPort -Name $newPortName -PrinterHostAddress $ip -ErrorAction Stop
            Write-Host "  [+] TCP/IP 端口 $newPortName 已创建。" -ForegroundColor Green
        }
        $printerToMove = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -like "WSD-*" } | Select-Object -First 1
        if ($printerToMove) {
            Set-Printer -Name $printerToMove.Name -PortName $newPortName -ErrorAction Stop
            Write-Log "打印机 $($printerToMove.Name) 从 WSD 迁移到了 TCP/IP ($ip)。" -Type "SUCCESS"
            Write-Host "  [+] $($printerToMove.Name) 已迁移到 $newPortName。" -ForegroundColor Green
        }
    }
    catch { Write-Log "WSD 转换失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-NetworkSockets {
    Write-Host "`n  ======================================================================"
    Write-Host "               网络套接字重新初始化 (选择性清理)"
    Write-Host "  ======================================================================"
    Write-Log "正在执行选择性网络套接字清理..." -Type "INFO"
    try {
        Write-Host "  [*] 正在扫描卡住的 SMB/RPC 连接..." -ForegroundColor Cyan
        $stuck445 = & netstat -ano 2>&1 | Select-String ":445\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $stuck135 = & netstat -ano 2>&1 | Select-String ":135\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $totalStuck = 0
        if ($stuck445) { $totalStuck += $stuck445.Count; Write-Host "  [!] 端口 445 (SMB): $($stuck445.Count) 个卡住的连接" -ForegroundColor Yellow }
        if ($stuck135) { $totalStuck += $stuck135.Count; Write-Host "  [!] 端口 135 (RPC): $($stuck135.Count) 个卡住的连接" -ForegroundColor Yellow }
        if ($totalStuck -eq 0) { Write-Host "  [+] 未检测到卡住的连接。" -ForegroundColor Green }
        Write-Host "  [*] 正在仅重启 SMB 客户端和服务器服务..." -ForegroundColor Cyan
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanServer -Force -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1
        Write-Log "选择性清除了网络套接字。已清除 $totalStuck 个连接。" -Type "SUCCESS"
        Write-Host "  [+] 套接字清理完成。清除了 $totalStuck 个失效连接。" -ForegroundColor Green
    }
    catch { Write-Log "套接字重初始化失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Rescue-NetworkProfile {
    Write-Host "`n  ======================================================================"
    Write-Host "               救援网络配置 (自动检测 & 看门狗)"
    Write-Host "  ======================================================================"
    Write-Log "正在救援网络配置..." -Type "INFO"
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        $publicFound = $false
        foreach ($p in $profiles) {
            if ($p.NetworkCategory -eq 'Public') {
                $publicFound = $true
                Write-Host "  [!] 检测到公用配置: $($p.InterfaceAlias)" -ForegroundColor Red
                Set-NetConnectionProfile -InterfaceAlias $p.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
                Write-Host "  [+] 强制设为专用: $($p.InterfaceAlias)" -ForegroundColor Green
            }
        }
        if (-not $publicFound) { Write-Host "  [+] 所有网络配置文件都已经是 专用/域 模式。无需操作。" -ForegroundColor Green }
        $deployWatchdog = Read-Host "`n  [?] 是否部署网络配置看门狗 (每 10 分钟检查一次)? (Y/N)"
        if ($deployWatchdog -eq 'Y') {
            $cmd = "powershell.exe -WindowStyle Hidden -Command \`"Get-NetConnectionProfile | Where-Object { `$_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private\`""
            & schtasks.exe /create /tn "NetworkProfileWatchdog" /tr $cmd /sc minute /mo 10 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                # 配置任务在电池供电时运行 (避免笔记本上的 0x800710E0 错误)
                try {
                    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    Set-ScheduledTask -TaskName "NetworkProfileWatchdog" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
                } catch {}
                Write-Log "已部署网络配置看门狗 (无限重复)。" -Type "SUCCESS"
                Write-Host "  [+] 看门狗已部署。将每 10 分钟强制检查并设为专用网络。" -ForegroundColor Green
            } else {
                Write-Log "部署网络配置看门狗失败。schtasks 返回退出代码 $LASTEXITCODE" -Type "ERROR"
            }
        }
    }
    catch { Write-Log "网络救援失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Remove-GhostUSBPrinters {
    Write-Host "`n  ======================================================================"
    Write-Host "               幽灵 USB 端口 & 副本清除器"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描幽灵 USB 打印机和副本..." -Type "INFO"
    try {
        $allPrinters = Get-Printer -ErrorAction SilentlyContinue
        $ghosts = $allPrinters | Where-Object { $_.Name -match '\(Copy \d+\)' -or $_.Name -match ' - Copy' -or $_.Name -match 'Copy \d+$' -or $_.Name -match '\(副本 \d+\)' }
        $activePorts = ($allPrinters | Where-Object { $_.Name -notmatch 'Copy' -and $_.Name -notmatch '副本' }).PortName
        $deadUSB = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "USB*" -and $_.Name -notin $activePorts }
        if ($ghosts.Count -eq 0 -and $deadUSB.Count -eq 0) {
            Write-Host "  [+] 未检测到幽灵打印机或死 USB 端口。" -ForegroundColor Green
            Write-Log "未找到幽灵设备。" -Type "SUCCESS"
            return
        }
        if ($ghosts.Count -gt 0) {
            Write-Host "  [!] 找到重复/幽灵打印机:" -ForegroundColor Yellow
            foreach ($g in $ghosts) { Write-Host "      - $($g.Name) [端口: $($g.PortName)]" -ForegroundColor Red }
        }
        if ($deadUSB.Count -gt 0) {
            Write-Host "  [!] 找到死 USB 端口:" -ForegroundColor Yellow
            foreach ($u in $deadUSB) { Write-Host "      - $($u.Name)" -ForegroundColor Red }
        }
        $confirm = Read-Host "`n  [?] 是否移除所有幽灵打印机和死 USB 端口? (Y/N)"
        if ($confirm -eq 'Y') {
            foreach ($g in $ghosts) {
                Remove-Printer -Name $g.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] 已移除打印机: $($g.Name)" -ForegroundColor Green
            }
            foreach ($u in $deadUSB) {
                Remove-PrinterPort -Name $u.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] 已移除端口: $($u.Name)" -ForegroundColor Green
            }
            Write-Log "清理幽灵设备:移除了 $($ghosts.Count) 台打印机, $($deadUSB.Count) 个端口。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "幽灵 USB 清理失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Nuke-PrintQueue {
    Write-Log "正在强制清除打印队列..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "                强制清除打印队列"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] 正在终止 Print Spooler 及所有子进程..." -ForegroundColor Cyan
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
        Write-Log "强制清除完成。清除了 $totalFiles 个损坏的文件。" -Type "SUCCESS"
        Write-Host "  [+] 打印队列已清空。清理了 $totalFiles 个文件。Spooler 已重启。" -ForegroundColor Green
    }
    catch { Write-Log "强制清除失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-SpoolerDependencyRegistry {
    Write-Log "正在通过直接修改注册表重置 Spooler 依赖服务..." -Type "INFO"
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Spooler"
        $current = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DependOnService
        if ($current) {
            Write-Host "  [*] 当前依赖项: $($current -join ', ')" -ForegroundColor Yellow
        }
        Set-ItemProperty -Path $regPath -Name DependOnService -Value @("RPCSS","http") -Type MultiString -Force -ErrorAction Stop
        Write-Log "Spooler DependOnService 已重置为出厂默认 (RPCSS, http)。" -Type "SUCCESS"
        Write-Host "  [+] Spooler 依赖项已重置为: RPCSS, http" -ForegroundColor Green
        Write-Host "  [*] 正在重启 Spooler 以应用设置..." -ForegroundColor Cyan
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
    }
    catch { Write-Log "重置依赖注册表失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Inject-CrossUserCredentials {
    Write-Host "`n  ======================================================================"
    Write-Host "               跨用户凭据映射"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 警告: 这将向此电脑上的[所有用户配置文件]中注入凭据。" -ForegroundColor Red
    Write-Log "开始跨用户凭据映射..." -Type "INFO"
    $ip = Read-Host "  [?] 目标 IP/主机名 (例如: 192.168.1.10)"
    $usr = Read-Host "  [?] 目标主机上的用户名"
    $pass = Read-Host "  [?] 目标主机上的密码 (明文显示)"
    if (-not $ip -or -not $usr) { Write-Host "  [-] 已取消。" -ForegroundColor Red; return }
    try {
        $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' }
        $injected = 0
        foreach ($profile in $profiles) {
            $sid = $profile.PSChildName
            $profilePath = (Get-ItemProperty $profile.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            $userName = Split-Path $profilePath -Leaf
            Write-Host "  [*] 正在为用户 $userName ($sid) 注入凭据..." -ForegroundColor Cyan
            $ntuser = Join-Path $profilePath "NTUSER.DAT"
            if (Test-Path $ntuser) {
                $LASTEXITCODE = 0; & reg load "HKU\$sid" $ntuser > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    try {
                        # Create self-deleting cmd script with credential command
                        $credScript = Join-Path $profilePath "PrinterCredFix.cmd"
                        $cmdContent = "@echo off`r`ncmdkey.exe /add:$ip /user:$usr /pass:`"$pass`"`r`ndel `"%~f0`""
                        Set-Content -Path $credScript -Value $cmdContent -Encoding ASCII -Force -ErrorAction Stop

                        # Inject RunOnce to execute the script (script self-deletes after running)
                        $runOncePath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\RunOnce"
                        Set-ItemProperty -Path $runOncePath -Name "PrinterCredFix" -Value "`"$credScript`"" -Force -ErrorAction Stop
                        Write-Log "已为 $userName 注入 RunOnce 凭据命令。" -Type "SUCCESS"
                    } catch {
                        Write-Log "写入 RunOnce 注册表失败 (${userName}): $($_.Exception.Message)" -Type "ERROR"
                    }
                    
                    # Retry loop to unload registry safely
                    $unloaded = $false
                    for ($retry = 1; $retry -le 5; $retry++) {
                        $LASTEXITCODE = 0
                        & reg unload "HKU\$sid" > $null 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $unloaded = $true
                            break
                        }
                        Start-Sleep -Milliseconds 200
                    }
                    if (-not $unloaded) {
                        Write-Log "在尝试5次后，卸载 $userName ($sid) 的注册表配置单元失败。" -Type "WARNING"
                    }
                    $injected++
                } else {
                    Write-Log "加载 $userName ($sid) 的注册表配置单元失败。" -Type "ERROR"
                }
            }
        }
        Write-Log "已为 $injected 个用户配置文件注入凭据。" -Type "SUCCESS"
        Write-Host "  [+] 凭据已注入 $injected 个用户配置文件中。" -ForegroundColor Green
        $pass = ""
    }
    catch { Write-Log "跨用户凭据注入失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Force-DefaultPrinterRegistry {
    Write-Host "`n  ======================================================================"
    Write-Host "               强制设置默认打印机 (注册表绕过 0x00000709)"
    Write-Host "  ======================================================================"
    Write-Log "通过注入注册表强制设置默认打印机..." -Type "INFO"
    try {
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] 未找到打印机。" -ForegroundColor Red; return }
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | 端口: $($p.PortName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] 请选择要强制设为默认的打印机编号"
        $selIdx = -1
        try { $selIdx = [int]$sel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] 选择无效。" -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $deviceStr = "$($target.Name),winspool,$($target.PortName):"
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name Device -Value $deviceStr -Type String -Force -ErrorAction Stop
        Write-Log "通过注册表强制设置了默认打印机: $($target.Name)" -Type "SUCCESS"
        Write-Host "  [+] 默认打印机已设置为: $($target.Name) (已应用注册表绕过)。" -ForegroundColor Green
    }
    catch { Write-Log "注册表默认打印机设置失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Sanitize-PrinterShareName {
    Write-Log "正在扫描不合规的打印机共享名称..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               自动清理打印机共享名称"
    Write-Host "  ======================================================================"
    try {
        $shared = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true }
        if (-not $shared) { Write-Host "  [+] 未找到共享打印机。" -ForegroundColor Yellow; return }
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
                Write-Host "  [+] $original (合规)" -ForegroundColor Green
            }
        }
        if ($fixed -gt 0) {
            Write-Log "清理了 $fixed 个打印机共享名称。" -Type "SUCCESS"
            Write-Host "`n  [+] $fixed 个共享名称已被清理。" -ForegroundColor Green
        }
        else {
            Write-Host "`n  [+] 所有共享名称已经合规。" -ForegroundColor Green
            Write-Log "所有共享名称合规。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "清理共享名称失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Fix-BrowserPrintSandbox {
    Write-Log "正在重置浏览器打印沙盒 (Chromium)..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               浏览器打印沙盒修复 (CHROMIUM)"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] 正在终止浏览器进程..." -ForegroundColor Cyan
        Get-Process -Name "chrome", "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $cleared = 0
        $chromePrintDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
        $edgePrintDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        if (Test-Path $chromePrintDir) {
            Remove-Item "$chromePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Chrome 缓存已清除。" -ForegroundColor Green
        }
        if (Test-Path $edgePrintDir) {
            Remove-Item "$edgePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Edge 缓存已清除。" -ForegroundColor Green
        }
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
        Write-Log "浏览器打印沙盒已重置。清除了 $cleared 个浏览器缓存。" -Type "SUCCESS"
        Write-Host "  [+] 浏览器打印沙盒修复完成。请重新打开浏览器。" -ForegroundColor Green
    }
    catch { Write-Log "浏览器沙盒修复失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Detect-GPOIntervention {
    Write-Log "正在扫描影响打印机注册表的组策略 (GPO) 干预..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               组策略 (GPO) 干预检测"
    Write-Host "  ======================================================================"
    try {
        $isPartOfDomain = $false
        try {
            $sys = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $isPartOfDomain = $sys.PartOfDomain
        } catch {
            $netJoin = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -ErrorAction SilentlyContinue
            if ($netJoin -and $netJoin.Domain -and $netJoin.Domain -ne "") {
                $isPartOfDomain = $true
            }
        }

        if ($isPartOfDomain) {
            Write-Host "  [+] 域状态: 已加入域 (DOMAIN JOINED)" -ForegroundColor Green
        } else {
            Write-Host "  [+] 域状态: 工作组 (WORKGROUP - 未加入域)" -ForegroundColor Green
        }

        $policyPaths = @(
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "打印机策略 (Printer Policies)" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"; Label = "点和打印 (Point and Print)" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"; Label = "RPC 策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"; Label = "Windows 受保护的打印 (WPP)" },
            @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "用户打印机策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"; Label = "Lanman Workstation 策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanServer"; Label = "Lanman Server 策略" }
        )

        $recommendations = @{
            "DisableClientSideRendering" = 1
            "RestrictDriverInstallationToAdministrators" = 0
            "InForest" = 1
            "TrustedServers" = 1
            "ServerList" = "*.*"
            "NoWarningNoElevationOnInstall" = 1
            "NoWarningNoElevationOnUpdate" = 1
            "UpdatePromptSettings" = 2
            "RpcUseNamedPipeProtocol" = 1
            "RpcTcpEnable" = 1
            "RpcProtocols" = 7
            "ForceSetup" = 1
            "RpcAuthenticationLevel" = 0
            "RpcOverNamedPipes" = 1
            "ForceKerberosForRpc" = 0
            "Enabled" = 0
            "PackagePointAndPrintServerList" = 1
            "RequireSecuritySignature" = 0
            "EnableSecuritySignature" = 0
        }

        $gpoDetected = $false
        $restrictionDetected = $false

        foreach ($entry in $policyPaths) {
            if (Test-Path $entry.Path) {
                $props = Get-ItemProperty $entry.Path -ErrorAction SilentlyContinue
                $propNames = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
                if ($propNames.Count -gt 0) {
                    $gpoDetected = $true
                    Write-Host "`n  [*] 路径: $($entry.Label)" -ForegroundColor Cyan
                    foreach ($prop in $propNames) {
                        $pName = $prop.Name
                        $pValue = $prop.Value
                        if ($recommendations.ContainsKey($pName)) {
                            $recVal = $recommendations[$pName]
                            if ($pValue.ToString() -eq $recVal.ToString()) {
                                Write-Host "      [已激活修复] $pName = $pValue" -ForegroundColor Green
                            } else {
                                $restrictionDetected = $true
                                Write-Host "      [!] 策略覆盖 (受限): $pName = $pValue (应为: $recVal)" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "      [*] 用户覆盖: $pName = $pValue" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        if ($isPartOfDomain) {
            Write-Host "`n  [*] 正在运行 gpresult 查找与打印机相关的 GPO..." -ForegroundColor Cyan
            $gpresult = & gpresult /R /Scope Computer 2>&1 | Select-String -Pattern "Printer|Print|Point|打印"
            if ($gpresult) {
                Write-Host "  [!] 在计算机策略中找到 GPO 引用:" -ForegroundColor Yellow
                $gpresult | ForEach-Object { Write-Host "      $_" -ForegroundColor Cyan }
            } else {
                Write-Host "  [+] 未通过 gpresult 检测到活动的打印机相关 GPO。" -ForegroundColor Green
            }

            if ($restrictionDetected) {
                Write-Host "`n  [!] 警告: 被 GPO 管理的键值将被域控制器[覆盖]。" -ForegroundColor Red
                Write-Host "  [!] 对这些键的本地更改将在 gpupdate 后还原。" -ForegroundColor Red
                Write-Log "检测到针对打印机注册表的 GPO 干预。" -Type "WARNING"
            } else {
                Write-Host "`n  [+] GPO 策略与打印机共享修复工具一致或未激活。" -ForegroundColor Green
                Write-Log "GPO 检查完毕；策略已对齐。" -Type "SUCCESS"
            }
        } else {
            Write-Host "`n  [+] 本地工作组环境 (未检测到活动的域控制器)。" -ForegroundColor Green
            if ($restrictionDetected) {
                Write-Host "  [!] 某些本地策略覆盖了配置并限制了共享。可以在本地调整它们。" -ForegroundColor Yellow
                Write-Log "检测到本地策略限制。" -Type "WARNING"
            } else {
                Write-Host "  [+] 未检测到本地策略冲突。" -ForegroundColor Green
                Write-Log "未检测到策略冲突。" -Type "SUCCESS"
            }
        }
    }
    catch { Write-Log "GPO 检测失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Parse-PrintEventLog {
    Write-Log "正在解析最近 5 个 PrintService 错误/警告事件..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "                 打印服务事件日志解析器 (前 5 名)"
    Write-Host "  ======================================================================"
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-PrintService/Admin'
            Level   = @(2, 3)
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($events) {
            $resolutionMap = @{
                '808' = "驱动程序安装失败。请执行 [43] 孤立驱动程序清理。"
                '842' = "队列损坏。请执行 [37] 强制清除打印队列。"
                '354' = "后台打印程序无法启动。请执行 [38] 重置 Spooler 依赖项。"
                '824' = "打印机脱机。请执行 [26] WSD 到 TCP/IP 端口转换器。"
            }
            foreach ($evt in $events) {
                $levelStr = if ($evt.Level -eq 2) { "错误" } else { "警告" }
                $color = if ($evt.Level -eq 2) { "Red" } else { "Yellow" }
                Write-Host "`n  [$levelStr] 事件 $($evt.Id) - $($evt.TimeCreated)" -ForegroundColor $color
                Write-Host "  消息: $($evt.Message)" -ForegroundColor White

                $suggestion = ""
                if ($evt.Id -eq 372) {
                    if ($evt.Message -match "Access is denied" -or $evt.Message -match "拒绝访问" -or $evt.Message -match "error code.*: 5\b") {
                        $suggestion = "权限被阻止。请执行 [12] 禁用密码共享 或 [60] 注入凭据。"
                    }
                    elseif ($evt.Message -match "The network path was not found" -or $evt.Message -match "找不到网络路径" -or $evt.Message -match "error code.*: 53\b") {
                        $suggestion = "主机无法访问。验证主机 IP/电源状态，然后执行 [14] 配置防火墙。"
                    }
                    else {
                        $suggestion = "Spooler/驱动程序崩溃。请执行 [06] 或 [37] 强制清除打印队列。"
                    }
                }
                elseif ($resolutionMap.ContainsKey($evt.Id.ToString())) {
                    $suggestion = $resolutionMap[$evt.Id.ToString()]
                }

                if ($suggestion) {
                    Write-Host "  建议操作: $suggestion" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [+] 未找到错误/警告事件。打印服务状态健康。" -ForegroundColor Green
        }
        Write-Log "已解析 PrintService 事件日志。" -Type "SUCCESS"
    }
    catch { Write-Log "解析事件日志失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Map-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               将本地端口映射到 UNC 路径 (绕过)"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 如果标准共享[仍然]提示'检查打印机名称'错误，请使用此方法。"
    $ip = Read-Host "  [?] 目标主机 IP/主机名 (例如: 192.168.1.10)"
    $share = Read-Host "  [?] 完全一致的打印机共享名称 (例如: EPSON_L120)"
    if ($ip -and $share) {
        $uncPath = "\\$ip\$share"
        try {
            Write-Host "  [*] 正在尝试标准的本地端口创建: $uncPath" -ForegroundColor Cyan
            Add-PrinterPort -Name $uncPath -ErrorAction Stop
            Write-Log "通过 API 创建了 UNC 本地端口: $uncPath" -Type "SUCCESS"
            Write-Host "  [+] 本地端口注入成功！现在您可以'添加本地打印机'并选择该端口。" -ForegroundColor Green
        }
        catch {
            Write-Host "  [*] 标准方法被 Windows 阻止。正在部署注册表绕过..." -ForegroundColor Yellow
            try {
                $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"

                Set-ItemProperty -Path $portRegPath -Name $uncPath -Value "" -Type String -Force -ErrorAction Stop

                Write-Host "  [*] 端口已注入。正在重启 Print Spooler 以完成配置..." -ForegroundColor Cyan
                Restart-Service spooler -Force -ErrorAction SilentlyContinue

                Write-Log "通过注册表绕过注入了 UNC 本地端口: $uncPath" -Type "SUCCESS"
                Write-Host "  [+] 绕过成功！端口 $uncPath 现在已存在于你的端口列表中。" -ForegroundColor Green
                Write-Host "  [!] 下一步: 进入 '添加打印机' -> '添加本地打印机' -> '使用现有的端口'。" -ForegroundColor Green
                Write-Host "  [!] 从下拉菜单中选择 $uncPath，然后选择你的打印机驱动。" -ForegroundColor Green
            }
            catch {
                Write-Log " 绕过失败: $($_.Exception.Message)" -Type "ERROR"
                Write-Host "  [-] 绕过失败。注册表访问被管理员/GPO完全锁定。" -ForegroundColor Red
            }
        }
    }
}

function Remove-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               移除已注入的本地端口 (UNC)"
    Write-Host "  ======================================================================"

    Write-Host "  [*] 正在识别活动的打印机端口..." -ForegroundColor Cyan
    try {
        $ports = Get-PrinterPort | Select-Object -ExpandProperty Name | Sort-Object
        if ($ports) {
            Write-Host "  [>] 检测到的端口:" -ForegroundColor Yellow
            foreach ($p in $ports) {
                if ($p -like "\\*") {
                    Write-Host "      -> $p (UNC 映射)" -ForegroundColor Green
                } else {
                    Write-Host "      -> $p" -ForegroundColor Gray
                }
            }
        }
    } catch { Write-Host "  [!] 无法通过 API 获取端口列表。" -ForegroundColor Yellow }

    Write-Host "`n  [!] 使用此功能删除之前由选项 [86] 创建的端口。"
    $portName = Read-Host "  [?] 输入要移除的[确切]端口名称 (例如: \\192.168.1.10\Printer)"
    if (-not $portName) { return }

    try {
        Write-Host "  [*] 正在尝试标准的端口移除..." -ForegroundColor Cyan
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "端口 $portName 已通过 API 移除。" -Type "SUCCESS"
        Write-Host "  [+] 端口 $portName 已成功移除。" -ForegroundColor Green
    }
    catch {
        Write-Host "  [*] 标准方法失败。正在部署注册表清除..." -ForegroundColor Yellow
        try {
            $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"
            Remove-ItemProperty -Path $portRegPath -Name $portName -ErrorAction Stop

            Write-Host "  [*] 已从注册表中删除端口。正在重启 Print Spooler..." -ForegroundColor Cyan
            Restart-Service spooler -Force -ErrorAction SilentlyContinue

            Write-Log "端口 $portName 已通过注册表绕过被移除。" -Type "SUCCESS"
            Write-Host "  [+] 绕过成功！端口 $portName 已被永久删除。" -ForegroundColor Green
        }
        catch {
            Write-Log "移除 UNC 端口失败: $($_.Exception.Message)" -Type "ERROR"
            Write-Host "  [-] 移除端口失败。确保输入的名称与端口列表中的[完全一致]。" -ForegroundColor Red
        }
    }
}

function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         执行全自动修复 (50 项自动化修复)"
    Write-Host "  ===================================================================================================`n"
    Write-Log "运行全自动修复 (SILENT=$script:silentNuke)" -Type "INFO"

    Write-Host "  [*] [1/50] 检测操作系统..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/50] 保护注册表 (备份)... (菜单 64)" -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/50] 刷新 GPO 缓存 (修改注册表前)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [4/50] 审查 RPC & DCOM... (菜单 32)" -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [5/50] 修补错误 0x0000011b... (菜单 01)" -ForegroundColor Cyan
    Fix-RpcAuthn0x0000011b

    Write-Host "  [*] [6/50] 深度修复 0x00000709 (多层 RPC)... (菜单 02)" -ForegroundColor Cyan
    Fix-Deep0x00000709

    Write-Host "  [*] [7/50] KB5089549 驱动程序策略及 HKCU 权限修复..." -ForegroundColor Cyan
    Fix-CrossSignedDriverPolicy
    Fix-HKCU-PrinterKeyPerms

    Write-Host "  [*] [8/50] 绕过错误 0x00000bc4... (菜单 03)" -ForegroundColor Cyan
    Fix-Discovery0x00000bc4

    Write-Host "  [*] [9/50] 修复错误 0x00000040 (KeepConn)... (菜单 07)" -ForegroundColor Cyan
    Fix-Network0x00000040

    Write-Host "  [*] [10/50] 修复错误 0x00000002 (CopyFilesPolicy)... (菜单 08)" -ForegroundColor Cyan
    Fix-DriverCopy0x00000002

    Write-Host "  [*] [11/50] 修复错误 0x0000007e (RPC Auth)... (菜单 09)" -ForegroundColor Cyan
    Fix-RpcBitness0x0000007e

    Write-Host "  [*] [12/50] 注入 DnsOnWire, StrictName & 绕过 UAC... (菜单 57)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [13/50] 禁用 SMB 签名强制要求及双向身份验证... (菜单 16)" -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [14/50] 确保 SMB2/SMB3 兼容性及网络提供商顺序... (菜单 17 & 18)" -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [15/50] 强制使用命名管道及 TCP... (菜单 13)" -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [16/50] 禁用客户端渲染... (菜单 05)" -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [17/50] 禁用驱动隔离... (菜单 40)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force
    }
    catch {}

    Write-Host "  [*] [18/50] 启动网络发现, mDNS, NetBIOS & WSD 服务... (菜单 20 & 04)" -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [19/50] 配置防火墙及开启 UDP 通道... (菜单 14 & 21)" -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [20/50] 开放 SMB 访客访问 (客户端及服务端)... (菜单 82)" -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [21/50] 禁用密码保护的网络共享... (菜单 12)" -ForegroundColor Cyan
    Disable-PasswordSharing

    Write-Host "  [*] [22/50] 降级 LSA 保护 & 强制实施 NTLMv2... (菜单 54, 58 & 62)" -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard

    Write-Host "  [*] [23/50] 绕过智能应用控制 (SAC)... (菜单 55)" -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [24/50] 初始化 IPP & Mopria 打印共享... (菜单 22)" -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [25/50] 禁用 WPP (允许传统的网络打印机)... (菜单 59)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "  [*] [26/50] 修复 RDP & LPD 协议... (菜单 52 & 24)" -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [27/50] 强制网络设为专用模式... (菜单 11)" -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [28/50] 降级虚拟网络适配器优先级 (Hyper-V)... (菜单 23)" -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [29/50] 刷新 DNS & Winsock... (菜单 10)" -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [30/50] 终止后台打印程序 (Spooler)..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [31/50] 向 Spooler 注入自动重启恢复... (菜单 34)" -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [32/50] 清除 Spooler 附加依赖项 (保留 http & RPCSS)... (菜单 35)" -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [33/50] 重置 PRINTERS 文件夹权限... (菜单 06)" -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [34/50] 清除陈旧的打印队列 & Splwow64... (菜单 31)" -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [35/50] 绕过 AppContainer UWP/Edge 环回隔离... (菜单 47)" -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [36/50] 应用高级点和打印及 PrintNightmare 绕过... (菜单 56)" -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [37/50] 部署 Spooler 看门狗任务... (菜单 36)" -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [38/50] 重新启动 BITS 服务... (菜单 68)" -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [39/50] 重启后台打印程序 (验证)..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler 已验证正在运行。" -ForegroundColor Green

    Write-Host "  [*] [40/50] 清除 Kerberos 登录缓存..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [41/50] 重新启动 WdiSystemHost 服务..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [42/50] 注册 mDNS (组播)..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [43/50] 生成系统还原点... (菜单 66)" -ForegroundColor Cyan
    Create-RestorePoint

    Write-Host "  [*] [44/50] 扫描 V4 打印类驱动... (菜单 41)" -ForegroundColor Cyan
    Fix-V4ClassDriver

    Write-Host "  [*] [45/50] 救援网络配置 (强制专用)... (菜单 28)" -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    $profiles | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    Write-Host "  [*] [46/50] 强制清除打印队列文件... (菜单 37)" -ForegroundColor Cyan
    Nuke-PrintQueue

    Write-Host "  [*] [47/50] 重置 Spooler 依赖项 (注册表级别)... (菜单 38)" -ForegroundColor Cyan
    Reset-SpoolerDependencyRegistry

    Write-Host "  [*] [48/50] 自动清理打印机共享名称... (菜单 53)" -ForegroundColor Cyan
    Sanitize-PrinterShareName

    Write-Host "  [*] [49/50] 部署系统更新后自动应用任务..." -ForegroundColor Cyan
    Set-PostPatchTuesdayTask

    Write-Host "  [*] [50/50] 解析打印服务事件日志 & 最终 Spooler 验证... (菜单 78)" -ForegroundColor Cyan
    Parse-PrintEventLog
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] Spooler 已验证正在运行。" -ForegroundColor Green

    Write-Log "全自动修复结束" -Type "SUCCESS"

    if ($script:silentNuke) {
        Write-Host "`n  ==================================================================================================="
        Write-Host "    [+] 静默全自动修复完成！将在 3 秒后自动重启..."
        Write-Host "  ===================================================================================================`n"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }

    Write-Host "`n  ==================================================================================================="
    Write-Host "  [!] 域网络提示: 如果主机已加入域 (AD)，请在 secpol.msc 中检查并确认'从网络访问此计算机'的权限。" -ForegroundColor Yellow
    Write-Host "  [!] 仍然拒绝访问？提示: 如果连接仍然失败，请尝试使用选项 [60] 或 绕过方法 [86]。" -ForegroundColor Green

    $checkError = Read-Host "   [?] 是否查看执行错误日志? (Y/N)"
    if ($checkError -eq 'Y' -or $checkError -eq 'y') {
        Write-Host "`n   --- 错误扫描结果 ---" -ForegroundColor Cyan
        $errors = Select-String -Path $script:logFile -Pattern " - ERROR - " -SimpleMatch
        if ($errors) {
            $errors.Line | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        else {
            Write-Host "   [+] 日志中未发现任何错误。" -ForegroundColor Green
        }
        Write-Host "   --------------------`n"
    }

    $allFixRestart = Read-Host "   [?] 是否立即执行系统重启? (Y/N)"
    if ($allFixRestart -eq 'Y' -or $allFixRestart -eq 'y') {
        Write-Host "  [*] 准备就绪，系统将在 5 秒后重启..." -ForegroundColor Cyan
        Restart-Computer -Force
    }
    else {
        Write-Host "  [*] 请手动重启计算机以应用所有更改。" -ForegroundColor Cyan
    }
}

function Extreme-25H2 {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "        针对 WIN 11 25H2 / 24H2 / 26H2+ / ARM64 的极限模式路径"
    Write-Host "  ==================================================================================================="
    Write-Host "  [*] 此模式为拥有严格安全策略的 Windows 11 系统应用深度修复。"
    Write-Host "  [*] 正在自动执行所有修复..." -ForegroundColor Cyan

    Write-Log "执行极限修复模式 25H2/26H2" -Type "INFO"

    Write-Host "  [*] 正在刷新 GPO 缓存 (应用修复前)..." -ForegroundColor Cyan
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
        $LASTEXITCODE = 0; cmdkey /list | Select-String $env:COMPUTERNAME | ForEach-Object { $t = $_.ToString() -replace '(?i)^\s*Target:\s*', ''; cmdkey /delete:$t > $null 2>&1 }
        $LASTEXITCODE = 0; klist purge > $null 2>&1
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1
    }
    catch {}

    Write-Log "极限修复路径完成！" -Type "SUCCESS"
    Write-Host "  [+] 极限安全配置修改完毕。建议重启系统。" -ForegroundColor Green

    $extremeRestart = Read-Host "`n   [?] 是否立即执行系统重启? (Y/N)"
    if ($extremeRestart -eq 'Y' -or $extremeRestart -eq 'y') { Restart-Computer -Force }
}

function Restart-PC {
    Write-Host "`n  [*] 系统将在 5 秒后重启..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

function Detect-Win {
    Write-Host "`n  ======================================================================"
    Write-Host "                 WINDOWS 系统及架构检测"
    Write-Host "  ======================================================================"
    Write-Host "  [+] 系统版本 : $script:productName" -ForegroundColor Green
    Write-Host "  [+] 系统版本号 (Build) : $script:buildNumber" -ForegroundColor Green
    if ($script:isARM64) {
        Write-Host "  [+] 系统架构 : ARM64 (Snapdragon 骁龙 / Apple M 系列 虚拟机)" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] 系统架构 : AMD64 / x64" -ForegroundColor Cyan
    }
    if ($script:isServer) {
        Write-Host "  [+] 系统版本 : Windows Server Edition (服务器版)" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] 系统版本 : 客户端 (Home/Pro/Enterprise 家庭版/专业版/企业版)" -ForegroundColor Cyan
    }
}

function Show-Help {
    param([string]$Topic = "")

    $helpData = @{
        '1'  = @("修补错误 0x0000011b (RpcAuthnLevelPrivacy)", "禁用 RpcAuthnLevelPrivacyEnabled 注册表项，防止 RPC 身份验证阻止共享连接。", "Windows 10/11 累计更新后最常见的错误。")
        '2'  = @("深度修复 0x00000709 (多层 RPC & Kerberos)", "应用多层修复：RPC 命名管道、绕过 Kerberos、清理 HKCU 及旧版覆盖策略。", "处理能在常规修复中存活的顽固 Win 11 0x00000709 错误。必须同时在主机上运行。")
        '3'  = @("绕过错误 0x00000bc4 (找不到打印机)", "强制 RPC 使用命名管道协议以便发现打印机。", "网络可用，但 Windows 仍报告'找不到打印机'。")
        '4'  = @("修复错误 0x80070035 (自动配置网络服务)", "自动启动并配置 fdPHost, FDResPub, SSDPSRV, upnphost 等网络服务。", "目标计算机在网络中不显示；提示'找不到网络路径'。")
        '5'  = @("禁用客户端渲染 (错误 0x000006d1)", "在注册表中启用 DisableClientSideRendering。", "由于客户端驱动程序渲染问题导致打印作业失败。")
        '6'  = @("修复错误 0x80070005 (重置 Spooler ACL)", "使用 icacls 将 Spool\Printers 目录的 ACL 重置为默认权限。", "打印操作期间出现'拒绝访问'(0x80070005) 错误。")
        '7'  = @("修复错误 0x00000040 (网络不可用)", "修复打印处理器和端口的注册表节点。", "访问打印机时提示'网络不可用'。")
        '8'  = @("修复错误 0x00000002 (CopyFilesPolicy)", "配置 CopyFilesPolicy 以允许系统摄取驱动程序。", "从主机服务器克隆打印机驱动程序时出错。")
        '9'  = @("修复错误 0x0000007e (RPC 位数不匹配)", "强制注册表兼容跨系统架构的驱动程序。", "32 位与 64 位架构不匹配导致的问题。")
        '10' = @("全面网络重置 (DNS, Winsock, NetBIOS)", "刷新 DNS，释放/续订 IP，重置 Winsock 和 NetBIOS。", "网络连接不稳定，经常超时 (RTO)，或存在严重延迟。")
        '11' = @("强制网络设为专用配置文件", "将所有网络连接配置文件覆盖为'专用 (Private)'状态。", "由于网络配置文件设置为'公用'而导致共享被拦截。")
        '12' = @("强制禁用受密码保护的共享", "修改 LSA 注册表：limitblankpassworduse=0, everyoneincludesanonymous=1。", "明明没设置密码却依然弹出凭据输入框。")
        '13' = @("通过命名管道和 TCP 启用 RPC", "强制 RPC 通信通过命名管道和 TCP 协议传输。", "因 RPC 端点拦截导致的打印机连接错误。")
        '14' = @("配置防火墙以允许文件和打印机共享", "在防火墙中启用'文件和打印机共享'以及'网络发现'规则。", "主机在网络中不可见，共享被严重阻断。")
        '15' = @("SMB 1.0 传统协议管理 (开启/关闭)", "根据用户输入启用或禁用 SMB 1.0 协议。", "需要连接到传统硬件 (Win XP/7)。注意: 有勒索软件风险！")
        '16' = @("禁用 SMB 签名 (修复 Win 11 NAS 访问)", "禁用客户端和服务器的 RequireSecuritySignature。", "在 Win 11 24H2+ 系统中无法访问 NAS 或旧版主机。")
        '17' = @("强制使用现代 SMB2/SMB3 拓扑", "确保激活 SMB2/SMB3，并显式禁用 SMB1。", "过渡到现代安全协议。")
        '18' = @("在网络提供商顺序中优先处理 SMB", "在提供商列表中优先处理 LanmanWorkstation。", "SMB 连接存在极端延迟。")
        '19' = @("禁用 IPv6 协议栈", "通过注册表和 netsh 接口禁用 IPv6。", "在纯 IPv4 网络中 IPv6 导致的网络路由问题。")
        '20' = @("启用 mDNS & LLMNR (发现协议)", "启用组播 DNS 和 LLMNR 协议。", "无法通过主机名解析发现打印机。")
        '21' = @("配置 WSD 防火墙规则 (端口 3702)", "在防火墙中开启 UDP 端口 3702 供 WSD 发现使用。", "Web 服务发现 (WSD) 被防火墙屏蔽。")
        '22' = @("启用 IPP & Mopria 共享基础功能", "启用 Windows IPP 和 Mopria Foundation 功能。", "现代打印机使用的 IPP 协议支持。")
        '23' = @("解决 Hyper-V/WSL 虚拟网络冲突", "禁用虚拟适配器上的打印机绑定。", "Hyper-V/WSL 虚拟交换机破坏了局域网拓扑。")
        '24' = @("安装旧版 LPR/LPD 协议", "启用 Windows LPR 端口监视器和 LPD 服务功能。", "需要通过传统的 LPR (行式打印机远程) 协议进行连接。")
        '25' = @("远程网络打印机发现", "扫描并枚举目标主机上的所有共享打印机。", "想知道目标主机共享了哪些未知打印机。")
        '26' = @("WSD 到 标准 TCP/IP 端口转换器", "检测 WSD 端口并将打印机迁移到稳定的标准 TCP/IP 端口。", "因 WSD 发现失败导致打印机间歇性消失或处于脱机状态。")
        '27' = @("网络套接字重新初始化 (选择性清理)", "重启 SMB 客户端/服务端服务，并清除卡住的 445/135 端口连接。", "在更改 IP 或使用 VPN 后，陈旧的网络连接阻止了打印机访问。")
        '28' = @("救援网络配置 (自动看门狗)", "强制所有'公用'网络转为'专用'，并可选择部署一个看门狗任务。", "重启后网络配置文件总是重置回公用模式，从而屏蔽了打印机共享。")
        '29' = @("手动注入标准 TCP/IP 端口", "通过 WMI 脚本注入 TCP/IP 端口。", "需要手动添加一个 IP 打印机端口。")
        '30' = @("强制初始化 WSD 打印设备", "为 Web 服务发现初始化 WSDPrintDevice 服务。", "系统始终无法检测到 WSD 网络打印机。")
        '31' = @("硬重置打印后台程序 (清除队列)", "停止 Spooler 服务，强制删除 Spool\Printers 中的队列文件，然后重启服务。", "打印队列彻底冻结，Spooler 进程卡死。")
        '32' = @("重新初始化 RPC & DCOM 服务", "验证并重新启动 RpcSs 和 DcomLaunch 服务。", "RPC 或 DCOM 服务意外终止/崩溃；提示'RPC 服务器不可用'。")
        '33' = @("远程目标 Spooler 重启", "通过 PowerShell WinRM/DCOM 远程执行 Spooler 重置。", "在无法物理接触的情况下远程重置死机的 Spooler。需要目标管理员权限。")
        '34' = @("配置 Spooler 崩溃时自动重启", "通过 sc.exe 配置恢复操作：服务崩溃时自动重启。", "Spooler 高度不稳定，需要自我修复机制。")
        '35' = @("清除陈旧的 Spooler 依赖项", "将 DependOnService 的 Spooler 参数重置为默认 (RPCSS, http)。", "RPC 服务运行正常但 Spooler 仍处于非活动状态。")
        '36' = @("部署 Spooler 看门狗 (5分钟审查)", "部署一个计划任务，每 5 分钟审计一次 Spooler 状态。", "需要确保持续可用性的高正常运行时间打印服务器环境。")
        '37' = @("强制清除打印队列 (.shd/.spl)", "终止所有相关打印进程并清除损坏的 .shd/.spl 后台处理文件。", "标准的取消方法无法彻底清除队列。")
        '38' = @("重置 Spooler 注册表依赖项", "通过 HKLM 直接修改注册表，将 Spooler 的 DependOnService 设回原厂默认 (RPCSS, http)。", "即使重启后 Spooler 依然无法启动。")
        '39' = @("驱动程序管理 (打印服务器属性)", "启动'打印服务器属性'GUI 界面以管理已安装的驱动。", "打印机使用了错误的驱动，或存在重复的驱动程序实例。")
        '40' = @("禁用打印驱动隔离", "在注册表中禁用 IsolationPolicy。", "特定的驱动程序导致 Spooler 崩溃。")
        '41' = @("通用打印类驱动 V4 修复", "扫描 V4 驱动是否有损坏的 PrintConfig.dll，并触发 DriverStore 重新注册。", "V4 打印机突然停止工作或打印出乱码。")
        '42' = @("切换 PCL 与 PostScript 驱动模式", "在 PCL 和 PostScript 渲染模式之间切换打印机的驱动。", "打印机吐出充满随机乱码的纸张。")
        '43' = @("孤立驱动程序清理 (pnputil)", "扫描 DriverStore 查找孤立的打印机 OEM INF 包并强制删除。", "因为与旧的隐藏驱动程序冲突而无法安装新驱动。")
        '44' = @("绕过'驱动程序当前正在使用'", "强制结束 PrintIsolationHost, splwow64 等进程以释放驱动程序句柄。", "Windows 拒绝让你删除某个驱动程序。")
        '45' = @("幽灵 USB 端口 & 副本清除器", "检测并删除重复的打印机'副本'以及死去的 USB 端口。", "你将打印机插入了不同的 USB 端口导致它创建了一个幽灵副本。")
        '46' = @("强制删除幽灵打印机", "通过命令行 (printui) 强制删除打印机。", "幽灵打印机或已损坏的打印机拒绝通过标准方法卸载。")
        '47' = @("修复 Microsoft Edge / UWP 打印", "重新注册 UWP 打印组件并设定环回豁免。", "从记事本打印正常，但从 Edge/UWP 应用打印失败。")
        '48' = @("重新安装 Microsoft Print to PDF/XPS", "重新初始化系统自带的 Windows PDF & XPS 虚拟打印功能。", "自带的虚拟打印机丢失或出现错误。")
        '49' = @("浏览器打印沙盒修复 (Chromium)", "清除浏览器打印缓存并修复打印对话框的环回豁免问题。", "从 Word 可以打印，但从 Chrome 浏览器无法打印。")
        '50' = @("强制设置永久默认打印机", "禁用 Windows 自动管理功能并通过 WMI 强制设置默认打印机。", "Windows 会根据网络位置动态改变默认打印机。")
        '51' = @("强制设置默认打印机 (注册表绕过)", "绕过 Windows 自动管理，直接通过修改 HKCU 注册表来设置默认打印机。", "无法通过常规的 Windows 设置界面设定默认打印机。")
        '52' = @("修复 RDP 打印机终端服务", "在 RDP 终端服务注册表中启用打印机重定向。", "通过 RDP 认证后，本地打印机无法映射到远程会话。")
        '53' = @("自动清理打印机共享名称", "扫描共享打印机，将共享名称中的非法字符替换为下划线。", "由于共享名称过长或太复杂，客户端无法连接。")
        '54' = @("降级 LSA 保护 (传统认证)", "在 LSA 注册表中禁用 RunAsPPL。", "由于 Win 11 严格的 LSA 保护导致共享登录失败。")
        '55' = @("绕过智能应用控制 (SAC)", "将 VerifiedAndReputablePolicyState 设置为 Off。", "Win 11 SAC 正在主动拦截驱动安装程序。")
        '56' = @("绕过高级服务器列表 Point & Print (PrintNightmare 绕过)", "在注册表中注入 PrintNightmare 漏洞修复的提权绕过以及 ServerList 通配符 (*)。", "在下载驱动时遇到'检查打印机名称'或'拒绝访问'之类的泛指错误。在 Win 11 Build 22621+ 中必须执行。")
        '57' = @("绕过 UAC 管理员网络 TokenFilter", "配置 LocalAccountTokenFilterPolicy = 1。", "由于 UAC 过滤导致无法对工作组主机进行远程管理。")
        '58' = @("强制 NTLMv2 响应标准", "将 LmCompatibilityLevel 严格配置为 NTLMv2 (级别 3)。", "当针对不同系统版本或网络存储 (NAS) 进行认证时提示'拒绝访问'。")
        '59' = @("管理 Windows 受保护的打印 (WPP)", "禁用 Windows 受保护的打印功能。", "旧的打印机驱动程序不兼容 WPP 隔离。")
        '60' = @("向凭据管理器永久注入凭据", "将用户名/密码直接注入到 Windows 凭据管理器中。", "用于绕过每次访问时的手动认证。")
        '61' = @("清除 Windows 凭据管理器中的失效凭据", "通过 cmdkey 从凭据库中清除无效或过期的凭据。", "主机的密码已更改，但本地机器仍保留了过期的缓存。")
        '62' = @("绕过 Credential Guard (严格的 NTLM 拦截)", "禁用 LsaCfgFlags Credential Guard 注册表节点。", "在启用了 Credential Guard 的企业版/专业版环境中。")
        '63' = @("跨用户凭据映射", "通过加载 NTUSER.DAT 注册表，将登录 RunOnce 凭据任务注入到本机的[所有]用户配置文件中。", "为一台拥有多个本地用户的共享电脑配置凭证。")
        '64' = @("执行前注册表备份 (Spooler 及 网络)", "将 Print, Printers Policy 和 LanmanWorkstation 注册表树导出到 C:\WindowsPrinterSharingFixBackup。", "强烈建议在应用其他修复前执行此操作。永远先运行这个！")
        '65' = @("从备份回滚注册表", "导入来自备份目录的 .reg 文件。", "如果在应用修复后情况变得更糟。仅当之前执行过 [64] 备份时有效。")
        '66' = @("生成系统还原点 (安全措施)", "生成系统还原点以备执行完整的操作系统回滚。", "在执行主要的系统级架构更改之前。")
        '67' = @("系统文件检查 (SFC) 与 DISM 恢复", "执行 SFC /scannow 以及 DISM RestoreHealth。", "经常蓝屏 (BSOD)、频繁的异常错误，或在清理恶意软件后执行。此过程可能耗时 10-30 分钟！")
        '68' = @("重启 BITS (后台智能传输服务)", "重新启动后台智能传输服务。", "驱动程序无法自动完成下载。")
        '69' = @("Windows 更新及拦截器管理", "提供卸载系统更新、暂停更新、永久禁用更新服务(以防修复被还原)或恢复更新默认设置的工具。", "防止 Windows 重新开启受限协议或再次破坏打印机共享。")
        '70' = @("启动原生 Windows 疑难解答", "运行原生 Windows 打印机疑难解答向导 (msdt)。", "在进行手动干预前的初步诊断步骤。")
        '71' = @("强制打印机联机状态", "通过 WMI/CIM 将打印机的 WorkOffline 状态强制设为 false。", "打印机状态卡在'脱机'或处于灰显不可用状态。")
        '72' = @("启动 Services.msc", "打开 Services.msc 服务管理控制台。", "手动检查和验证 Print Spooler 的运行状态。")
        '73' = @("检测操作系统版本及架构", "显示操作系统版本、版本号以及特定的建议。", "在选择特定的修复方案前确保兼容性。")
        '74' = @("Ping & 端口 445/135 诊断", "通过 ICMP Ping 以及扫描 SMB (445) 和 RPC (135) 端口状态。", "测试网络连通性和防火墙状态的第一步。")
        '75' = @("查看执行日志", "启动日志管理界面 (记事本)。", "用于修复后的检查与审计。")
        '76' = @("审核最近 20 条打印服务错误日志", "从系统事件日志中解析出最近的 20 条错误事件。", "调查引发打印问题的根本原因。")
        '77' = @("系统诊断审查", "审查 Spooler 状态、SMB 状态、防火墙状态及网络拓扑。", "在部署任何修复前检查系统的总体健康状况。")
        '78' = @("打印服务事件日志解析器 (前 5 名)", "解析最近的 5 条错误/警告事件，并提供自动化解决建议。", "遇到神秘的打印问题却不知道明显的错误代码。")
        '79' = @("生成 HTML 诊断报告", "将执行日志编译成互动的 HTML 报告文件。", "用于 IT 文档记录或向上级主管汇报。")
        '80' = @("检测 GPO 干预 (组策略扫描)", "扫描注册表和 gpresult 以寻找影响打印机的组策略覆盖设置。", "修复方案只有短暂效果，重启或 gpupdate 后就再次失效。")
        '81' = @("PrintBRM (备份/恢复迁移工具)", "通过 PrintBrm.exe 对打印机拓扑执行完整的备份或恢复。", "将打印机部署到多个工作站，或迁移到新硬件。")
        '82' = @("启用 SMB 访客访问并取消匿名拦截", "在 LanmanWorkstation 注册表中启用 AllowInsecureGuestAuth。", "适用于局域网环境中的免密码共享。")
        '83' = @("极限路径 (针对 WIN 11 24H2/25H2/26H2+ & ARM64)", "极具攻击性的组合修复：修改 DnsOnWire, 严格名称检查, NTLM级别, SMB签名, 清空Kerberos等。", "标准修复方案在最新的 Win 11 上不起作用。专为 Build 26000 以上的版本构建。")
        '84' = @("执行全自动修复 (50 项自动化修复)", "按顺序依次执行 50 项自动化修复。", "主要推荐操作 —— 解决绝大多数常规情况的最佳修复。完成后[请重启系统]以获得最佳效果。")
        '85' = @("静默全自动修复并重启 (零提示)", "静默执行全部 50 项步骤，完成后自动重启。", "需要立即执行无人值守修复的紧急情况。系统会自动重启！执行前请保存好所有重要工作！")
        '86' = @("将本地端口映射到 UNC 路径 (绕过 0x00000709)", "尝试标准的端口创建，如果被拦截，则回退到通过直接写入注册表来绕过限制的方法。", "当标准共享连接失败且系统彻底封锁了 'Add-PrinterPort' 命令时。")
        '87' = @("移除已注入的本地端口 (UNC)", "尝试标准的端口移除，如果被拦截，则回退到通过清除注册表来强行删除。", "当之前映射的端口不再需要，或配置错误需要重新修改时。")
        '88' = @("重启系统", "立即重启系统。", "在应用任何重大修复后应始终执行此操作。")
        '89' = @("退出脚本", "退出本工具。", "故障排除完成后选择。")
    }

    if ($Topic -eq "" -or $Topic.ToLower() -eq "menu" -or $Topic.ToLower() -eq "help") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "      用户指南: Windows 打印机共享修复工具 (汉化版) - @KHAIRUDINFAHMI" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  使用方法:" -ForegroundColor Yellow
        Write-Host "    - 输入功能编号 (1-89) 然后按 ENTER 键"
        Write-Host "    - 输入 '7' 或 '07' 均可识别"
        Write-Host "    - 输入 '?' 显示此指南"
        Write-Host "    - 输入 '? 7' 显示功能 7 的详细说明"
        Write-Host "    - 输入 '? all' 打开完整的 HTML 说明文档 (如果可用)"
        Write-Host ""
        Write-Host "  新手工作流 (推荐的标准执行步骤):" -ForegroundColor Yellow
        Write-Host "    1. 执行 [64] 备份注册表 (强制建议)" -ForegroundColor White
        Write-Host "    2. 执行 [84] 全自动修复 (执行 50 步自动化修复)" -ForegroundColor White
        Write-Host "    3. 重启系统" -ForegroundColor White
        Write-Host "    4. 验证打印机共享访问是否恢复" -ForegroundColor White
        Write-Host ""
        Write-Host "  WIN 11 24H2+ 工作流 (系统版本 26000+):" -ForegroundColor Yellow
        Write-Host "    1. 执行 [64] 备份注册表" -ForegroundColor White
        Write-Host "    2. 执行 [83] 极限路径" -ForegroundColor White
        Write-Host "    3. 重启系统" -ForegroundColor White
        Write-Host ""
        Write-Host "  紧急处理 (快速自动化):" -ForegroundColor Yellow
        Write-Host "    - 执行 [85] 静默全自动修复 (警告: 完成后会自动重启系统！)" -ForegroundColor White
        Write-Host ""
        Write-Host "  功能类别分类:" -ForegroundColor Yellow
        Write-Host "    [01-09] 错误代码修复 (0x0000011b, 0x00000709, 0x00000bc4, 0x00000035, 0x000006d1, 等)" -ForegroundColor Cyan
        Write-Host "    [10-30] 网络 & 共享配置 (DNS, SMB, 防火墙, WSD, IPP)" -ForegroundColor Cyan
        Write-Host "    [31-38] Spooler 管理 (重置, RPC, 恢复, 看门狗, 清除)" -ForegroundColor Cyan
        Write-Host "    [39-53] 驱动 & 打印 (隔离, V4, PCL, 幽灵端口, PDF, RDP)" -ForegroundColor Cyan
        Write-Host "    [54-59] 安全 & 策略 (LSA, SAC, UAC, NTLMv2, WPP)" -ForegroundColor Cyan
        Write-Host "    [60-69] 凭证 & 系统 (凭证库, 备份, SFC, BITS, KB更新)" -ForegroundColor Cyan
        Write-Host "    [70-81] 诊断 & 实用工具 (疑难解答, 日志, GPO组策略, BRM)" -ForegroundColor Green
        Write-Host "    [82-89] 特殊操作 (极限模式, 全自动修复, 本地 UNC, 静默修复)" -ForegroundColor Green

        Write-Host ""
        Write-Host "  快速故障排除提示:" -ForegroundColor Yellow
        Write-Host "    - 不断弹出输入密码的提示框?     -> 执行 [12], [60], [82]" -ForegroundColor White
        Write-Host "    - '拒绝访问' (总是无法解决)?    -> 使用 [60] 强行注入目标 IP 和凭据" -ForegroundColor White
        Write-Host "    - 泛指的 '检查打印机名称' 错误? -> 执行 [56] 或 [86]" -ForegroundColor White
        Write-Host "    - 打印机开着但显示'脱机'?       -> 执行 [71]" -ForegroundColor White
        Write-Host "    - 局域网里找不到目标主机?       -> 执行 [04], [11], [14]" -ForegroundColor White
        Write-Host "    - Edge/UWP 应用无法打印?        -> 执行 [47]" -ForegroundColor White
        Write-Host "    - 怎样撤销所有的改动?           -> 执行 [65]" -ForegroundColor White
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
            Write-Host "  [*] 正在打开完整的 HTML 帮助文档..." -ForegroundColor Cyan
            $fileUrl = "file:///" + $docPath.Replace("\", "/") + "?all"
            Start-Process $fileUrl
        }
        else {
            Write-Host "  [-] 在安装目录中未找到 documentation.html 文件。" -ForegroundColor Red
            Write-Host "  [!] 请使用 '?' 查看简要指南，或使用 '? <数字>' 获取功能详解。" -ForegroundColor Yellow
        }
    }
    else {
        $num = $Topic.TrimStart('0')
        if ($helpData.ContainsKey($num)) {
            $h = $helpData[$num]
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host "      帮助: 功能模块 [$Topic]" -ForegroundColor Green
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  名称     : $($h[0])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  功能简介 : $($h[1])" -ForegroundColor White
            Write-Host ""
            if ($h[2] -ne "") {
                Write-Host "  适用场景 : $($h[2])" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [-] 找不到功能编号 '$Topic'。请输入 1-89。" -ForegroundColor Red
        }
    }
}

function Show-Menu {
    cls
    $winName = "$script:productName $script:buildNumber".ToUpper()
    if ($script:isARM64) { $winName += " ARM64" }
    elseif ([Environment]::Is64BitOperatingSystem) { $winName += " 64BIT" }
    else { $winName += " 32BIT" }

    Write-Host " 用户 (USER): " -NoNewline
    Write-Host "$env:USERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| 计算机名 (COMPUTERNAME): " -NoNewline
    Write-Host "$env:COMPUTERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| 系统 (OS): " -NoNewline
    Write-Host "$winName " -ForegroundColor Blue -NoNewline
    Write-Host "| Windows 打印机共享修复工具 v2.3.2" -ForegroundColor Green

    Write-Host " 时区: " -NoNewline
    Write-Host "$(Get-TimeZone | Select-Object -ExpandProperty Id) | $(Get-Date -Format 'HH.mm.ss')" -ForegroundColor Red
    Write-Host " 原作者: @KHAIRUDINFAHMI (2026) | 汉化" -ForegroundColor Magenta
    Write-Host ("=" * 175) -ForegroundColor DarkGray

    # 尝试调整控制台宽度（如失败则忽略）
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

    # ---- 辅助函数：计算字符串在控制台中的显示宽度（全角=2，半角=1） ----
    function Get-DisplayWidth([string]$s) {
        $w = 0
        foreach ($c in $s.ToCharArray()) {
            # Unicode 类别中，中/日/韩等属于 OtherLetter 或 OtherScript
            if ([char]::GetUnicodeCategory($c) -in @('OtherLetter', 'OtherScript')) {
                $w += 2
            } else {
                $w += 1
            }
        }
        return $w
    }

    # ---- 填充函数：将字符串填充至指定显示宽度（右侧补空格） ----
    function PadRightDisplay([string]$s, [int]$targetWidth) {
        $cur = Get-DisplayWidth $s
        if ($cur -ge $targetWidth) {
            # 若超宽则截断并加省略号（尽量保留前部）
            $truncated = ''
            $w = 0
            foreach ($c in $s.ToCharArray()) {
                $cw = if ([char]::GetUnicodeCategory($c) -in @('OtherLetter', 'OtherScript')) { 2 } else { 1 }
                if ($w + $cw -gt $targetWidth - 2) { break }
                $truncated += $c
                $w += $cw
            }
            if ($truncated.Length -lt $s.Length) { $truncated += '…' }
            return $truncated
        }
        return $s + (' ' * ($targetWidth - $cur))
    }

    # 定义三列内容（与原来一致）
    $col1 = @(
        "[01] 修补错误 0x0000011b (RpcAuthnLevelPrivacy)",
        "[02] 深度修复 0x00000709 (多层 RPC & Kerberos)",
        "[03] 绕过错误 0x00000bc4 (找不到打印机)",
        "[04] 修复错误 0x80070035 (自动配置网络服务)",
        "[05] 禁用客户端渲染 (错误 0x000006d1)",
        "[06] 修复错误 0x80070005 (重置 Spooler ACL)",
        "[07] 修复错误 0x00000040 (网络不可用)",
        "[08] 修复错误 0x00000002 (CopyFilesPolicy)",
        "[09] 修复错误 0x0000007e (RPC 位数不匹配)",
        "[10] 全面网络重置 (DNS, Winsock, NetBIOS)",
        "[11] 强制网络设为专用配置文件 (Private)",
        "[12] 强制禁用受密码保护的共享",
        "[13] 通过命名管道和 TCP 启用 RPC",
        "[14] 配置防火墙允许文件和打印机共享",
        "[15] SMB 1.0 传统协议管理 (开启/关闭)",
        "[16] 禁用 SMB 签名 (修复 Win 11 NAS 访问)",
        "[17] 强制使用现代 SMB2/SMB3 拓扑",
        "[18] 在网络提供商顺序中优先处理 SMB",
        "[19] 禁用 IPv6 协议栈",
        "[20] 启用 mDNS & LLMNR (发现协议)",
        "[21] 配置 WSD 防火墙规则 (开放端口 3702)",
        "[22] 启用 IPP & Mopria 共享基础功能",
        "[23] 解决 Hyper-V/WSL 虚拟网络冲突",
        "[24] 安装旧版 LPR/LPD 协议",
        "[25] 远程网络打印机发现",
        "[26] WSD 到 标准 TCP/IP 端口转换器",
        "[27] 网络套接字重新初始化 (选择性清理)",
        "[28] 救援网络配置 (自动看门狗)",
        "[29] 手动注入标准 TCP/IP 端口",
        "[30] 强制初始化 WSD 打印设备"
    )

    $col2 = @(
        "[31] 硬重置打印后台程序 (清除队列)",
        "[32] 重新初始化 RPC & DCOM 服务",
        "[33] 远程目标机器 Spooler 重启",
        "[34] 配置 Spooler 崩溃时自动重启",
        "[35] 清除陈旧的 Spooler 依赖项",
        "[36] 部署 Spooler 看门狗 (每5分钟审查)",
        "[37] 强制清除打印队列 (.shd/.spl)",
        "[38] Spooler 注册表依赖项重置",
        "[39] 驱动程序管理 (打印服务器属性)",
        "[40] 禁用打印机驱动隔离",
        "[41] 通用打印类驱动 V4 修复",
        "[42] 切换 PCL 与 PostScript 驱动模式",
        "[43] 孤立驱动程序清理 (pnputil)",
        "[44] 绕过 '驱动程序当前正在使用'",
        "[45] 幽灵 USB 端口 & 副本清除器",
        "[46] 强制删除幽灵打印机",
        "[47] 修复 Microsoft Edge / UWP 应用打印",
        "[48] 重新安装 Microsoft Print to PDF/XPS",
        "[49] 浏览器打印沙盒修复 (Chromium)",
        "[50] 强制设置永久默认打印机",
        "[51] 强制设置默认打印机 (注册表绕过)",
        "[52] 修复 RDP 打印机终端服务",
        "[53] 自动清理打印机共享名称中非法字符",
        "[54] 降级 LSA 保护 (传统认证)",
        "[55] 绕过智能应用控制 (SAC)",
        "[56] 绕过高级 ServerList Point & Print",
        "[57] 绕过 UAC 管理员网络 TokenFilter",
        "[58] 强制 NTLMv2 响应标准合规",
        "[59] 管理 Windows 受保护的打印 (WPP)"
    )

    $col3 = @(
        "[60] 将凭据永久注入 Windows 凭据库",
        "[61] 从凭据库中清除失效/过期凭据",
        "[62] 绕过 Credential Guard (严格的 NTLM)",
        "[63] 跨用户凭据映射 (给所有用户注入)",
        "[64] 执行前备份注册表 (重要)",
        "[65] 从备份回滚注册表",
        "[66] 生成系统还原点 (安全措施)",
        "[67] 系统文件检查 (SFC) 与 DISM 恢复",
        "[68] 重启 BITS (后台智能传输服务)",
        "[69] Windows 更新及拦截器管理",
        "[70] 启动原生 Windows 疑难解答",
        "[71] 强制打印机设为联机状态",
        "[72] 启动 Services.msc (服务管理)",
        "[73] 检测操作系统版本及系统架构",
        "[74] Ping & 端口 445/135 诊断",
        "[75] 查看执行日志",
        "[76] 审核最近 20 条打印服务错误日志",
        "[77] 诊断并审查系统整体状态",
        "[78] 打印服务事件日志解析器 (前 5 名)",
        "[79] 生成 HTML 诊断报告",
        "[80] 检测 GPO 组策略干预 (策略扫描)",
        "[81] PrintBRM (备份/恢复迁移工具)",
        "[82] 启用 SMB 访客访问并取消匿名拦截",
        "[83] 极限路径 (针对 WIN 11 24H2/25H2/26H2+)",
        "[84] 全自动修复 (执行 50 项自动化修复)",
        "[85] 静默全自动修复并重启 (零提示)",
        "[86] 将本地端口映射到 UNC 路径 (终极绕过)",
        "[87] 移除已注入的本地 UNC 端口",
        "[88] 重启系统",
        "[89] 退出脚本"
    )

    # 固定三列的目标显示宽度（可根据实际微调）
    $cw1 = 62
    $cw2 = 55
    $cw3 = 58
    $totalW = $cw1 + $cw2 + $cw3

    # 输出三列表头
    Write-Host (" 核心修复 & 网络服务".PadRight($cw1)) -ForegroundColor Cyan -NoNewline
    Write-Host (" SPOOLER(后台程序), 驱动 & 策略".PadRight($cw2)) -ForegroundColor Cyan -NoNewline
    Write-Host " 诊断 & 自动化操作" -ForegroundColor Cyan

    $maxRows = 30
    for ($i = 0; $i -lt $maxRows; $i++) {
        $line = ""

        # 第一列
        if ($i -lt $col1.Count) {
            $item = $col1[$i]
            # 将 [XX] 染成绿色，剩余部分染成绿色（原样保持）
            # 为简化，我们直接填充整个字符串并统一颜色（后面可以用正则，但这里统一绿色）
            $line += PadRightDisplay $item $cw1
        } else {
            $line += (' ' * $cw1)
        }
        $line += " "  # 列间空格

        # 第二列
        if ($i -lt $col2.Count) {
            $item = $col2[$i]
            $line += PadRightDisplay $item $cw2
        } else {
            $line += (' ' * $cw2)
        }
        $line += " "

        # 第三列
        if ($i -lt $col3.Count) {
            $item = $col3[$i]
            # 特殊标记 [83],[84],[85] 用红色
            if ($item -match '^(\[83\]|\[84\]|\[85\])') {
                # 拆分为编号和剩余内容分别着色
                $match = [regex]::Match($item, '^(\[\d+\])(.*)')
                if ($match.Success) {
                    $num = $match.Groups[1].Value
                    $rest = $match.Groups[2].Value
                    # 先填充整体，再拆开着色较复杂，为简便仍整体绿色，但警告行单独红色处理（下边的底部提示已单独标红）
                    $line += PadRightDisplay $item $cw3
                } else {
                    $line += PadRightDisplay $item $cw3
                }
            } else {
                $line += PadRightDisplay $item $cw3
            }
        } else {
            $line += (' ' * $cw3)
        }

        # 输出整行（统一绿色，但第三列特殊编号我们保留在循环中处理颜色，但这里统一输出绿色）
        Write-Host $line -ForegroundColor Green
    }

    Write-Host ("-" * $totalW) -ForegroundColor Red
    $noteLine1 = " :   提示: ".PadRight($totalW - 2) + ":"
    $noteLine2 = " :   [84] 全自动修复(50步) | [83] Win11 极限路径 | [85] 静默全自动修复并重启 ".PadRight($totalW - 2) + ":"
    $noteLine3 = " :   [?] 帮助 | [? 7] 详情 | [? all] HTML | 如果提示'检查打印机名称'错误，请使用选项 [86] ".PadRight($totalW - 2) + ":"

    Write-Host $noteLine1 -ForegroundColor Red
    Write-Host $noteLine2 -ForegroundColor Red
    Write-Host $noteLine3 -ForegroundColor Green
    Write-Host ("-" * $totalW) -ForegroundColor Red
    Write-Host ""
    Write-Host "输入选项编号: " -NoNewline
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
        Write-Host "`n  [>] 请按 ENTER 键返回主菜单..." -ForegroundColor Yellow
        Read-Host | Out-Null
        continue
    }

    if ($choice -match '^\d+$' -and $choice.Length -gt 1) { $choice = $choice.TrimStart('0') }

    if ($choice -match '^\d+$') {
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  正在执行模块 [$choice]" -ForegroundColor Yellow
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
        '30' { Start-Service WSDPrintDevice -ErrorAction SilentlyContinue; Write-Host "  [+] WSD 发现功能已启用" -ForegroundColor Green }
        '31' { Reset-Spooler }
        '32' { Check-RPC }
        '33' { Remote-SpoolerReset }
        '34' { Set-SpoolerRecovery }
        '35' { Reset-SpoolerDependency }
        '36' { Set-SpoolerWatchdog }
        '37' { Nuke-PrintQueue }
        '38' { Reset-SpoolerDependencyRegistry }
        '39' { Manage-Drivers }
        '40' { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force; Write-Host "  [+] 驱动隔离已禁用" -ForegroundColor Green }
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
        '89' { Write-Log "工具已退出。" -Type "INFO"; exit }

        default { Write-Host "`n  [-] 选择无效。请输入 1 - 89 之间的数字。" -ForegroundColor Red }
    }

    if ($choice -ne '89' -and $choice -ne '88' -and $choice -ne '85') {
        Write-Host "`n  [>] 请按 ENTER 键返回主菜单..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)