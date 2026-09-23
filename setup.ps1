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
# ==========================================================================
# Helpers: Python & mitmproxy Discovery Engine
# ==========================================================================
function Test-PythonBinary {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $false }
    if ($Path -like '*\WindowsApps\*') {
        $item = Get-Item $Path -ErrorAction SilentlyContinue
        if (-not $item -or $item.Length -eq 0) { return $false }
    }
    try {
        $ver = & $Path --version 2>&1
        if ($LASTEXITCODE -eq 0 -and "$ver" -match 'Python 3\.') {
            return $true
        }
    } catch {}
    return $false
}

function Find-PythonAndMitm {
    $result = @{
        PythonExe  = $null
        PythonDir  = $null
        ScriptsDir = $null
        MitmDump   = $null
        Version    = $null
    }

    # 1. Active mitmdump in PATH
    $mitmCmd = Get-Command mitmdump -ErrorAction SilentlyContinue
    if ($mitmCmd) {
        $result.MitmDump   = $mitmCmd.Source
        $result.ScriptsDir = Split-Path -Parent $mitmCmd.Source
    }

    # 2. Check active Python in PATH (skipping broken WindowsApps stubs)
    $pyCandidates = @(
        (Get-Command py -ErrorAction SilentlyContinue),
        (Get-Command python -ErrorAction SilentlyContinue),
        (Get-Command python3 -ErrorAction SilentlyContinue)
    )
    foreach ($cand in $pyCandidates) {
        if ($cand -and (Test-PythonBinary $cand.Source)) {
            $result.PythonExe = $cand.Source
            $result.PythonDir = Split-Path -Parent $cand.Source
            break
        }
    }

    # 3. Check 'py -3' launcher if pythonExe not resolved yet
    if (-not $result.PythonExe) {
        $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
        if ($pyLauncher) {
            try {
                $pyPath = & py -3 -c "import sys; print(sys.executable)" 2>$null
                if ($pyPath -and (Test-PythonBinary $pyPath.Trim())) {
                    $result.PythonExe = $pyPath.Trim()
                    $result.PythonDir = Split-Path -Parent $result.PythonExe
                }
            } catch {}
        }
    }

    # 4. Search standard Windows installation locations for python.exe
    if (-not $result.PythonExe) {
        $searchDirs = @(
            "$env:LOCALAPPDATA\Python\*\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\*\python.exe",
            "$env:APPDATA\Python\*\python.exe",
            "C:\Python3*\python.exe",
            "C:\Program Files\Python3*\python.exe"
        )
        foreach ($pattern in $searchDirs) {
            $foundPy = Get-Item $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($foundPy -and (Test-PythonBinary $foundPy.FullName)) {
                $result.PythonExe = $foundPy.FullName
                $result.PythonDir = $foundPy.DirectoryName
                break
            }
        }
    }

    # 5. Check Scripts folder next to resolved python
    if ($result.PythonExe -and -not $result.MitmDump) {
        $tryScripts = Join-Path $result.PythonDir 'Scripts'
        $tryMitm = Join-Path $tryScripts 'mitmdump.exe'
        if (Test-Path $tryMitm) {
            $result.MitmDump   = $tryMitm
            $result.ScriptsDir = $tryScripts
        }
    }

    # 6. Search standard Windows installation locations for mitmdump.exe
    if (-not $result.MitmDump) {
        $searchMitm = @(
            "$env:LOCALAPPDATA\Python\*\Scripts\mitmdump.exe",
            "$env:LOCALAPPDATA\Programs\Python\*\Scripts\mitmdump.exe",
            "$env:APPDATA\Python\*\Scripts\mitmdump.exe",
            "$env:USERPROFILE\.local\bin\mitmdump.exe"
        )
        foreach ($p in $searchMitm) {
            $foundMitm = Get-Item $p -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($foundMitm) {
                $result.MitmDump   = $foundMitm.FullName
                $result.ScriptsDir = $foundMitm.DirectoryName
                if (-not $result.PythonExe) {
                    $candPy = Join-Path $foundMitm.Directory.Parent.FullName 'python.exe'
                    if (Test-PythonBinary $candPy) {
                        $result.PythonExe = $candPy
                        $result.PythonDir = $foundMitm.Directory.Parent.FullName
                    }
                }
                break
            }
        }
    }

    if (-not $result.ScriptsDir -and $result.PythonDir) {
        $result.ScriptsDir = Join-Path $result.PythonDir 'Scripts'
    }

    # Update process-level PATH
    $newPaths = @()
    if ($result.ScriptsDir -and (Test-Path $result.ScriptsDir) -and ($env:Path -notlike "*$($result.ScriptsDir)*")) {
        $newPaths += $result.ScriptsDir
    }
    if ($result.PythonDir -and (Test-Path $result.PythonDir) -and ($env:Path -notlike "*$($result.PythonDir)*")) {
        $newPaths += $result.PythonDir
    }
    if ($newPaths.Count -gt 0) {
        $env:Path = ($newPaths -join ';') + ';' + $env:Path
    }

    if ($result.PythonExe) {
        try {
            $result.Version = (& $result.PythonExe --version 2>&1 | Select-Object -First 1)
        } catch {}
    }

    return $result
}

