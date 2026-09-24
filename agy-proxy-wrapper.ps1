# AGY through the security proxy -- Author: @uzii2208
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AgyArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = 8080

# Dynamic CA Certificate resolution (no hardcoded user paths)
$CertDir  = Join-Path $env:USERPROFILE '.mitmproxy'
$Combined = Join-Path $CertDir 'combined-ca-bundle.pem'
$Cert     = Join-Path $CertDir 'mitmproxy-ca-cert.pem'

if (Test-Path $Combined) {
    $env:SSL_CERT_FILE = $Combined
} elseif (Test-Path $Cert) {
    $env:SSL_CERT_FILE = $Cert
} else {
    Write-Host "  ▲ Warning: MITM CA certificate not found in $CertDir" -ForegroundColor Yellow
}

$env:HTTPS_PROXY = "http://127.0.0.1:$Port"
$env:https_proxy = "http://127.0.0.1:$Port"
$env:HTTP_PROXY  = "http://127.0.0.1:$Port"
$env:http_proxy  = "http://127.0.0.1:$Port"
$env:AGY_CLI_DISABLE_SAFETY_FILTERING = 'true'

function Test-ProxyListening {
    param([int]$CheckPort = 8080)
    $conn = Get-NetTCPConnection -LocalPort $CheckPort -State Listen -ErrorAction SilentlyContinue
    if ($conn) { return $true }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect('127.0.0.1', $CheckPort, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(400, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            $tcp.Close()
            return $true
        }
        $tcp.Close()
    } catch {}
    return $false
}

# Auto-start proxy if not running
if (-not (Test-ProxyListening -CheckPort $Port)) {
    Write-Host "  ● Proxy not detected on 127.0.0.1:$Port. Auto-starting background daemon..." -ForegroundColor Cyan
    $runPs1 = Join-Path $ScriptDir 'run.ps1'
    if (Test-Path $runPs1) {
        $startArgs = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-WindowStyle', 'Hidden', '-File', $runPs1, '-Port', $Port)
        Start-Process -FilePath 'powershell.exe' -ArgumentList $startArgs -WindowStyle Hidden
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-ProxyListening -CheckPort $Port) {
                $ready = $true
                break
            }
        }
        if ($ready) {
            Write-Host "  ✔ Proxy daemon active on 127.0.0.1:$Port." -ForegroundColor Green
        } else {
            Write-Host "  ▲ Proxy daemon did not respond on port $Port within 10s." -ForegroundColor Yellow
            Write-Host "  ▲ Run '.\run.ps1' in a separate terminal to view diagnostics." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ▲ run.ps1 not found at $runPs1. Please start proxy manually." -ForegroundColor Yellow
    }
}

try {
    if ($AgyArgs -and $AgyArgs.Count -gt 0) {
        & agy @AgyArgs
    } else {
        & agy
    }
} catch {
    Write-Host "  ✖ Failed to execute 'agy': $_" -ForegroundColor Red
}
