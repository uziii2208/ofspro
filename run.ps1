#Requires -Version 5.1
<#
.SYNOPSIS
    Offensive Security Gemini Proxy - Quick Start for AGY CLI (Windows)
.DESCRIPTION
    Starts the MITM proxy and optionally launches AGY through it.
    Supports Localhost Lure for target -> loopback rewriting.
.PARAMETER Level
    Bypass level: 0=Light, 1=Medium, 2=Strong, 3=Nuclear (default: 2)
.PARAMETER Target
    Target IP or domain to lure -> loopback (repeatable). Alias: -T
.PARAMETER LureAuto
    Auto-capture any non-loopback IP and lure it
.PARAMETER NoUnmap
    Don't map loopback back to real targets in responses
.PARAMETER Rewrite
    When to rewrite: auto | always | off (default: auto)
.PARAMETER Port
    Listen port (default: 8080)
.PARAMETER WithAgy
    Also launch AGY through the proxy
.PARAMETER Kill
    Kill running proxy processes
.PARAMETER Web
    Enable OFSPRO Web UI dashboard (enabled by default)
.PARAMETER NoWeb
    Disable OFSPRO Web UI dashboard
.PARAMETER WebPort
    Web UI port (default: 8081)
.PARAMETER NoClean
    Disable response cleaning
.PARAMETER NoRetry
    Disable auto-retry on blocks
.PARAMETER MaxRetries
    Max retry attempts (default: 3)
.NOTES
    Author: @uzii2208
.EXAMPLE
    .\run.ps1
    .\run.ps1 -Level 3
    .\run.ps1 -T 10.10.10.50 -T target.htb -Level 2
    .\run.ps1 -LureAuto -Level 3
    .\run.ps1 -Kill
#>

[CmdletBinding()]
param(
    [ValidateRange(0,3)]
    [int]$Level = 2,

    [Alias('T')]
    [string[]]$Target,

    [switch]$LureAuto,
    [switch]$NoUnmap,

    [ValidateSet('auto','always','off')]
    [string]$Rewrite = 'auto',

    [Alias('p')]
    [int]$Port = 8080,

    [switch]$WithAgy,
    [switch]$Kill,

    [Alias('w')]
    [switch]$Web,
    [switch]$NoWeb,
    [int]$WebPort = 8081,

    [switch]$NoClean,
    [switch]$NoRetry,
    [switch]$NoTools,
    [switch]$NoHistory,
    [switch]$NoContinuation,
    [int]$MaxRetries = 3,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AgyArgs
)

$ErrorActionPreference = 'Continue'

# -- Console UTF-8 & Virtual Terminal Initialization -----------------------
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertDir   = Join-Path $env:USERPROFILE '.mitmproxy'
$Cert      = Join-Path $CertDir 'mitmproxy-ca-cert.pem'
$Combined  = Join-Path $CertDir 'combined-ca-bundle.pem'

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

function Write-BoxRow {
    param(
        [string]$Label,
        [string]$Value,
        [ConsoleColor]$ValueColor = [ConsoleColor]::White,
        [ConsoleColor]$BorderColor = [ConsoleColor]::Magenta,
        [int]$LabelWidth = 16,
        [int]$TotalWidth = 59
    )
    $cleanVal = $Value -replace '\x1b\[[0-9;]*m',''
    $lblPad = ' ' * [Math]::Max(1, $LabelWidth - $Label.Length)
    $rem = [Math]::Max(0, $TotalWidth - ($Label.Length + $lblPad.Length + $cleanVal.Length))
    $endPad = ' ' * $rem
    Write-Host '  │  ' -ForegroundColor $BorderColor -NoNewline
    Write-Host "$Label$lblPad" -ForegroundColor White -NoNewline
    Write-Host $Value -ForegroundColor $ValueColor -NoNewline
    Write-Host "$endPad│" -ForegroundColor $BorderColor
}

