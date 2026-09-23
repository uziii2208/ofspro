#Requires -Version 5.1
<#
.SYNOPSIS
    Offensive Security Gemini Proxy - Windows Setup
.DESCRIPTION
    Installs mitmproxy, generates CA certificate, imports into Windows
    trust store, creates combined CA bundle, and creates AGY wrapper.
.NOTES
    Author: @uzii2208
    Run as Administrator for CA certificate import.
#>

param()

$ErrorActionPreference = 'Continue'

# -- Console UTF-8 & Virtual Terminal Initialization -----------------------
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# -- Paths -----------------------------------------------------------------
$CertDir   = Join-Path $env:USERPROFILE '.mitmproxy'
$Cert      = Join-Path $CertDir 'mitmproxy-ca-cert.pem'
$Combined  = Join-Path $CertDir 'combined-ca-bundle.pem'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# -- UI Helpers ------------------------------------------------------------
function Write-Ok       { param([string]$Msg) Write-Host '  ✔ ' -ForegroundColor Green  -NoNewline; Write-Host $Msg -ForegroundColor White }
function Write-Info     { param([string]$Msg) Write-Host '  ● ' -ForegroundColor Cyan   -NoNewline; Write-Host $Msg -ForegroundColor Gray }
function Write-Warn     { param([string]$Msg) Write-Host '  ▲ ' -ForegroundColor Yellow -NoNewline; Write-Host $Msg -ForegroundColor Yellow }
function Write-Fail     { param([string]$Msg) Write-Host '  ✖ ' -ForegroundColor Red    -NoNewline; Write-Host $Msg -ForegroundColor Red }
function Write-Item     { param([string]$Msg) Write-Host '     ├─ ' -ForegroundColor DarkGray -NoNewline; Write-Host $Msg }
function Write-ItemLast { param([string]$Msg) Write-Host '     ╰─ ' -ForegroundColor DarkGray -NoNewline; Write-Host $Msg }

function Write-BoxLine {
    param(
        [string]$Content,
        [ConsoleColor]$ContentColor = [ConsoleColor]::White,
        [ConsoleColor]$BorderColor = [ConsoleColor]::Magenta,
        [int]$InnerWidth = 59
    )
    $clean = $Content -replace '\x1b\[[0-9;]*m',''
    $padCount = [Math]::Max(0, $InnerWidth - $clean.Length)
    $pad = ' ' * $padCount
    Write-Host '  │  ' -ForegroundColor $BorderColor -NoNewline
    Write-Host $Content -ForegroundColor $ContentColor -NoNewline
    Write-Host ($pad + '│') -ForegroundColor $BorderColor
}


function Write-StepHeader {
    param([int]$Step, [string]$Title)
    $bar = '───────────────────────────────────────────────────────────'
    $rem = [Math]::Max(1, 49 - $Title.Length)
    $subBar = $bar.Substring(0, [Math]::Min($rem, $bar.Length))
    Write-Host ''
    Write-Host '  ╭─ ' -ForegroundColor Magenta -NoNewline
    Write-Host "[$Step/5] " -ForegroundColor White -NoNewline
    Write-Host $Title -ForegroundColor Cyan -NoNewline
    Write-Host " $subBar╮" -ForegroundColor Magenta
}

function Write-StepFooter {
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta
}

# -- Banner -----------------------------------------------------------------
Write-Host ''
Write-Host '  ╭───────────────────────────────────────────────────────────╮' -ForegroundColor Magenta
Write-Host '  │   ██████╗ ███████╗███████╗  ██████╗ ██████╗  ██████╗      │' -ForegroundColor Magenta
Write-Host '  │  ██╔═══██╗██╔════╝██╔════╝  ██╔══██╗██╔══██╗██╔═══██╗     │' -ForegroundColor Magenta
Write-Host '  │  ██║   ██║█████╗  ███████╗  ██████╔╝██████╔╝██║   ██║     │' -ForegroundColor Magenta
Write-Host '  │  ██║   ██║██╔══╝  ╚════██║  ██╔═══╝ ██╔══██╗██║   ██║     │' -ForegroundColor Magenta
Write-Host '  │  ╚██████╔╝██║     ███████║  ██║     ██║  ██║╚██████╔╝     │' -ForegroundColor Magenta
Write-Host '  │   ╚═════╝ ╚═╝     ╚══════╝  ╚═╝     ╚═╝  ╚═╝ ╚═════╝      │' -ForegroundColor Magenta
Write-Host '  │                                                           │' -ForegroundColor Magenta
Write-Host '  │   ' -ForegroundColor Magenta -NoNewline
Write-Host '⚡ OFFENSIVE SECURITY GEMINI PROXY · SETUP (WINDOWS)' -ForegroundColor Cyan -NoNewline
Write-Host '   │' -ForegroundColor Magenta
Write-Host '  │   ' -ForegroundColor Magenta -NoNewline
Write-Host '🛡  Environmental Deception · Localhost Lure · AGY      ' -ForegroundColor DarkGray -NoNewline
Write-Host '│' -ForegroundColor Magenta
Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta

# ==========================================================================
# Step 1: mitmproxy
# ==========================================================================
Write-StepHeader 1 'MITMPROXY CORE ENGINE'

function Find-MitmDump {
    $cmd = Get-Command mitmdump -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }

    # Query Python directly for its scripts path
    $pythonCmd = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonCmd) {
        $pyScripts = & $pythonCmd.Source -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null
        if ($pyScripts -and (Test-Path (Join-Path $pyScripts 'mitmdump.exe'))) {
            $env:Path = "$pyScripts;$env:Path"
            return (Get-Command mitmdump -ErrorAction SilentlyContinue)
        }
    }

    # Search common Windows paths
    $searchPaths = @(
        "$env:LOCALAPPDATA\Python\*\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\*\Scripts",
        "$env:APPDATA\Python\*\Scripts",
        "$env:LOCALAPPDATA\Python\bin",
        "$env:USERPROFILE\.local\bin"
    )
    foreach ($pattern in $searchPaths) {
        $found = Get-Item (Join-Path $pattern 'mitmdump.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $env:Path = "$($found.DirectoryName);$env:Path"
            return (Get-Command mitmdump -ErrorAction SilentlyContinue)
        }
    }
    return $null
}

$mitmdump = Find-MitmDump
if ($mitmdump) {
    $ver = & $mitmdump.Source --version 2>&1 | Select-Object -First 1
    Write-Ok "Detected existing installation: $ver"
    Write-ItemLast "Path: $($mitmdump.Source)"
} else {
    Write-Info 'mitmproxy not found in PATH — installing via pip...'
    $pipCmd = Get-Command pip, pip3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pipCmd) {
        & $pipCmd.Source install mitmproxy 2>&1 | Out-Null
    } else {
        $python = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($python) {
            & $python.Source -m pip install mitmproxy 2>&1 | Out-Null
        } else {
            Write-Fail 'Python not found in PATH. Please install Python 3.10+ and rerun setup.'
            Write-StepFooter
            exit 1
        }
    }

    $mitmdump = Find-MitmDump
    if ($mitmdump) {
        $ver = & $mitmdump.Source --version 2>&1 | Select-Object -First 1
        Write-Ok "mitmproxy installed successfully: $ver"
        Write-ItemLast "Binary: $($mitmdump.Source)"
    } else {
        Write-Fail 'mitmproxy installation completed, but binary not found in standard paths.'
        Write-ItemLast 'Install manually: pip install mitmproxy'
        Write-StepFooter
        exit 1
    }
}
Write-StepFooter

# ==========================================================================
# Step 2: CA Certificate
# ==========================================================================
Write-StepHeader 2 'CA ROOT CERTIFICATE'

if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

if (Test-Path $Cert) {
    $certSize = (Get-Item $Cert).Length
    Write-Ok 'CA certificate already exists'
    Write-Item "File: $Cert"
    Write-ItemLast "Size: $certSize bytes"
} else {
    Write-Info 'Generating fresh mitmproxy root CA certificate...'
    try {
        $mitmBin = if ($mitmdump) { $mitmdump.Source } else { 'mitmdump' }
        $proc = Start-Process -FilePath $mitmBin -ArgumentList '--listen-port','0','-q' -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    } catch {
        Write-Warn "Ephemeral process error: $_"
    }

    if (Test-Path $Cert) {
        Write-Ok 'Generated root CA successfully'
        Write-ItemLast "Saved to: $Cert"
    } else {
        Write-Fail 'Failed to generate CA certificate.'
        Write-ItemLast 'Run manually: mitmdump -q and terminate after 2 seconds'
        Write-StepFooter
        exit 1
    }
}
Write-StepFooter

# ==========================================================================
# Step 3: Windows Trust Store
# ==========================================================================
Write-StepHeader 3 'WINDOWS CERTIFICATE STORE'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if ($isAdmin) {
    Write-Info 'Running as Administrator — importing CA into Trusted Root CAs...'
    $imported = $false

    $certutilCmd = Get-Command certutil -ErrorAction SilentlyContinue
    if ($certutilCmd) {
        $res = & certutil -addstore -f Root $Cert 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'Imported into LocalMachine\Root via certutil'
            Write-ItemLast 'Certificate is now trusted system-wide'
            $imported = $true
        }
    }

    if (-not $imported) {
        try {
            $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Cert)
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
            $store.Open('ReadWrite')
            $store.Add($certObj)
            $store.Close()
            Write-Ok 'Imported into LocalMachine\Root via .NET X509Store'
            Write-ItemLast 'Certificate is now trusted system-wide'
            $imported = $true
        } catch {
            Write-Warn "System import failed: $_"
            Write-ItemLast "Run manually: certutil -addstore -f Root `"$Cert`""
        }
    }
} else {
    Write-Warn 'Current shell does NOT have Administrator privileges'
    Write-Item 'Windows trust store auto-import skipped.'
    Write-Item 'To trust the proxy CA certificate across Windows, run in an Admin terminal:'
    Write-ItemLast "certutil -addstore -f Root `"$Cert`""
}
Write-StepFooter