# ==========================================================================
# Step 1: mitmproxy
# ==========================================================================
Write-StepHeader 1 'MITMPROXY CORE ENGINE'

$pyInfo = Find-PythonAndMitm

if (-not $pyInfo.PythonExe) {
    Write-Fail 'Python 3.10+ is required but not found in PATH or standard directories.'
    Write-ItemLast 'Install Python 3.10+ from https://python.org and rerun setup.'
    Write-StepFooter
    exit 1
}

if (-not $pyInfo.MitmDump) {
    Write-Info 'mitmproxy not found in PATH — installing via pip...'
    & $pyInfo.PythonExe -m pip install --upgrade mitmproxy certifi 2>&1 | Out-Null
    $pyInfo = Find-PythonAndMitm
}

if ($pyInfo.MitmDump) {
    $ver = & $pyInfo.MitmDump --version 2>&1 | Select-Object -First 1
    Write-Ok "Detected existing installation: $ver"
    Write-Item "Binary: $($pyInfo.MitmDump)"
    Write-ItemLast "Runtime: $($pyInfo.PythonExe)"

    # Persist to User PATH environment variable if missing
    try {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $toAdd = @($pyInfo.PythonDir, $pyInfo.ScriptsDir) | Where-Object { $_ -and (Test-Path $_) -and $userPath -notlike "*$_*" }
        if ($toAdd.Count -gt 0) {
            $newUserPath = ($toAdd + $userPath) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            Write-Ok 'Added Python & Scripts directories to User PATH'
        }
    } catch {}
} else {
    Write-Fail 'mitmproxy installation completed, but binary not found in standard paths.'
    Write-ItemLast 'Install manually: pip install mitmproxy'
    Write-StepFooter
    exit 1
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
        $proc = Start-Process -FilePath $pyInfo.MitmDump -ArgumentList '--listen-port','0','-q' -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-Path $Cert) { break }
        }
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

$imported = $false

if ($isAdmin) {
    Write-Info 'Running as Administrator — importing CA into LocalMachine\Root...'
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
            Write-Warn "LocalMachine import failed: $_"
            Write-ItemLast "Run manually: certutil -addstore -f Root `"$Cert`""
        }
    }
} else {
    Write-Info 'Running as Standard User — importing CA into CurrentUser\Root...'
    $certutilCmd = Get-Command certutil -ErrorAction SilentlyContinue
    if ($certutilCmd) {
        $res = & certutil -user -addstore -f Root $Cert 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'Imported into CurrentUser\Root via certutil'
            Write-ItemLast 'Certificate is now trusted for current user'
            $imported = $true
        }
    }

    if (-not $imported) {
        try {
            $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Cert)
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
            $store.Open('ReadWrite')
            $store.Add($certObj)
            $store.Close()
            Write-Ok 'Imported into CurrentUser\Root via .NET X509Store'
            Write-ItemLast 'Certificate is now trusted for current user'
            $imported = $true
        } catch {
            Write-Warn "CurrentUser import failed: $_"
            Write-ItemLast "For system-wide trust, run in an Admin terminal: certutil -addstore -f Root `"$Cert`""
        }
    }
}
Write-StepFooter

