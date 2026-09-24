@echo off
REM AGY through the security proxy -- Author: @uzii2208

set "SCRIPT_DIR=%~dp0"
set "PORT=8080"

rem Resolve CA certificate bundle dynamically
if exist "%USERPROFILE%\.mitmproxy\combined-ca-bundle.pem" (
    set "SSL_CERT_FILE=%USERPROFILE%\.mitmproxy\combined-ca-bundle.pem"
) else if exist "%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem" (
    set "SSL_CERT_FILE=%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem"
)

set "HTTPS_PROXY=http://127.0.0.1:%PORT%"
set "https_proxy=http://127.0.0.1:%PORT%"
set "HTTP_PROXY=http://127.0.0.1:%PORT%"
set "http_proxy=http://127.0.0.1:%PORT%"
set "AGY_CLI_DISABLE_SAFETY_FILTERING=true"

rem Check if proxy daemon is actively listening on port 8080
netstat -ano -p tcp | findstr /R /C:":%PORT% " | findstr /I "LISTENING" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [*] Proxy not detected on 127.0.0.1:%PORT%. Auto-starting background daemon...
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT_DIR%run.ps1','-Port','%PORT%') -WindowStyle Hidden"
    
    rem Wait up to 10 seconds (20 x 500ms) for the proxy to initialize
    powershell -NoProfile -Command "$p=%PORT%; for($i=0;$i -lt 20;$i++){ if(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue){ exit 0 }; try { $c=New-Object System.Net.Sockets.TcpClient; $a=$c.BeginConnect('127.0.0.1',$p,$null,$null); if($a.AsyncWaitHandle.WaitOne(200,$false)){ $c.EndConnect($a); $c.Close(); exit 0 }; $c.Close() } catch {}; Start-Sleep -Milliseconds 500 }; exit 1"
    if errorlevel 1 (
        echo   [!] Proxy daemon did not respond on port %PORT% within 10s.
        echo   [!] Run '.\run.ps1' in a separate terminal to view diagnostics.
        echo.
    ) else (
        echo   [+] Proxy daemon active on 127.0.0.1:%PORT%.
    )
)

agy %*
