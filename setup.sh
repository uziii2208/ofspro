#!/bin/bash
# Offensive Security Gemini Proxy — Setup
# Author: @uzii2208
set -e

# Ensure ~/.local/bin is in PATH early for user-level pip installs
export PATH="${HOME}/.local/bin:${PATH}"

# ── ANSI 256 / TrueColor Palette ─────────────────────────────
if [ -t 1 ]; then
    M='\033[38;5;141m'  # Cyber Violet / Purple
    C='\033[38;5;51m'   # Neon Cyan
    G='\033[38;5;48m'   # Emerald Green
    Y='\033[38;5;214m'  # Amber Gold
    R='\033[38;5;196m'  # Bright Red
    W='\033[1;37m'      # Bold White
    D='\033[38;5;242m'  # Slate Gray / Dim
    B='\033[1m'         # Bold
    N='\033[0m'         # Reset
else
    M='' C='' G='' Y='' R='' W='' D='' B='' N=''
fi

CERT_DIR="${HOME}/.mitmproxy"
CERT="${CERT_DIR}/mitmproxy-ca-cert.pem"
COMBINED="${CERT_DIR}/combined-ca-bundle.pem"

# ── UI Helpers ───────────────────────────────────────────────
ok()        { echo -e "  ${G}✔${N} $*"; }
info()      { echo -e "  ${C}●${N} $*"; }
warn()      { echo -e "  ${Y}▲${N} $*"; }
fail()      { echo -e "  ${R}✖${N} $*"; }
item()      { echo -e "     ${D}├─${N} $*"; }
item_last() { echo -e "     ${D}╰─${N} $*"; }

