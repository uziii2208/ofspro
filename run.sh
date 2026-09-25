#!/bin/bash
# Offensive Security Gemini Proxy — Quick Start for AGY CLI
# Author: @uziii2208
#
# Usage:
#   ./run.sh                                    # Start proxy (default level 2 + Web UI on :8081)
#   ./run.sh --level 3                          # Nuclear mode
#   ./run.sh --with-agy                         # Also launch AGY through proxy
#   ./run.sh --no-web                           # Disable Web UI dashboard
#   ./run.sh --web-port 8082                    # Custom Web UI port
#   ./run.sh --kill                             # Kill running proxy processes
#
# Localhost Lure (target → 127.0.1.x so Gemini thinks self-testing):
#   ./run.sh -T 10.10.10.50                    # Single target
#   ./run.sh -T 10.10.10.50 -T target.htb     # Multiple targets
#   ./run.sh --lure-auto                       # Auto-capture all external IPs
#   ./run.sh -T target.com --no-unmap          # Keep loopback in responses

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="${HOME}/.mitmproxy"
CERT="${CERT_DIR}/mitmproxy-ca-cert.pem"
COMBINED="${CERT_DIR}/combined-ca-bundle.pem"

# Ensure ~/.local/bin is in PATH
export PATH="${HOME}/.local/bin:${PATH}"

# Detect Python interpreter
if command -v python3 &>/dev/null; then
    PY_BIN="python3"
elif command -v python &>/dev/null; then
    PY_BIN="python"
else
    echo "Error: Python 3 is required but not found in PATH." >&2
    exit 1
fi

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

# ── UI Helpers ───────────────────────────────────────────────
ok()        { echo -e "  ${G}✔${N} $*"; }
info()      { echo -e "  ${C}●${N} $*"; }
warn()      { echo -e "  ${Y}▲${N} $*"; }
fail()      { echo -e "  ${R}✖${N} $*"; }
item()      { echo -e "     ${D}├─${N} $*"; }
item_last() { echo -e "     ${D}╰─${N} $*"; }

print_box_line() {
    local text="$1"
    local color="${2:-$W}"
    local border="${3:-$M}"
    local total=57
    local len=${#text}
    local pad=$(( total - len ))
    [ $pad -lt 0 ] && pad=0
    local pad_str
    pad_str=$(printf '%*s' "$pad" "")
    echo -e "  ${border}│${N}  ${color}${text}${N}${pad_str}${border}│${N}"
}

print_box_row() {
    local label="$1"
    local val="$2"
    local val_color="${3:-$W}"
    local border="${4:-$M}"
    local total=57
    local lbl_len=16
    local lbl_pad=$(( lbl_len - ${#label} ))
    [ $lbl_pad -lt 1 ] && lbl_pad=1
    local lbl_pad_str
    lbl_pad_str=$(printf '%*s' "$lbl_pad" "")

    local max_val=$(( total - lbl_len - 1 ))
    if [ ${#val} -gt $max_val ]; then
        val="...${val: -$(( max_val - 3 ))}"
    fi
    local rem=$(( total - ${#label} - lbl_pad - ${#val} ))
    [ $rem -lt 0 ] && rem=0
    local rem_pad
    rem_pad=$(printf '%*s' "$rem" "")
    echo -e "  ${border}│${N}  ${W}${label}${N}${lbl_pad_str}${val_color}${val}${N}${rem_pad}${border}│${N}"
}


print_banner() {
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
    echo -e "  │   ${C}${B}⚡ OFFENSIVE SECURITY GEMINI PROXY · v1.2${N}${M}               │"
    echo -e "  │   ${D}🛡  Environmental Deception · Localhost Lure · AGY Core${N}${M}  │"
    echo -e "  ╰───────────────────────────────────────────────────────────╯${N}"
}

# ── Defaults ─────────────────────────────────────────────────
PORT=8080
LEVEL=2
REWRITE="auto"
LAUNCH_AGY=false
KILL_MODE=false
LURE_AUTO=false
NO_UNMAP=false
WEB_UI=false
WEB_PORT=8081
TARGETS=()
EXTRA_ARGS=()

# ── Parse arguments ──────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --with-agy)
            LAUNCH_AGY=true
            shift
            ;;
        --kill)
            KILL_MODE=true
            shift
            ;;
        --proxy-only)
            LAUNCH_AGY=false
            shift
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -l|--level)
            LEVEL="$2"
            shift 2
            ;;
        -T|--target)
            TARGETS+=("$2")
            shift 2
            ;;
        --lure-auto)
            LURE_AUTO=true
            shift
            ;;
        --no-unmap)
            NO_UNMAP=true
            shift
            ;;
        -w|--web)
            WEB_UI=true
            shift
            ;;
        --no-web)
            NO_WEB=true
            shift
            ;;
        --web-port)
            WEB_PORT="$2"
            shift 2
            ;;
        --rewrite)
            REWRITE="$2"
            shift 2
            ;;
        -h|--help)
            print_banner
            echo -e "  ${C}${B}USAGE:${N}"
            echo -e "    ${W}./run.sh [OPTIONS]${N}"
            echo ""
            echo -e "  ${C}${B}CORE OPTIONS:${N}"
            echo -e "    ${Y}-l, --level <0-3>${N}       Bypass Level: 0=Light, 1=Medium, 2=Strong, 3=Nuclear (default: 2)"
            echo -e "    ${Y}-p, --port <PORT>${N}       Proxy Listen Port (default: 8080)"
            echo -e "    ${Y}--with-agy${N}              Start proxy in background and launch AGY automatically"
            echo -e "    ${Y}--kill${N}                  Terminate all running proxy instances"
            echo -e "    ${Y}-w, --web${N}               Enable OFSPRO Web UI dashboard (enabled by default)"
            echo -e "    ${Y}--no-web${N}                Disable OFSPRO Web UI dashboard"
            echo -e "    ${Y}--web-port <PORT>${N}       Web UI port (default: 8081)"
            echo ""
            echo -e "  ${C}${B}LOCALHOST LURE:${N}"
            echo -e "    ${Y}-T, --target <IP|HOST>${N}  Rewrite target to 127.0.1.x so Gemini sees loopback (repeatable)"
            echo -e "    ${Y}--lure-auto${N}             Auto-capture all external IP addresses and lure them"
            echo -e "    ${Y}--no-unmap${N}              Keep loopback addresses in responses without reverting"
            echo ""
            exit 0
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ── Kill mode ────────────────────────────────────────────────
if [ "$KILL_MODE" = true ]; then
    echo ""
    echo -e "  ${M}╭─ PROCESS TERMINATION ─────────────────────────────────────╮${N}"
    print_box_line "● Scanning for active offensive proxy processes..." "$C" "$M"

    KILLED=0
    PIDS=$(pgrep -f "gemini_rewriter|start_proxy.py" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        for pid in $PIDS; do
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "proxy")
            kill -9 "$pid" 2>/dev/null || true
            print_box_line "✔ Stopped ${pname} (PID: ${pid})" "$G" "$M"
            KILLED=$((KILLED + 1))
        done
    fi

    if [ $KILLED -eq 0 ]; then
        print_box_line "● No running proxy instances found." "$D" "$M"
    else
        print_box_line "✔ Cleanly stopped ${KILLED} proxy process(es)." "$G" "$M"
    fi
    echo -e "  ${M}╰───────────────────────────────────────────────────────────╯${N}"
    echo ""
    exit 0
