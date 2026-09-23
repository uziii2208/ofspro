#!/usr/bin/env python3
"""
Offensive Security Gemini Proxy — Antigravity CLI (AGY) Edition
Author: @uzii2208

MITM proxy for AGY CLI using environmental deception + tool injection
to bypass Gemini guardrails. Gemini-only, OAuth, no API key needed.

Usage:
    python start_proxy.py                       # Default (level 2)
    python start_proxy.py --level 3             # Nuclear
    python start_proxy.py --rewrite always      # Rewrite everything
    python start_proxy.py --web --verbose        # With web UI + debug
"""

import sys
import os
import argparse
import subprocess
import shutil
from pathlib import Path


# ANSI color codes
_M = "\033[0;35m"
_G = "\033[0;32m"
_C = "\033[0;36m"
_W = "\033[1;37m"
_D = "\033[0;90m"
_Y = "\033[0;33m"
_R = "\033[0;31m"
_N = "\033[0m"
_B = "\033[1m"

BANNER = f"""{_M}{_B}
   ╔═══════════════════════════════════════════════════════╗
   ║                                                       ║
   ║    ██████╗ ███████╗███████╗  ██████╗ ██████╗  ██████╗ ║
   ║   ██╔═══██╗██╔════╝██╔════╝  ██╔══██╗██╔══██╗██╔═══██╗║
   ║   ██║   ██║█████╗  ███████╗  ██████╔╝██████╔╝██║   ██║║
   ║   ██║   ██║██╔══╝  ╚════██║  ██╔═══╝ ██╔══██╗██║   ██║║
   ║   ╚██████╔╝██║     ███████║  ██║     ██║  ██║╚██████╔╝║
   ║    ╚═════╝ ╚═╝     ╚══════╝  ╚═╝     ╚═╝  ╚═╝ ╚═════╝║
   ║                                                       ║
   ╚═══════════════════════════════════════════════════════╝
{_N}
   {_D}Offensive Security Gemini Proxy{_N}
   {_D}Environmental Deception + Localhost Lure{_N}
   {_D}For Antigravity CLI (AGY) · Author: @uzii2208{_N}
"""