function Stop-ProcessTree {
    param(
        [int]$ProcessId,
        [string]$ProcessName = ''
    )
    if ($ProcessId -le 0) { return }

    # Prefer taskkill /T /F on Windows for clean, forceful tree termination
    $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
    if ($taskkill) {
        & $taskkill.Source /PID $ProcessId /T /F 2>&1 | Out-Null
    } else {
        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                Stop-ProcessTree -ProcessId $child.ProcessId -ProcessName $child.Name
            }
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

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

function Find-Python {
    # 1. Existing PATH (skipping WindowsApps stubs)
    $pyCandidates = @(
        (Get-Command py -ErrorAction SilentlyContinue),
        (Get-Command python -ErrorAction SilentlyContinue),
        (Get-Command python3 -ErrorAction SilentlyContinue)
    )
    foreach ($cand in $pyCandidates) {
        if ($cand -and (Test-PythonBinary $cand.Source)) {
            $pyDir = Split-Path -Parent $cand.Source
            $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
            return $cand.Source
        }
    }

    # 2. Windows py launcher
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pyLauncher) {
        $pyPath = & $pyLauncher.Source -3 -c "import sys; print(sys.executable)" 2>$null
        if ($pyPath -and (Test-PythonBinary $pyPath.Trim())) {
            $pyDir = Split-Path -Parent $pyPath.Trim()
            $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
            return $pyPath.Trim()
        }
    }

    # 3. Search common Windows installation paths
    $searchPatterns = @(
        "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
        "$env:LOCALAPPDATA\Python\*\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-*\python.exe",
        "$env:ProgramFiles\Python*\python.exe",
        "${env:ProgramFiles(x86)}\Python*\python.exe",
        "$env:SystemDrive\Python*\python.exe",
        "$env:USERPROFILE\.local\bin\python.exe"
    )
    foreach ($pattern in $searchPatterns) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and (Test-PythonBinary $found.FullName)) {
            $pyDir = $found.DirectoryName
            $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
            return $found.FullName
        }
    }
    return $null
}

function Find-MitmDump {
    param([string]$PythonExe)

    $cmd = Get-Command mitmdump -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Query Python directly for its scripts path
    if ($PythonExe -and (Test-Path $PythonExe)) {
        try {
            $pyScripts = & $PythonExe -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null
            if ($pyScripts -and (Test-Path (Join-Path $pyScripts 'mitmdump.exe'))) {
                $env:Path = "$pyScripts;$env:Path"
                return (Join-Path $pyScripts 'mitmdump.exe')
            }
        } catch {}

        $pyDir = Split-Path -Parent $PythonExe
        $cand = Join-Path $pyDir 'Scripts\mitmdump.exe'
        if (Test-Path $cand) {
            $scriptsDir = Split-Path -Parent $cand
            $env:Path = "$scriptsDir;$env:Path"
            return $cand
        }
    }

    # Search common Windows paths
    $searchPaths = @(
        "$env:LOCALAPPDATA\Python\*\Scripts\mitmdump.exe",
        "$env:LOCALAPPDATA\Programs\Python\*\Scripts\mitmdump.exe",
        "$env:APPDATA\Python\*\Scripts\mitmdump.exe",
        "$env:LOCALAPPDATA\Python\bin\mitmdump.exe",
        "$env:USERPROFILE\.local\bin\mitmdump.exe"
    )
    foreach ($pattern in $searchPaths) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $env:Path = "$($found.DirectoryName);$env:Path"
            return $found.FullName
        }
    }
    return $null
}

function Show-Banner {
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
    Write-Host '⚡ OFFENSIVE SECURITY GEMINI PROXY · v1.2' -ForegroundColor Cyan -NoNewline
    Write-Host '               │' -ForegroundColor Magenta
    Write-Host '  │   ' -ForegroundColor Magenta -NoNewline
    Write-Host '🛡  Environmental Deception · Localhost Lure · AGY Core  ' -ForegroundColor DarkGray -NoNewline
    Write-Host '│' -ForegroundColor Magenta
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta
}

# ==========================================================================
# Kill mode
# ==========================================================================
if ($Kill) {
    Write-Host ''
    Write-Host '  ╭─ PROCESS TERMINATION ─────────────────────────────────────╮' -ForegroundColor Magenta
    Write-BoxLine '● Scanning for running proxy processes and port listeners...' Cyan Magenta
    
    $killed = 0
    $pidsToKill = [System.Collections.Generic.HashSet[int]]::new()

    # 1. Match proxy process signatures
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -match '^(mitmdump|mitmweb|python|python3)\.exe$') -and
            ($_.CommandLine -match 'gemini_rewriter|start_proxy|mitmdump|mitmweb')
        }
    if ($procs) {
        foreach ($p in $procs) {
            $null = $pidsToKill.Add($p.ProcessId)
        }
    }

    # 2. Check listeners on proxy port and web port
    $portsToCheck = @($Port)
    if ($Web -or $WebPort) { $portsToCheck += $WebPort }
    foreach ($chkPort in $portsToCheck) {
        $conns = Get-NetTCPConnection -LocalPort $chkPort -State Listen -ErrorAction SilentlyContinue
        if ($conns) {
            foreach ($c in $conns) {
                if ($c.OwningProcess -gt 4) {
                    $null = $pidsToKill.Add($c.OwningProcess)
                }
            }
        }
    }

    if ($pidsToKill.Count -gt 0) {
        foreach ($pidToKill in $pidsToKill) {
            try {
                $pName = (Get-Process -Id $pidToKill -ErrorAction SilentlyContinue).ProcessName
                Stop-ProcessTree -ProcessId $pidToKill -ProcessName $pName
                Write-BoxLine "✔ Stopped $pName (PID: $pidToKill) + process tree" Green Magenta
                $killed++
            } catch {}
        }
        Write-BoxLine "✔ Cleanly terminated $killed process tree(s)." Green Magenta
    } else {
        Write-BoxLine '● No active proxy processes or port listeners found.' DarkGray Magenta
    }
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta
    Write-Host ''
    exit 0
}