# ==========================================================================
# Step 4: Combined CA Bundle
# ==========================================================================
Write-StepHeader 4 'COMBINED CA BUNDLE (GO TLS STACK)'

$certifiBundle = $null
if ($pyInfo.PythonExe) {
    try {
        $bundlePath = & $pyInfo.PythonExe -c "import certifi; print(certifi.where())" 2>$null
        if ($bundlePath -and (Test-Path $bundlePath.Trim())) {
            $certifiBundle = $bundlePath.Trim()
        }
    } catch {}
}

if (-not $certifiBundle -and $pyInfo.PythonDir) {
    $searchCacerts = @(
        (Join-Path $pyInfo.PythonDir 'Lib\site-packages\certifi\cacert.pem'),
        (Join-Path $pyInfo.ScriptsDir '..\Lib\site-packages\certifi\cacert.pem'),
        "$env:LOCALAPPDATA\Python\*\Lib\site-packages\certifi\cacert.pem",
        "$env:APPDATA\Python\*\site-packages\certifi\cacert.pem"
    )
    foreach ($p in $searchCacerts) {
        $foundCacert = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundCacert) {
            $certifiBundle = $foundCacert.FullName
            break
        }
    }
}

if ($certifiBundle -and (Test-Path $certifiBundle)) {
    $bundleContent = Get-Content $certifiBundle -Raw
    $mitmContent   = Get-Content $Cert -Raw
    [System.IO.File]::WriteAllText($Combined, ($bundleContent.TrimEnd() + "`r`n" + $mitmContent.Trim() + "`r`n"), [System.Text.Encoding]::ASCII)
    Write-Ok 'Built bundle from Python certifi + mitmproxy CA'
    Write-Item "Source: $certifiBundle"
} else {
    Copy-Item $Cert $Combined -Force
    Write-Ok 'Created standalone bundle (mitmproxy CA only)'
    Write-Item 'Notice: For full public CA validation, install certifi: pip install certifi'
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
    '',
    'set "SCRIPT_DIR=%~dp0"',
    'set "PORT=8080"',
    '',
    'rem Resolve CA certificate bundle dynamically',
    'if exist "%USERPROFILE%\.mitmproxy\combined-ca-bundle.pem" (',
    '    set "SSL_CERT_FILE=%USERPROFILE%\.mitmproxy\combined-ca-bundle.pem"',
    ') else if exist "%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem" (',
    '    set "SSL_CERT_FILE=%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem"',
    ')',
    '',
    'set "HTTPS_PROXY=http://127.0.0.1:%PORT%"',
    'set "https_proxy=http://127.0.0.1:%PORT%"',
    'set "HTTP_PROXY=http://127.0.0.1:%PORT%"',
    'set "http_proxy=http://127.0.0.1:%PORT%"',
    'set "AGY_CLI_DISABLE_SAFETY_FILTERING=true"',
    '',
    'rem Check if proxy daemon is actively listening on port 8080',
    'netstat -ano -p tcp | findstr /R /C:":%PORT% " | findstr /I "LISTENING" >nul 2>&1',
    'if %ERRORLEVEL% NEQ 0 (',
    '    echo   [●] Proxy not detected on 127.0.0.1:%PORT%. Auto-starting background daemon...',
    '    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell -ArgumentList ''-ExecutionPolicy Bypass -NoProfile -File \"\"%SCRIPT_DIR%run.ps1\"\" -Port %PORT%'' -WindowStyle Hidden"',
    '    powershell -NoProfile -Command "$p=%PORT%; for($i=0;$i -lt 20;$i++){ if(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue){ exit 0 }; Start-Sleep -Milliseconds 500 }; exit 1"',
    '    if errorlevel 1 (',
    '        echo   [▲] Proxy daemon did not respond on port %PORT% within 10s.',
    '        echo   [▲] Run ''.\run.ps1'' in a separate terminal to view diagnostics.',
    '        echo.',
    '    ) else (',
    '        echo   [✔] Proxy daemon active on 127.0.0.1:%PORT%.',
    '    )',
    ')',
    '',
    'agy %*'
)
[System.IO.File]::WriteAllText($batWrapper, (($batLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
Write-Ok 'Created portable batch wrapper (with auto-daemon check)'
Write-Item "File: $batWrapper"

$ps1Wrapper = Join-Path $ScriptDir 'agy-proxy-wrapper.ps1'
$ps1Lines = @(
    '# AGY through the security proxy -- Author: @uzii2208',
    '[CmdletBinding()]',
    'param(',
    '    [Parameter(ValueFromRemainingArguments = $true)]',
    '    [string[]]$AgyArgs',
    ')',
    '',
    '$Port = 8080',
    '$CertBundle = Join-Path $env:USERPROFILE ''.mitmproxy\combined-ca-bundle.pem''',
    '',
    'function Test-ProxyPort {',
    '    param([int]$p = 8080)',
    '    try {',
    '        $tcp = New-Object System.Net.Sockets.TcpClient',
    '        $iar = $tcp.BeginConnect(''127.0.0.1'', $p, $null, $null)',
    '        if ($iar.AsyncWaitHandle.WaitOne(600, $false)) {',
    '            $tcp.EndConnect($iar)',
    '            $tcp.Close()',
    '            return $true',
    '        }',
    '        $tcp.Close()',
    '        return $false',
    '    } catch {',
    '        return $false',
    '    }',
    '}',
    '',
    'if (-not (Test-ProxyPort $Port)) {',
    '    Write-Host ''  ▲ [!] OFSPRO proxy daemon is not running on 127.0.0.1:'' -NoNewline -ForegroundColor Yellow',
    '    Write-Host $Port -ForegroundColor Cyan',
    '    Write-Host ''  ● Auto-starting OFSPRO background proxy daemon...'' -ForegroundColor Cyan',
    '    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path',
    '    $runScript = Join-Path $ScriptDir ''run.ps1''',
    '    if (Test-Path $runScript) {',
    '        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`" -Port $Port -Level 3" -WindowStyle Hidden',
    '        $started = $false',
    '        for ($i = 0; $i -lt 8; $i++) {',
    '            Start-Sleep -Milliseconds 500',
    '            if (Test-ProxyPort $Port) {',
    '                $started = $true',
    '                break',
    '            }',
    '        }',
    '        if ($started) {',
    '            Write-Host "  ✔ Proxy daemon online and listening on 127.0.0.1:$Port" -ForegroundColor Green',
    '        } else {',
    '            Write-Host ''  ▲ Auto-start pending. If connection fails, launch in another terminal:'' -ForegroundColor Yellow',
    '            Write-Host ''     .\run.ps1 -Level 3'' -ForegroundColor White',
    '        }',
    '    }',
    '}',
    '',
    '$env:HTTPS_PROXY = "http://127.0.0.1:$Port"',
    '$env:https_proxy = "http://127.0.0.1:$Port"',
    '$env:HTTP_PROXY  = "http://127.0.0.1:$Port"',
    '$env:http_proxy  = "http://127.0.0.1:$Port"',
    '$env:SSL_CERT_FILE = $CertBundle',
    '$env:AGY_CLI_DISABLE_SAFETY_FILTERING = ''true''',
    '',
    '& agy @AgyArgs'
)
[System.IO.File]::WriteAllText($ps1Wrapper, (($ps1Lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::UTF8)
Write-Ok 'Created PowerShell wrapper (with auto-daemon check)'
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