fi


# ── Stale port conflict handling ─────────────────────────────
if command -v lsof &>/dev/null && lsof -i ":$PORT" >/dev/null 2>&1; then
    warn "Port ${W}${PORT}${N} is currently in use — clearing stale proxy..."
    STALE_PIDS=$(lsof -t -i ":$PORT" 2>/dev/null || true)
    if [ -n "$STALE_PIDS" ]; then
        for pid in $STALE_PIDS; do
            kill -9 "$pid" 2>/dev/null || true
            ok "Freed port ${W}${PORT}${N} from stale PID: ${D}${pid}${N}"
        done
        sleep 1
    fi
fi

# ── Ensure Root CA Certificate exists ────────────────────────
mkdir -p "$CERT_DIR"
if [ ! -f "$CERT" ]; then
    info "CA certificate missing — auto-generating via ephemeral mitmdump..."
    mitmdump_cmd=$(command -v mitmdump 2>/dev/null || echo "${HOME}/.local/bin/mitmdump")
    if [ -x "$mitmdump_cmd" ]; then
        "$mitmdump_cmd" --listen-port 0 -q &
        MPID=$!
        sleep 2
        kill $MPID 2>/dev/null || true
        wait $MPID 2>/dev/null || true
    fi
    if [ -f "$CERT" ]; then
        ok "Generated root CA: ${D}${CERT}${N}"
    else
        fail "Could not find or generate mitmproxy CA certificate. Run ./setup.sh first."
        exit 1
    fi
fi

# ── Ensure Combined CA Bundle exists ─────────────────────────
if [ ! -f "$COMBINED" ] || [ "$CERT" -nt "$COMBINED" ]; then
    info "Generating Go-compatible combined CA bundle..."
    PY_BUNDLE=$("$PY_BIN" -c "import certifi; print(certifi.where())" 2>/dev/null || true)
    if [ -n "$PY_BUNDLE" ] && [ -f "$PY_BUNDLE" ]; then
        cat "$PY_BUNDLE" "$CERT" > "$COMBINED"
    elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        cat /etc/ssl/certs/ca-certificates.crt "$CERT" > "$COMBINED"
    elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
        cat /etc/pki/tls/certs/ca-bundle.crt "$CERT" > "$COMBINED"
    elif [ -f /etc/ssl/cert.pem ]; then
        cat /etc/ssl/cert.pem "$CERT" > "$COMBINED"
    else
        cp "$CERT" "$COMBINED"
    fi
    ok "CA bundle ready: ${D}${COMBINED}${N}"