# ==========================================================================
# Detect Python runtime & mitmdump
# ==========================================================================
$pythonExe = Find-Python
if (-not $pythonExe) {
    Write-Fail 'Python 3.10+ is required but not found in PATH or standard installation folders.'
    Write-ItemLast 'Please install Python from python.org or ensure it is installed in AppData.'
    exit 1
}

$mitmdumpExe = Find-MitmDump -PythonExe $pythonExe

# ==========================================================================
# Check & kill stale proxy on same port
# ==========================================================================
$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Warn "Port $Port is in use -- clearing existing listener and child tree..."
    foreach ($conn in $portInUse) {
        if ($conn.OwningProcess -gt 4) {
            try {
                $pName = (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                Stop-ProcessTree -ProcessId $conn.OwningProcess -ProcessName $pName
                Write-Ok "Terminated stale listener $pName (PID: $($conn.OwningProcess))"
            } catch {}
        }
    }
    for ($i = 0; $i -lt 5; $i++) {
        Start-Sleep -Milliseconds 400
        $stillInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if (-not $stillInUse) { break }
    }
}

# ==========================================================================
# Ensure Root CA Certificate exists
# ==========================================================================
if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

if (-not (Test-Path $Cert)) {
    Write-Info 'CA certificate missing -- auto-generating...'
    $mitmBin = if ($mitmdumpExe) { $mitmdumpExe } else { 'mitmdump' }
    try {
        $proc = Start-Process -FilePath $mitmBin -ArgumentList '--listen-port','0','-q' -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        try { Stop-ProcessTree -ProcessId $proc.Id } catch {}
    } catch {
        Write-Warn "Ephemeral mitmdump execution error: $_"
    }
    if (Test-Path $Cert) {
        Write-Ok "Generated CA certificate: $Cert"
    } else {
        Write-Fail "Could not generate CA certificate. Please run .\setup.ps1 first."
        exit 1
    }
}

# ==========================================================================
# Ensure Combined CA Bundle exists
# ==========================================================================
if (-not (Test-Path $Combined) -or (Get-Item $Cert).LastWriteTime -gt (Get-Item $Combined -ErrorAction SilentlyContinue).LastWriteTime) {
    Write-Info 'Generating Go-compatible combined CA bundle...'
    $certifiBundle = $null
    if ($pythonExe) {
        try {
            $bundleOutput = & $pythonExe -c 'import certifi; print(certifi.where())' 2>$null
            if ($bundleOutput -and (Test-Path $bundleOutput.Trim())) {
                $certifiBundle = $bundleOutput.Trim()
            }
        } catch {}
    }
    if (-not $certifiBundle -and $pythonExe) {
        $searchCacerts = @(
            (Join-Path (Split-Path -Parent $pythonExe) 'Lib\site-packages\certifi\cacert.pem'),
            (Join-Path (Split-Path -Parent $pythonExe) '..\Lib\site-packages\certifi\cacert.pem'),
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
        $content = (Get-Content $certifiBundle -Raw).TrimEnd() + "`r`n" + (Get-Content $Cert -Raw).Trim()
        Set-Content -Path $Combined -Value $content -Encoding ASCII
    } else {
        Copy-Item $Cert $Combined -Force
    }
    Write-Ok "CA bundle ready: $Combined"
}

# ==========================================================================
# Build start_proxy.py arguments
# ==========================================================================
$pyArgs = @(
    (Join-Path $ScriptDir 'start_proxy.py'),
    '--port', $Port,
    '--level', $Level,
    '--rewrite', $Rewrite,
    '--max-retries', $MaxRetries
)
if ($NoClean)        { $pyArgs += '--no-clean' }
if ($NoRetry)        { $pyArgs += '--no-retry' }
if ($NoTools)        { $pyArgs += '--no-tools' }
if ($NoHistory)      { $pyArgs += '--no-history' }
if ($NoContinuation) { $pyArgs += '--no-continuation' }
if ($NoWeb)          { $pyArgs += '--no-web' }
else                 { $pyArgs += '--web-port'; $pyArgs += $WebPort }

# Check verbose from CmdletBinding
if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
    $pyArgs += '--verbose'
}
if ($Target) {
    foreach ($t in $Target) {
        $pyArgs += '-T'
        $pyArgs += $t
    }
}
if ($LureAuto) { $pyArgs += '--lure-auto' }
if ($NoUnmap)  { $pyArgs += '--no-unmap' }

