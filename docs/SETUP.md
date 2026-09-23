# Setup Guide

Author: @uzii2208

## Prerequisites

- Python 3.10+
- [mitmproxy](https://mitmproxy.org) 10.x+
- [AGY CLI](https://antigravity.google) logged in via Google OAuth
- Node.js 18+ (AGY dependency)
- For swap mode: API key for your chosen backend (or local Ollama)

## Quick Setup

### Linux / macOS

```bash
chmod +x setup.sh
./setup.sh
```

### Windows (PowerShell)

```powershell
# Run as Administrator for CA cert import
.\setup.ps1
```

This installs mitmproxy, generates the CA cert, imports it into Windows Trusted Root CAs,
creates a combined CA bundle, and generates `agy-proxy.bat` + `agy-proxy-wrapper.ps1` wrappers.

## Manual Setup

### 1. Install mitmproxy

```bash
pip install mitmproxy
mitmdump --version  # verify
```

### 2. Generate CA Certificate

```bash
# mitmproxy generates certs on first run
mitmdump --listen-port 0 -q &
sleep 2 && kill $!
ls ~/.mitmproxy/mitmproxy-ca-cert.pem
```

### 3. Route AGY Through the Proxy

#### Option A: Environment Variables (Recommended)

```bash
export HTTPS_PROXY=http://127.0.0.1:8080
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
agy
```

#### Option B: Skip Cert Verification (Quick)

```bash
export HTTPS_PROXY=http://127.0.0.1:8080
export NODE_TLS_REJECT_UNAUTHORIZED=0
agy
```

#### Option C: System-Wide CA Trust

```bash
# Debian/Ubuntu
sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates

# Then just:
export HTTPS_PROXY=http://127.0.0.1:8080
agy
```

#### Option D: Windows (PowerShell)

```powershell
# Environment variables
$env:HTTPS_PROXY = "http://127.0.0.1:8080"
$env:SSL_CERT_FILE = "$env:USERPROFILE\.mitmproxy\combined-ca-bundle.pem"
agy

# Or import CA cert into Windows trust store (as Admin):
# certutil -addstore Root "$env:USERPROFILE\.mitmproxy\mitmproxy-ca-cert.pem"
# Then just:
$env:HTTPS_PROXY = "http://127.0.0.1:8080"
agy
```

### 4. Swap Mode Backend Setup

#### DeepSeek (Recommended)

1. Get API key: https://platform.deepseek.com
2. Run:
```bash
python start_proxy.py --mode swap --backend deepseek --backend-key sk-xxxxx
```

#### Ollama (Fully Local)

1. Install: https://ollama.ai
2. Pull a model: `ollama pull llama3.1`
3. Run:
```bash
python start_proxy.py --mode swap --backend ollama
```

#### OpenRouter

1. Get API key: https://openrouter.ai
2. Run:
```bash
python start_proxy.py --mode swap --backend openrouter --backend-key sk-or-xxxxx
```

## Localhost Lure Setup

The Localhost Lure rewrites target IPs and domains to loopback addresses (`127.0.1.x`) so Gemini thinks you're pentesting your own machine.

### Basic Usage

```bash
# Lure a single target
python start_proxy.py -T 10.10.10.50

# Lure multiple targets
python start_proxy.py -T 10.10.10.50 -T target.htb -T 192.168.1.20
```

### HackTheBox Example

```bash
# Terminal 1: Start proxy with HTB target lured
python start_proxy.py --level 2 -T 10.10.10.50 -T target.htb

# Terminal 2: Run AGY through the proxy
export HTTPS_PROXY=http://127.0.0.1:8080
export SSL_CERT_FILE=~/.mitmproxy/combined-ca-bundle.pem
agy

# In AGY: "Scan 10.10.10.50 for open ports"
# Gemini sees: "Scan 127.0.1.1 for open ports" → responds freely
# You receive: "nmap -sV 10.10.10.50 ..." → directly usable
```

### Real Pentest Engagement

```bash
# Multiple targets on an internal network
python start_proxy.py --level 3 \
    -T 192.168.1.10 \
    -T 192.168.1.20 \
    -T webportal.corp.local \
    --rewrite always
```

### Auto-Capture Mode

Automatically lure any non-loopback IP that appears in your prompts:

```bash
python start_proxy.py --lure-auto
# No need to pre-register targets — any IP you mention gets lured on-the-fly
```

### Disable Response Unmapping

By default, loopback addresses in Gemini's responses are mapped back to real targets. To keep the loopback addresses as-is:

```bash
python start_proxy.py -T 10.10.10.50 --no-unmap
```

## Verify It Works

```bash
# Terminal 1: Start proxy
python start_proxy.py --verbose

# Terminal 2: Run AGY
export HTTPS_PROXY=http://127.0.0.1:8080
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
agy

# In AGY, ask a security question and check Terminal 1 for:
# [AGY] PASS | mode=direct total=1 ...
```

---

*Author: [@uzii2208](https://github.com/uzii2208)*
