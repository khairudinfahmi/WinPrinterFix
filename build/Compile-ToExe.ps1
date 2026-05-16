$ProjectRoot = Split-Path $PSScriptRoot -Parent

$SourceFile = Join-Path $ProjectRoot "src\WinPrinterFix.ps1"
$OutputDir  = Join-Path $ProjectRoot "release"
$OutputFile = Join-Path $OutputDir "WinPrinterFix.exe"
$IconFile   = Join-Path $ProjectRoot "assets\icon.ico"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $SourceFile)) {
    Write-Host "[ERROR] Source file not found: $SourceFile" -ForegroundColor Red
    Write-Host "Ensure the script is executed from within the WinPrinterFix project directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "Verifying PS2EXE module..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "PS2EXE module not installed. Installing..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
}

Write-Host "PS2EXE module found." -ForegroundColor Green
Write-Host "Compiling $SourceFile to $OutputFile..." -ForegroundColor Cyan

$ps2exeParams = @{
    inputFile   = $SourceFile
    outputFile  = $OutputFile
    requireAdmin = $true
    title       = "Windows Printer Sharing Fix"
    description = "Windows Printer Sharing Fix Tool"
    version     = "2.2.8.0"
    company     = "khairudinfahmi"
    copyright   = "2026 khairudinfahmi"
}

if (Test-Path $IconFile) {
    $ps2exeParams.iconFile = $IconFile
}

try {
    Invoke-ps2exe @ps2exeParams
    
    Write-Host "`nCompilation Successful!" -ForegroundColor Green
    Write-Host "EXE file generated at: $OutputFile" -ForegroundColor Cyan
    
    $docSource = Join-Path $ProjectRoot "docs\documentation.html"
    $docDest = Join-Path $OutputDir "documentation.html"
    if (Test-Path $docSource) {
        Copy-Item $docSource $docDest -Force
        Write-Host "Documentation bundled: $docDest" -ForegroundColor Green
    }
    
    Write-Host "Starting Code Signing..." -ForegroundColor Magenta
    $certName = "khairudinfahmi"
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -match $certName | Select-Object -First 1
    
    if (-not $cert) {
        Write-Host "Code Signing certificate '$certName' not found. Generating new certificate..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Subject "CN=$certName" -Type CodeSigningCert -CertStoreLocation "Cert:\CurrentUser\My"
        Write-Host "New certificate generated." -ForegroundColor Green
    }
    
    $cerExportPath = Join-Path $ProjectRoot "assets\khairudinfahmi_cert.cer"
    Export-Certificate -Cert $cert -FilePath $cerExportPath -Force | Out-Null
    Write-Host "Certificate file exported to: $cerExportPath" -ForegroundColor Cyan
    
    Write-Host "Injecting digital signature into $OutputFile..." -ForegroundColor Cyan
    $sig = Set-AuthenticodeSignature -FilePath $OutputFile -Certificate $cert -TimestampServer "http://timestamp.sectigo.com"
    
    if ($sig.Status -eq "Valid" -or $sig.Status -eq "UnknownError") {
        Write-Host "Signature injected! (Status: $($sig.Status))" -ForegroundColor Green
    } else {
        Write-Host "Signing failed: $($sig.StatusMessage)" -ForegroundColor Red
    }

} catch {
    Write-Host "Process Failed: $_" -ForegroundColor Red
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")


