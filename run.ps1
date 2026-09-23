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
    Enable mitmproxy web UI
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
    [int]$WebPort = 8081,

    [switch]$NoClean,
    [switch]$NoRetry,
    [switch]$NoTools,
    [switch]$NoHistory,
    [switch]$NoContinuation,
    [int]$MaxRetries = 3
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
    Write-BoxLine '● Scanning for running proxy processes...' Cyan Magenta
    
    $killed = 0
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -match '^(mitmdump|mitmweb|python|python3)\.exe$') -and
            ($_.CommandLine -match 'gemini_rewriter|start_proxy')
        }

    if ($procs) {
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                Write-BoxLine "✔ Stopped $($p.Name) (PID: $($p.ProcessId))" Green Magenta
                $killed++
            } catch {}
        }
        Write-BoxLine "✔ Cleanly terminated $killed process(es)." Green Magenta
    } else {
        Write-BoxLine '● No active proxy processes found.' DarkGray Magenta
    }
    Write-Host '  ╰───────────────────────────────────────────────────────────╯' -ForegroundColor Magenta
    Write-Host ''
    exit 0
}

# ==========================================================================
# Detect Python runtime
# ==========================================================================
$pythonCmd = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pythonCmd) {
    Write-Fail 'Python 3.10+ is required but not found in PATH.'
    exit 1
}
$pythonExe = $pythonCmd.Source

# ==========================================================================
# Check & kill stale proxy on same port
# ==========================================================================
$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Warn "Port $Port is in use — clearing existing listener..."
    foreach ($conn in $portInUse) {
        try {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            Write-Ok "Terminated stale listener (PID: $($conn.OwningProcess))"
        } catch {}
    }
    Start-Sleep -Seconds 1
}

# ==========================================================================
# Ensure Root CA Certificate exists
# ==========================================================================
if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

if (-not (Test-Path $Cert)) {
    Write-Info 'CA certificate missing — auto-generating...'
    try {
        $proc = Start-Process -FilePath 'mitmdump' -ArgumentList '--listen-port','0','-q' -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    } catch {}
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
    try { $certifiBundle = (& $pythonExe -c "import certifi; print(certifi.where())" 2>$null) } catch {}
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
if ($Web)            { $pyArgs += '--web'; $pyArgs += '--web-port'; $pyArgs += $WebPort }

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
    Start-Sleep -Seconds 2

    if ($proxyProc.HasExited) {
        Write-Fail "Proxy daemon failed to start. Verify port $Port is available."
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

    try { & agy } catch {}

    Write-Host ''
    Write-Warn 'AGY session terminated. Shutting down proxy daemon...'
    try { $proxyProc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    Write-Ok 'Proxy stopped cleanly. Session ended.'
    Write-Host ''
} else {
    # ── Proxy-only mode — run in foreground ───────────────────
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
