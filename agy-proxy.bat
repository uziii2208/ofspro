@echo off
REM AGY through the security proxy -- Author: @uzii2208
set HTTPS_PROXY=http://127.0.0.1:8080
set https_proxy=http://127.0.0.1:8080
set HTTP_PROXY=http://127.0.0.1:8080
set http_proxy=http://127.0.0.1:8080
set "SSL_CERT_FILE=C:\Users\mrsha\.mitmproxy\combined-ca-bundle.pem"
set AGY_CLI_DISABLE_SAFETY_FILTERING=true
agy %*