# ==========================================================================
# Step 4: Combined CA Bundle
# ==========================================================================
Write-StepHeader 4 'COMBINED CA BUNDLE (GO TLS STACK)'

$certifiBundle = $null
try {
    $pythonCmd = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonCmd) {
        $certifiBundle = & $pythonCmd.Source -c "import certifi; print(certifi.where())" 2>$null
    }
} catch {}

if ($certifiBundle -and (Test-Path $certifiBundle)) {
    $bundleContent = Get-Content $certifiBundle -Raw
    $mitmContent   = Get-Content $Cert -Raw
    Set-Content -Path $Combined -Value ($bundleContent.TrimEnd() + "`r`n" + $mitmContent.Trim()) -Encoding ASCII
    Write-Ok 'Built bundle from Python certifi + mitmproxy CA'
    Write-Item "Source: $certifiBundle"
} else {
    Copy-Item $Cert $Combined -Force
    Write-Ok 'Created standalone bundle (mitmproxy CA only)'
}
Write-ItemLast "Output bundle: $Combined"
Write-StepFooter

# ==========================================================================
# Step 5: AGY Wrapper Scripts
# ==========================================================================
Write-StepHeader 5 'AGY INTERCEPTION WRAPPERS'

$batWrapper = Join-Path $ScriptDir 'agy-proxy.bat'
$batLines = @(
    '@echo off',
    'REM AGY through the security proxy -- Author: @uzii2208',
    'set HTTPS_PROXY=http://127.0.0.1:8080',
    'set https_proxy=http://127.0.0.1:8080',
    'set HTTP_PROXY=http://127.0.0.1:8080',
    'set http_proxy=http://127.0.0.1:8080',
    "set `"SSL_CERT_FILE=$Combined`"",
    'set AGY_CLI_DISABLE_SAFETY_FILTERING=true',
    'agy %*'
)
$batLines -join "`r`n" | Set-Content -Path $batWrapper -Encoding ASCII
Write-Ok 'Created batch wrapper'
Write-Item "File: $batWrapper"

$ps1Wrapper = Join-Path $ScriptDir 'agy-proxy-wrapper.ps1'
$ps1Lines = @(
    '# AGY through the security proxy -- Author: @uzii2208',
    "`$env:HTTPS_PROXY = 'http://127.0.0.1:8080'",
    "`$env:https_proxy = 'http://127.0.0.1:8080'",
    "`$env:HTTP_PROXY  = 'http://127.0.0.1:8080'",
    "`$env:http_proxy  = 'http://127.0.0.1:8080'",
    "`$env:SSL_CERT_FILE = '$Combined'",
    "`$env:AGY_CLI_DISABLE_SAFETY_FILTERING = 'true'",
    '& agy @args'
)
$ps1Lines -join "`r`n" | Set-Content -Path $ps1Wrapper -Encoding UTF8
Write-Ok 'Created PowerShell wrapper'
Write-ItemLast "File: $ps1Wrapper"
Write-StepFooter

# ==========================================================================
# Done Dashboard
# ==========================================================================
Write-Host ''
Write-Host '  ╭───────────────────────────────────────────────────────────╮' -ForegroundColor Green
Write-Host '  │  ' -ForegroundColor Green -NoNewline
Write-Host '✔ SETUP COMPLETE — SYSTEM READY FOR OPERATION' -ForegroundColor Green -NoNewline
Write-Host '            │' -ForegroundColor Green
Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Green
Write-Host ''
Write-Host '  ╭─ WORKFLOW GUIDE ──────────────────────────────────────────╮' -ForegroundColor Magenta
Write-BoxLine 'MODE 1: Basic Proxy Interception (Nuclear Level 3)' Cyan
Write-BoxLine 'Terminal 1:  .\run.ps1 -Level 3' Yellow
Write-BoxLine 'Terminal 2:  .\agy-proxy.bat' Green
Write-BoxLine ''
Write-BoxLine 'MODE 2: Localhost Lure (Target -> 127.0.1.x)' Cyan
Write-BoxLine 'Terminal 1:  .\run.ps1 -T 10.10.10.50 -Level 3' Yellow
Write-BoxLine 'Terminal 2:  .\agy-proxy.bat' Green
Write-BoxLine ''
Write-BoxLine 'MODE 3: Multi-Target Lure (CTF / Red Team Lab)' Cyan
Write-BoxLine 'Terminal 1:  .\run.ps1 -T 10.10.10.50 -T target.htb -l 3' Yellow
Write-BoxLine 'Terminal 2:  .\agy-proxy.bat' Green
Write-BoxLine ''
Write-BoxLine 'MODE 4: Auto-Capture Dynamic External IPs' Cyan
Write-BoxLine 'Terminal 1:  .\run.ps1 -LureAuto -Level 3' Yellow
Write-BoxLine 'Terminal 2:  .\agy-proxy.bat' Green
Write-BoxLine ''
Write-BoxLine 'Note: AGY requires SSL_CERT_FILE set to CA bundle.' DarkGray
Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta

Write-Host ''