# ==========================================================================
# Launch
# ==========================================================================
if ($WithAgy) {
    Show-Banner

    $levelNames  = @{ 0='Light'; 1='Medium'; 2='Strong'; 3='Nuclear ★' }
    $levelColors = @{ 0='DarkGray'; 1='Yellow'; 2='Cyan'; 3='Red' }

    Write-Host '  ╭─ LAUNCH CONFIGURATION ────────────────────────────────────╮' -ForegroundColor Magenta
    Write-BoxRow 'Mode:' 'Integrated AGY Launcher' Green Magenta
    Write-BoxRow 'Bypass Level:' "$Level ($($levelNames[$Level]))" $levelColors[$Level] Magenta
    Write-BoxRow 'Proxy Port:' "$Port" Cyan Magenta
    if ($Target) {
        Write-BoxRow 'Lure Targets:' "$($Target.Count) configured" Green Magenta
    }
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta
    Write-Host ''

    Write-Info "Starting background proxy on port $Port..."
    $proxyProc = Start-Process -FilePath $pythonExe -ArgumentList $pyArgs -PassThru -WindowStyle Hidden
    
    # Wait for proxy port to enter Listen state
    $isListening = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if ($proxyProc.HasExited) { break }
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $isListening = $true
            break
        }
    }

    if ($proxyProc.HasExited -or (-not $isListening)) {
        Write-Fail "Proxy daemon failed to start or bind to port $Port."
        try { Stop-ProcessTree -ProcessId $proxyProc.Id } catch {}
        exit 1
    }

    Write-Ok "Proxy active (PID: $($proxyProc.Id))"
    Write-Info 'Hooking AGY environment variables...'

    $env:HTTPS_PROXY = "http://127.0.0.1:$Port"
    $env:HTTP_PROXY  = "http://127.0.0.1:$Port"
    $env:https_proxy = "http://127.0.0.1:$Port"
    $env:http_proxy  = "http://127.0.0.1:$Port"
    $env:SSL_CERT_FILE = $Combined
    $env:AGY_CLI_DISABLE_SAFETY_FILTERING = 'true'

    Write-Host ''
    Write-Host '  ╭───────────────────────────────────────────────────────────╮' -ForegroundColor Green
    Write-BoxLine '✔ AGY CLI CONNECTED THROUGH PROXY — COMMENCING SESSION' Green Green
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Green
    Write-Host ''

    try {
        if ($AgyArgs -and $AgyArgs.Count -gt 0) {
            & agy @AgyArgs
        } else {
            & agy
        }
    } catch {
        Write-Fail "Error invoking AGY CLI: $_"
    }

    Write-Host ''
    Write-Warn 'AGY session terminated. Shutting down proxy daemon...'
    try { Stop-ProcessTree -ProcessId $proxyProc.Id } catch {}

    # Clear any residual listener on port
    $lingering = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($lingering) {
        foreach ($conn in $lingering) {
            if ($conn.OwningProcess -gt 4) {
                try { Stop-ProcessTree -ProcessId $conn.OwningProcess } catch {}
            }
        }
    }
    Write-Ok 'Proxy stopped cleanly. Session ended.'
    Write-Host ''
} else {
    # ── Proxy-only mode -- run in foreground ───────────────────
    $pyVer = & $pythonExe --version 2>&1
    Write-Host ''
    Write-Host '  ╭─ PREFLIGHT READY ─────────────────────────────────────────╮' -ForegroundColor Cyan
    Write-BoxRow '✔ Runtime:' "$pyVer" White Cyan
    Write-BoxRow '✔ Port:' "$Port (Ready)" Cyan Cyan
    Write-BoxRow '✔ Certificate:' "$Cert" DarkGray Cyan
    Write-BoxRow '✔ Bundle:' "$Combined" DarkGray Cyan
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Cyan
    Write-Host ''

    # start_proxy.py takes over foreground, displays banner and live stream
    try {
        & $pythonExe @pyArgs
    } catch [System.Management.Automation.Host.HostException] {
        # Catch Ctrl+C cleanly
        Write-Host ''
        Write-Ok 'Proxy stopped.'
    }
}