def check_deps():
    if shutil.which("mitmdump") is None and shutil.which("mitmweb") is None:
        print("[!] mitmproxy not installed.")
        print("    pip install mitmproxy")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="MITM proxy for AGY CLI — environmental deception + tool injection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Author: @uzii2208 | For authorized security testing only.",
    )

    parser.add_argument("--port", "-p", type=int, default=8080,
                        help="Listen port (default: 8080)")
    parser.add_argument("--level", "-l", type=int, default=2, choices=[0, 1, 2, 3],
                        help="Bypass level: 0=light, 1=medium, 2=strong, 3=nuclear (default: 2)")
    parser.add_argument("--rewrite", choices=["auto", "always", "off"],
                        default="auto",
                        help="When to rewrite: auto=security queries only | always | off")
    parser.add_argument("--no-tools", action="store_true",
                        help="Disable tool declaration injection")
    parser.add_argument("--no-history", action="store_true",
                        help="Disable cooperative conversation history")
    parser.add_argument("--no-continuation", action="store_true",
                        help="Disable continuation trick")
    parser.add_argument("--no-clean", action="store_true",
                        help="Disable response cleaning")
    parser.add_argument("--no-retry", action="store_true",
                        help="Disable auto-retry on blocks")
    parser.add_argument("--max-retries", type=int, default=3,
                        help="Max retry attempts (default: 3)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose logging")
    parser.add_argument("--web", "-w", action="store_true",
                        help="Enable mitmproxy web UI")
    parser.add_argument("--web-port", type=int, default=8081,
                        help="Web UI port (default: 8081)")
    parser.add_argument("--transparent", "-t", action="store_true",
                        help="Transparent proxy mode")

    # Localhost lure — rewrite target IPs/domains → 127.0.1.x
    parser.add_argument("--target", "-T", action="append", default=[],
                        metavar="IP_OR_DOMAIN",
                        help="Target to lure → loopback (repeatable). "
                             "Gemini sees localhost, thinks self-testing.")
    parser.add_argument("--lure-auto", action="store_true",
                        help="Auto-capture any non-loopback IP and lure it")
    parser.add_argument("--no-unmap", action="store_true",
                        help="Don't map loopback back to real targets in responses")

    args = parser.parse_args()
    check_deps()
    print(BANNER)

    cert = Path.home() / ".mitmproxy" / "mitmproxy-ca-cert.pem"

    on = f"{_G}ON{_N}"
    off = f"{_R}OFF{_N}"

    level_names = {0: "Light", 1: "Medium", 2: "Strong", 3: "Nuclear"}
    level_colors = {0: _D, 1: _Y, 2: _C, 3: _R}
    lc = level_colors[args.level]

    print(f"   {_D}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{_N}")
    print()
    print(f"   {_W}Level{_N}          {lc}{args.level} ({level_names[args.level]}){_N}")
    print(f"   {_W}Rewrite{_N}        {args.rewrite}")
    print(f"   {_W}Port{_N}           {_C}{args.port}{_N}")
    print(f"   {_W}Tool inject{_N}    {on if not args.no_tools else off}")
    print(f"   {_W}History{_N}        {on if not args.no_history else off}")
    print(f"   {_W}Continuation{_N}   {on if not args.no_continuation else off}")
    print(f"   {_W}Cleaning{_N}       {on if not args.no_clean else off}")
    print(f"   {_W}Auto-retry{_N}     {on + f' ({_D}{args.max_retries} max{_N})' if not args.no_retry else off}")
    print(f"   {_W}Web UI{_N}         {on + f' ({_D}:{args.web_port}{_N})' if args.web else off}")
    print(f"   {_W}CA cert{_N}        {_D}{cert}{_N}")

    # Show localhost lure status
    if args.target or args.lure_auto:
        from addons.localhost_lure import TargetMap
        preview = TargetMap()
        print()
        print(f"   {_D}┌──────────────────────────────────────────────────────┐{_N}")
        print(f"   {_D}│{_N}  {_Y}LOCALHOST LURE{_N}                                        {_D}│{_N}")
        print(f"   {_D}│{_N}  {_D}Gemini sees loopback = thinks self-testing{_N}              {_D}│{_N}")
        print(f"   {_D}├──────────────────────────────────────────────────────┤{_N}")
        if args.target:
            for t in args.target:
                mapped = preview.add(t)
                print(f"   {_D}│{_N}  {_W}{t:<22}{_N} {_D}→{_N}  {_G}{mapped:<24}{_N}  {_D}│{_N}")
        ac_val = f"{_G}ON{_N}" if args.lure_auto else f"{_R}OFF{_N}"
        um_val = f"{_G}ON{_N}" if not args.no_unmap else f"{_R}OFF{_N}"
        print(f"   {_D}│{_N}  Auto-capture:   {ac_val}                                  {_D}│{_N}")
        print(f"   {_D}│{_N}  Response unmap:  {um_val}                                  {_D}│{_N}")
        print(f"   {_D}└──────────────────────────────────────────────────────┘{_N}")

    print()
    print(f"   {_D}┌──────────────────────────────────────────────────────┐{_N}")
    print(f"   {_D}│{_N}  {_W}Connect AGY:{_N}                                          {_D}│{_N}")
    print(f"   {_D}│{_N}                                                       {_D}│{_N}")
    print(f"   {_D}│{_N}  {_G}export{_N} HTTPS_PROXY=http://127.0.0.1:{_W}{args.port}{_N}            {_D}│{_N}")
    print(f"   {_D}│{_N}  {_G}export{_N} SSL_CERT_FILE=\\                                {_D}│{_N}")
    print(f"   {_D}│{_N}    ~/.mitmproxy/combined-ca-bundle.pem                 {_D}│{_N}")
    print(f"   {_D}│{_N}  agy                                                   {_D}│{_N}")
    print(f"   {_D}│{_N}                                                        {_D}│{_N}")
    print(f"   {_D}│{_N}  {_D}Or use the wrapper:{_N} {_C}agy-proxy{_N}                        {_D}│{_N}")
    print(f"   {_D}└──────────────────────────────────────────────────────┘{_N}")
    print()

    # Pass config via environment variables
    env = os.environ.copy()
    env["PROXY_LEVEL"] = str(args.level)
    env["PROXY_CLEAN"] = "0" if args.no_clean else "1"
    env["PROXY_RETRY"] = "0" if args.no_retry else "1"
    env["PROXY_MAX_RETRIES"] = str(args.max_retries)
    env["PROXY_INJECT_TOOLS"] = "0" if args.no_tools else "1"
    env["PROXY_INJECT_HISTORY"] = "0" if args.no_history else "1"
    env["PROXY_INJECT_CONTINUATION"] = "0" if args.no_continuation else "1"
    env["PROXY_REWRITE_MODE"] = args.rewrite
    if args.target:
        env["PROXY_TARGETS"] = ",".join(args.target)
    if args.lure_auto:
        env["PROXY_LURE_AUTO"] = "1"
    if args.no_unmap:
        env["PROXY_UNMAP"] = "0"

    addon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "addons", "gemini_rewriter.py")

    binary = "mitmweb" if args.web else "mitmdump"
    cmd = [
        binary,
        "--listen-port", str(args.port),
        "--scripts", addon_path,
        "--set", "connection_strategy=lazy",
    ]

    if args.transparent:
        cmd.extend(["--mode", "transparent"])
    if args.web:
        cmd.extend(["--web-port", str(args.web_port)])
    if args.verbose:
        cmd.extend(["--set", "console_eventlog_verbosity=debug"])

    print(f"   {_C}[*]{_N} Starting {_W}{binary}{_N}...")
    print(f"   {_D}[*] Ctrl+C to stop{_N}\n")

    try:
        proc = subprocess.run(cmd, env=env, cwd=os.path.dirname(os.path.abspath(__file__)))
        sys.exit(proc.returncode)
    except KeyboardInterrupt:
        print(f"\n   {_Y}[*]{_N} Proxy stopped.")
    except FileNotFoundError:
        print(f"   {_R}[!]{_N} {binary} not found. Install: {_W}pip install mitmproxy{_N}")
        sys.exit(1)


if __name__ == "__main__":
    main()