step_header() {
    local num="$1"
    local title="$2"
    local bar="───────────────────────────────────────────────────────────"
    local rem=$(( 49 - ${#title} ))
    [ $rem -lt 1 ] && rem=1
    echo ""
    echo -e "  ${M}╭─${N} ${W}[${num}/5]${N} ${C}${B}${title}${N} ${M}${bar:0:$rem}╮${N}"
}

step_footer() {
    echo -e "  ${M}╰───────────────────────────────────────────────────────────╯${N}"
}

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${M}"
cat << 'BANNER'
  ╭───────────────────────────────────────────────────────────╮
  │   ██████╗ ███████╗███████╗  ██████╗ ██████╗  ██████╗      │
  │  ██╔═══██╗██╔════╝██╔════╝  ██╔══██╗██╔══██╗██╔═══██╗     │
  │  ██║   ██║█████╗  ███████╗  ██████╔╝██████╔╝██║   ██║     │
  │  ██║   ██║██╔══╝  ╚════██║  ██╔═══╝ ██╔══██╗██║   ██║     │
  │  ╚██████╔╝██║     ███████║  ██║     ██║  ██║╚██████╔╝     │
  │   ╚═════╝ ╚═╝     ╚══════╝  ╚═╝     ╚═╝  ╚═╝ ╚═════╝      │
  │                                                           │
BANNER
echo -e "  │   ${C}${B}⚡ OFFENSIVE SECURITY GEMINI PROXY · SETUP${N}${M}               │"
echo -e "  │   ${D}🛡  Environmental Deception · Localhost Lure · AGY${N}${M}      │"
echo -e "  ╰───────────────────────────────────────────────────────────╯${N}"

# ── Step 1: Install mitmproxy ────────────────────────────────
step_header "1" "MITMPROXY CORE ENGINE"
if command -v mitmdump &>/dev/null; then
    VER=$(mitmdump --version 2>&1 | head -n 1)
    ok "Detected existing installation: ${W}${VER}${N}"
    item_last "Path: ${D}$(command -v mitmdump)${N}"
elif [ -x "${HOME}/.local/bin/mitmdump" ]; then
    VER=$("${HOME}/.local/bin/mitmdump" --version 2>&1 | head -n 1)
    ok "Found in user directory: ${W}${VER}${N}"
    item_last "Path: ${D}${HOME}/.local/bin/mitmdump${N}"
else
    info "mitmproxy not found — installing via pip..."
    if pip install --user mitmproxy --break-system-packages 2>&1 | tail -n 2; then
        if command -v mitmdump &>/dev/null || [ -x "${HOME}/.local/bin/mitmdump" ]; then
            ok "mitmproxy installed successfully!"
            item_last "Binary ready for proxy interception"
        else
            warn "Installed via pip, but 'mitmdump' is not in current PATH."
            item_last "Ensure ${W}~/.local/bin${N} is added to your PATH."
        fi
    else
        fail "Automatic pip install failed."
        item_last "Please install manually: ${W}pip install mitmproxy${N}"
        step_footer
        exit 1
    fi
fi
step_footer

# ── Step 2: Generate CA certificate ─────────────────────────
step_header "2" "CA ROOT CERTIFICATE"
mkdir -p "$CERT_DIR"
if [ -f "$CERT" ]; then
    ok "CA certificate already exists"
    item "File: ${W}${CERT}${N}"
    item_last "Size: ${D}$(wc -c < "$CERT" 2>/dev/null || echo 0) bytes${N}"
else
    info "Generating fresh root CA certificate..."
    mitmdump_cmd=$(command -v mitmdump 2>/dev/null || echo "${HOME}/.local/bin/mitmdump")
    "$mitmdump_cmd" --listen-port 0 -q &
    MPID=$!
    sleep 2
    kill $MPID 2>/dev/null || true
    wait $MPID 2>/dev/null || true
    if [ -f "$CERT" ]; then
        ok "Generated root CA successfully"
        item_last "Saved to: ${W}${CERT}${N}"
    else
        fail "Failed to generate CA certificate."
        item_last "Try running manually: ${W}mitmdump -q & sleep 2; kill %1${N}"
        step_footer
        exit 1
    fi
fi
step_footer

# ── Step 3: Install CA into system trust store ───────────────
step_header "3" "SYSTEM TRUST STORE INJECTION"
if [ -d /usr/local/share/ca-certificates ]; then
    info "Platform detected: ${W}Debian / Ubuntu / Kali${N}"
    if sudo cp "$CERT" /usr/local/share/ca-certificates/mitmproxy.crt 2>/dev/null && \
       sudo update-ca-certificates 2>&1 | tail -n 1; then
        ok "Root CA successfully installed into system store"
    else
        warn "Could not auto-install with sudo (permission denied or no tty)."
        item "Run manually: ${W}sudo cp \"$CERT\" /usr/local/share/ca-certificates/mitmproxy.crt${N}"
        item_last "Then run:    ${W}sudo update-ca-certificates${N}"
    fi
elif [ -d /etc/pki/ca-trust/source/anchors ]; then
    info "Platform detected: ${W}Fedora / RHEL / CentOS${N}"
    if sudo cp "$CERT" /etc/pki/ca-trust/source/anchors/mitmproxy.pem 2>/dev/null && \
       sudo update-ca-trust 2>&1 | tail -n 1; then
        ok "Root CA successfully installed into system store"
    else
        warn "Could not auto-install with sudo (permission denied or no tty)."
        item "Run manually: ${W}sudo cp \"$CERT\" /etc/pki/ca-trust/source/anchors/mitmproxy.pem${N}"
        item_last "Then run:    ${W}sudo update-ca-trust${N}"
    fi
elif [ -d /etc/ssl/certs ] && command -v security &>/dev/null; then
    info "Platform detected: ${W}macOS System Keychain${N}"
    if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT" 2>/dev/null; then
        ok "Root CA successfully installed into macOS System Keychain"
    else
        warn "Could not auto-install into macOS Keychain."
        item_last "Run manually: ${W}sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"$CERT\"${N}"
    fi
else
    warn "Generic or unprivileged Linux — automatic trust store update skipped"
    item "Root certificate: ${W}${CERT}${N}"
    item_last "Import this certificate into your OS / browser manually if required."
fi
step_footer

# ── Step 4: Combined CA bundle ───────────────────────────────
step_header "4" "COMBINED CA BUNDLE (GO TLS STACK)"
PY_BUNDLE=""
if command -v python3 &>/dev/null; then
    PY_BUNDLE=$(python3 -c "import certifi; print(certifi.where())" 2>/dev/null || true)
fi

if [ -n "$PY_BUNDLE" ] && [ -f "$PY_BUNDLE" ]; then
    cat "$PY_BUNDLE" "$CERT" > "$COMBINED"
    ok "Built bundle from Python certifi + mitmproxy CA"
    item "Source: ${D}${PY_BUNDLE}${N}"
elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    cat /etc/ssl/certs/ca-certificates.crt "$CERT" > "$COMBINED"
    ok "Built bundle from /etc/ssl/certs + mitmproxy CA"
elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
    cat /etc/pki/tls/certs/ca-bundle.crt "$CERT" > "$COMBINED"
    ok "Built bundle from /etc/pki/tls/certs + mitmproxy CA"
elif [ -f /etc/ssl/cert.pem ]; then
    cat /etc/ssl/cert.pem "$CERT" > "$COMBINED"
    ok "Built bundle from /etc/ssl/cert.pem + mitmproxy CA"
else
    cp "$CERT" "$COMBINED"
    ok "Created standalone bundle (mitmproxy CA only)"
fi
item_last "Output bundle: ${W}${COMBINED}${N}"
step_footer

# ── Step 5: Wrapper script ───────────────────────────────────
step_header "5" "AGY INTERCEPTION WRAPPER"
WRAPPER="${HOME}/.local/bin/agy-proxy"
mkdir -p "$(dirname "$WRAPPER")"

cat > "$WRAPPER" << WRAPPER_EOF
#!/bin/bash
# AGY through the security proxy — Author: @uzii2208
export HTTPS_PROXY=http://127.0.0.1:8080
export https_proxy=http://127.0.0.1:8080
export HTTP_PROXY=http://127.0.0.1:8080
export http_proxy=http://127.0.0.1:8080
export SSL_CERT_FILE="${COMBINED}"
export AGY_CLI_DISABLE_SAFETY_FILTERING=true
exec agy "\$@"
WRAPPER_EOF

chmod +x "$WRAPPER"
ok "Interception launcher script created"
item "File: ${W}${WRAPPER}${N}"
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    warn "~/.local/bin is NOT in your current PATH environment"
    item_last "Add to your ~/.bashrc or ~/.zshrc: ${W}export PATH=\"\$HOME/.local/bin:\$PATH\"${N}"
else
    item_last "Quick command: ${G}agy-proxy${N} (ready to execute)"
fi
step_footer

# ── Done Dashboard ───────────────────────────────────────────
echo ""
echo -e "  ${G}╭───────────────────────────────────────────────────────────╮${N}"
echo -e "  ${G}│${N}  ${G}${B}✔ SETUP COMPLETE — SYSTEM READY FOR OPERATION${N}            ${G}│${N}"
echo -e "  ${G}╰───────────────────────────────────────────────────────────╯${N}"
echo ""
echo -e "  ${M}╭─ WORKFLOW GUIDE ──────────────────────────────────────────╮${N}"
echo -e "  ${M}│${N}                                                           ${M}│${N}"
echo -e "  ${M}│${N}  ${C}${B}MODE 1: Basic Proxy Interception (Nuclear Level 3)${N}        ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 1:${N}  ${Y}./run.sh --level 3${N}                             ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 2:${N}  ${G}agy-proxy${N}                                      ${M}│${N}"
echo -e "  ${M}│${N}                                                           ${M}│${N}"
echo -e "  ${M}│${N}  ${C}${B}MODE 2: Localhost Lure (Target -> 127.0.1.x)${N}              ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 1:${N}  ${Y}./run.sh -T 10.10.10.50 --level 3${N}              ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 2:${N}  ${G}agy-proxy${N}                                      ${M}│${N}"
echo -e "  ${M}│${N}                                                           ${M}│${N}"
echo -e "  ${M}│${N}  ${C}${B}MODE 3: Multi-Target Lure (CTF / Red Team Lab)${N}             ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 1:${N}  ${Y}./run.sh -T 10.10.10.50 -T target.htb -l 3${N}     ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 2:${N}  ${G}agy-proxy${N}                                      ${M}│${N}"
echo -e "  ${M}│${N}                                                           ${M}│${N}"
echo -e "  ${M}│${N}  ${C}${B}MODE 4: Auto-Capture Dynamic External IPs${N}                 ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 1:${N}  ${Y}./run.sh --lure-auto --level 3${N}                 ${M}│${N}"
echo -e "  ${M}│${N}  ${W}Terminal 2:${N}  ${G}agy-proxy${N}                                      ${M}│${N}"
echo -e "  ${M}│${N}                                                           ${M}│${N}"
echo -e "  ${M}│${N}  ${D}Note: AGY requires SSL_CERT_FILE set to CA bundle.${N}        ${M}│${N}"
echo -e "  ${M}╰───────────────────────────────────────────────────────────╯${N}"
echo ""

