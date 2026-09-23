# AGY through the security proxy -- Author: @uzii2208
$env:HTTPS_PROXY = 'http://127.0.0.1:8080'
$env:https_proxy = 'http://127.0.0.1:8080'
$env:HTTP_PROXY  = 'http://127.0.0.1:8080'
$env:http_proxy  = 'http://127.0.0.1:8080'
$env:SSL_CERT_FILE = 'C:\Users\mrsha\.mitmproxy\combined-ca-bundle.pem'
$env:AGY_CLI_DISABLE_SAFETY_FILTERING = 'true'
& agy @args