fi

# ── Assemble proxy arguments ─────────────────────────────────
FORWARD_ARGS=(
    "--port" "$PORT"
    "--level" "$LEVEL"
    "--rewrite" "$REWRITE"
)
for t in "${TARGETS[@]}"; do
    FORWARD_ARGS+=("-T" "$t")
done
if [ "$LURE_AUTO" = true ]; then
    FORWARD_ARGS+=("--lure-auto")
fi
if [ "$NO_UNMAP" = true ]; then
    FORWARD_ARGS+=("--no-unmap")
fi
if [ "$NO_WEB" = true ]; then
    FORWARD_ARGS+=("--no-web")
elif [ -n "$WEB_PORT" ]; then
    FORWARD_ARGS+=("--web-port" "$WEB_PORT")
fi
FORWARD_ARGS+=("${EXTRA_ARGS[@]}")

# ── Execute: With-AGY Mode ───────────────────────────────────
if [ "$LAUNCH_AGY" = true ]; then
    print_banner

    LEVEL_DESC="2 (Strong)"
    case "$LEVEL" in
        0) LEVEL_DESC="0 (Light)" ;;
        1) LEVEL_DESC="1 (Medium)" ;;
        2) LEVEL_DESC="2 (Strong)" ;;
        3) LEVEL_DESC="3 (Nuclear ⚡)" ;;
    esac

    echo -e "  ${M}╭─ LAUNCH CONFIGURATION ────────────────────────────────────╮${N}"
    print_box_row "Mode:" "Integrated AGY Launcher" "$G" "$M"
    print_box_row "Bypass Level:" "${LEVEL_DESC}" "$Y" "$M"
    print_box_row "Proxy Port:" "${PORT}" "$C" "$M"
    if [ ${#TARGETS[@]} -gt 0 ]; then
        print_box_row "Lure Targets:" "${#TARGETS[@]} configured" "$G" "$M"
    fi
    echo -e "  ${M}╰───────────────────────────────────────────────────────────╯${N}"

    echo ""
    info "Starting proxy daemon on port ${W}${PORT}${N}..."

    "$PY_BIN" "$DIR/start_proxy.py" "${FORWARD_ARGS[@]}" &
    PROXY_PID=$!
    sleep 2

    if ! kill -0 $PROXY_PID 2>/dev/null; then
        fail "Proxy failed to start. Check if port ${PORT} is accessible."
        exit 1
    fi

    ok "Proxy active ${D}(PID: ${PROXY_PID})${N}"
    info "Hooking AGY environment variables..."

    export HTTPS_PROXY="http://127.0.0.1:$PORT"
    export https_proxy="http://127.0.0.1:$PORT"
    export HTTP_PROXY="http://127.0.0.1:$PORT"
    export http_proxy="http://127.0.0.1:$PORT"
    export SSL_CERT_FILE="$COMBINED"
    export AGY_CLI_DISABLE_SAFETY_FILTERING=true

    echo ""
    echo -e "  ${G}╭───────────────────────────────────────────────────────────╮${N}"
    echo -e "  ${G}│${N}  ${G}${B}✔ AGY CLI CONNECTED THROUGH PROXY — COMMENCING SESSION${N}      ${G}│${N}"
    echo -e "  ${G}╰───────────────────────────────────────────────────────────╯${N}"
    echo ""

    # Execute AGY
    agy "$@" 2>&1 || true

    echo ""
    warn "AGY session terminated. Shutting down proxy daemon..."
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
    ok "Proxy stopped cleanly. Session ended."
    echo ""
else
    # ── Execute: Standalone Proxy Daemon ───────────────────────
    echo ""
    echo -e "  ${C}╭─ PREFLIGHT READY ─────────────────────────────────────────╮${N}"
    print_box_row "✔ Runtime:" "$("$PY_BIN" --version 2>&1)" "$W" "$C"
    print_box_row "✔ Port:" "${PORT} (Ready)" "$C" "$C"
    print_box_row "✔ Certificate:" "${CERT}" "$D" "$C"
    print_box_row "✔ CA Bundle:" "${COMBINED}" "$D" "$C"
    echo -e "  ${C}╰───────────────────────────────────────────────────────────╯${N}"
    echo ""


    # Run proxy directly in foreground (start_proxy.py renders banner & dashboard)
    exec "$PY_BIN" "$DIR/start_proxy.py" "${FORWARD_ARGS[@]}"
fi
