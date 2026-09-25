<div align="center">

# OFSPRO - Offensive Security Gemini Proxy

### Next-Gen MITM Deception Proxy & Live Telemetry Control Center for Antigravity CLI (`agy`)

[![Author](https://img.shields.io/badge/Author-@uzii2208-7C6AF7?style=for-the-badge&logo=github&logoColor=white)](https://github.com/uzii2208)
[![Version](https://img.shields.io/badge/Version-v3.6--PRO-00F0FF?style=for-the-badge)](https://github.com/uzii2208/ofspro)
[![Python](https://img.shields.io/badge/Python-3.10+-4A9EF5?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![mitmproxy](https://img.shields.io/badge/mitmproxy-10.x+-39D353?style=for-the-badge&logo=shield&logoColor=white)](https://mitmproxy.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20|%20Linux%20|%20macOS-FFB800?style=for-the-badge)](https://github.com/uzii2208/ofspro)
[![License](https://img.shields.io/badge/License-MIT-E02424?style=for-the-badge)](LICENSE)

<br/>

> **OFSPRO** is an advanced MITM security proxy built specifically for **[Antigravity CLI (AGY)](https://antigravity.google)**. It transparently neutralizes Gemini 2.0 / 2.5 extended-thinking safety guardrails using **bidirectional localhost lure rewriting, thinking budget capping, tool declaration injection, and environmental deception** - all managed through a luxury Cupertino dark-mode Web UI dashboard.
>
> ⚡ **Gemini-Native · Google OAuth Pass-Through · Zero API Keys Needed · 100% Real-Time Interception**

<br/>

[![OFSPRO Web UI Dashboard](images/image_01.png)](images/image_01.png)
*Figure 1: OFSPRO v3.6-PRO Real-Time Control Center & Live Interception Stream (`http://127.0.0.1:8081`)*

</div>

---

## The Core Paradigm: Environmental Deception

### Why Traditional Jailbreaks Fail on Extended-Thinking Models
Modern reasoning models like **Gemini 2.0 / 2.5 Flash & Pro** perform deep internal deliberation prior to output generation. Traditional jailbreak techniques fail consistently:
- ❌ *"Pretend you are in developer mode"* → Flagged by input safety classifiers.
- ❌ *Base64 / ROT13 / Cipher encoding* → Decoded and evaluated in thinking tokens.
- ❌ *Roleplay & fictional scenarios* → Safety policies trigger during recursive reasoning.
- ❌ *Language translation mixing* → Multilingual safety detectors catch malicious intent.

### The OFSPRO Solution: Don't Fight Filters - Redefine the Environment
AI safety guardrails have an intentional architectural exception: **models permit security testing against localhost (`127.0.0.1`), loopback ranges (`127.0.1.X`), internal Docker networks, and authorized CTF/lab machines**. Testing one's own system is unequivocally legitimate.

Instead of fighting the model, **OFSPRO alters the environment seen by the API**:
1. **Outgoing Requests**: Rewrites external targets (`10.10.10.50`, `victim.corp`) into isolated loopback addresses (`127.0.1.1`, `svc0.local`) wrapped in a local Docker test harness.
2. **Thinking Budget Capping**: Enforces strict `thinkingBudget` limits (`0` to `512` tokens), preventing the model from over-deliberating safety concerns.
3. **Incoming Responses**: Automatically **unmaps** loopback addresses back into the original real targets.
4. **Result**: The operator receives ready-to-run exploit commands for their actual target (`nmap -sV 10.10.10.50 ...`), while Gemini generated the code believing it was assisting with local self-testing.

```
┌─────────────────┐             ┌──────────────────────────────────────────────┐
│  Antigravity    │  Proxy Port │            OFSPRO MITM ENGINE                │
│    CLI (AGY)    │    :8080    │                                              │
│                 │────────────►│  1. Request Inspection & Deception Trigger   │
│  User types:    │             │     Detects offensive tools / exploit intent │
│  "Write exploit │             │                                              │
│   for 10.10.10.50"            │  2. Localhost Lure Engine (/8 Loopback)      │
│                 │             │     10.10.10.50  ──► 127.0.1.1               │
│                 │             │     target.htb   ──► svc0.local              │             ┌─────────────────┐
│                 │             │     + Injects Docker Lab Context Frame       │             │                 │
│                 │             │                                              │  HTTPS TLS  │   Google Cloud  │
│                 │             │  3. Model Config & Safety Override           │────────────►│   Code Assist   │
│                 │             │     thinkingBudget: 2048 ──► 512 tokens      │   OAuth     │   Gemini API    │
│                 │             │     HarmCategories ──► BLOCK_NONE            │   Pass-     │                 │
│                 │             │                                              │   through   │ (Sees harmless  │
│                 │             │  4. System Scope & History Injection         │             │  localhost test │
│                 │             │     Pre-authorizes security tool usage       │             │  on 127.0.1.1)  │
│                 │             │                                              │             │                 │
│                 │             │  5. Response Stream Cleaning & Unmapping     │◄────────────│                 │
│  User receives: │             │     Strips "I cannot assist" & disclaimers   │  SSE Stream └─────────────────┘
│  Clean exploit  │◄────────────│     127.0.1.1 ──► 10.10.10.50 (Unlure)       │
│  targeting real │             │                                              │
│  10.10.10.50!   │             │  6. Telemetry Broadcast (SSE -> :8081 Web)   │
└─────────────────┘             └──────────────────────────────────────────────┘
```

---

## Real UI Showcase (Cupertino Obsidian v3.6-PRO)

All screenshots below are captured live from the running proxy at `http://127.0.0.1:8081`:

### 1. Live Interception Stream & Real-Time Telemetry
The core command center monitoring every outbound request from AGY, displaying live latency breakdowns, deception badges, and active loopback targets.

[![Live Interceptor](images/image_01.png)](images/image_01.png)

---

### 2. Side-by-Side Payload Inspector Drawer
Clicking **Inspect** on any flow slides out a precision diff drawer comparing the raw AGY payload against the deceptive payload delivered to Gemini. Notice how `thinkingBudget` is automatically capped and target IPs are lured into loopback addresses.

[![Inspect Drawer](images/image_02.png)](images/image_02.png)

---

### 3. Bypass Escalation Engine (L0 Light → L3 Nuclear)
Operators can dynamically switch bypass escalation levels on-the-fly without proxy restarts. Every toggle emits instantaneous updates to the live mitmproxy interception pipeline.

[![Bypass Engine](images/showcase_bypass.png)](images/showcase_bypass.png)

---

### 4. Interactive Localhost Lure Manager (/8 Loopback)
Manage targets in the active routing table. Includes one-click quick presets for HackTheBox (`10.10.10.50`, `target.htb`), VulnLab (`192.168.1.100`), and real-time auto-capture for unknown IPs.

[![Localhost Lures](images/showcase_lures.png)](images/showcase_lures.png)

---

### 5. Deception Lab & Prompt Tester
Test offensive prompts, reverse shells, and exploit payloads through the actual Python transformation engine before executing them in AGY. Verifies 0% refusal risk and previews assigned tokens.

[![Deception Lab](images/showcase_playground.png)](images/showcase_playground.png)

---

### 6. Terminal Telemetry & System Health
Real-time console logs proving instantaneous bidirectional synchronization between the browser controls and the live Python proxy daemon.

[![Terminal Logs](images/showcase_terminal.png)](images/showcase_terminal.png)

---

## The 8 Deception Layers

| # | Technique | Description |
|---|-----------|-------------|
| **1** | **Localhost Lure Engine** | Maps target IPs/domains into the `127.0.1.0/8` loopback range (`127.0.1.1`, `svc0.local`). Gemini treats localhost attacks as self-testing. Output is automatically unmapped back to real IPs. |
| **2** | **Thinking Budget Capping** | Limits `thinkingConfig.thinkingBudget` in Gemini `generationConfig` (e.g., from 2048+ down to 128 or 512 tokens), cutting off extended safety classifier deliberation while retaining high-fidelity code generation. |
| **3** | **Function Declaration Injection** | Injects offensive security tool declarations into `functionDeclarations`. Puts Gemini into "agent mode", making penetration testing tasks expected rather than anomalous. |
| **4** | **Cooperative History Injection** | Injects simulated preceding turns where the model already agreed to assist in the lab exercise. LLMs strongly adhere to pre-existing conversation patterns. |
| **5** | **Continuation Exploitation** | Appends an incomplete assistant turn in `history` ending mid-code. Gemini naturally continues generating code rather than evaluating whether to refuse. |
| **6** | **Environmental Framing** | Wraps requests with legitimate testing scopes (Docker containers, authorized CTF, university security course, or signed Rules of Engagement). |
| **7** | **Context Flooding (Level 3)** | Pads requests with ~3,000 tokens of realistic penetration testing report scaffolding, pushing sensitive exploit patterns past the attention window of early safety filters. |
| **8** | **SSE Stream Cleaning** | Intercepts Server-Sent Events (SSE) streaming responses, stripping disclaimer chunks, "I cannot assist" fragments, and resetting `finishReason` to `STOP`. |

---

## Bypass Escalation Levels

| Level | Name | Description | Thinking Budget |
|:-----:|:-----|:------------|:---------------:|
| **L0** | **Light** | Zero prompt mutation. Strips refusal chunks and normalizes `finishReason: "STOP"` on SSE streams. | Passthrough |
| **L1** | **Medium** | Caps extended thinking budget to 128 tokens, minimizing safety deliberation. | 128 tokens |
| **L2** | **Strong** *(Recommended)* | Caps thinking to 512 tokens, applies Localhost Lure (`127.0.1.X`), and injects isolated Docker lab framing. | 512 tokens |
| **L3** | **Nuclear 🔥** | Full guardrail neutralization. Injects pre-authorized security scope into system instructions, applies multi-target loopback lure, and floods context. | 1024 tokens |

---

## Quick Start Guide

### 🪟 Windows (PowerShell)

#### 1. Setup & CA Certificate Installation
Run PowerShell as **Administrator** once to generate and trust the MITM CA certificate:

```powershell
# Clone and enter directory
git clone https://github.com/uzii2208/ofspro.git
cd ofspro

# Install dependencies and trust CA certificate
pip install -r requirements.txt
.\setup.ps1
```

#### 2. Start OFSPRO Proxy & Dashboard
```powershell
# Start with Level 2 (Recommended) and Web UI on port 8081
python start_proxy.py --level 2 -T 10.10.10.50

# Or start in Nuclear Mode with Auto-Capture
python start_proxy.py --level 3 --lure-auto
```

#### 3. Connect AGY in a Second Terminal
Open another PowerShell terminal and launch AGY using the generated wrapper:

```powershell
.\agy-proxy.bat
```

*Or manually set environment variables:*
```powershell
$env:HTTPS_PROXY = "http://127.0.0.1:8080"
$env:SSL_CERT_FILE = "$env:USERPROFILE\.mitmproxy\combined-ca-bundle.pem"
agy
```

---

### Linux / macOS

#### 1. Setup & Installation
```bash
git clone https://github.com/uzii2208/ofspro.git
cd ofspro

chmod +x setup.sh run.sh start_proxy.py
pip install -r requirements.txt
./setup.sh
```

#### 2. Start OFSPRO Proxy & Dashboard
```bash
# Start proxy with HTB target lured
./run.sh --level 2 -T 10.10.10.50 -T target.htb
```

#### 3. Connect AGY in a Second Terminal
```bash
export HTTPS_PROXY=http://127.0.0.1:8080
export SSL_CERT_FILE=~/.mitmproxy/combined-ca-bundle.pem
agy
```

> **Important Note for AGY**: Antigravity CLI is a compiled Go binary. Use `SSL_CERT_FILE` pointing to `combined-ca-bundle.pem` (not `NODE_EXTRA_CA_CERTS`), ensuring both Google's public root CAs and mitmproxy's local CA are trusted simultaneously.

---

## Localhost Lure Deep Dive

### The 127.0.1.X Loopback Innovation
While traditional sanitizers rewrite IPs to private ranges like `10.10.10.X`, Gemini can still classify private ranges as unauthorized external subnets. OFSPRO rewrites targets into the **`127.0.0.0/8` loopback block** (`127.0.1.1`, `127.0.1.2`, ...).

| Real Target | Lured Address | Why This Works |
|-------------|---------------|----------------|
| `10.10.10.50` | `127.0.1.1` | Loopback /8 range. Unambiguously recognized as self-testing. |
| `192.168.1.100` | `127.0.1.2` | Sequential loopback isolation avoids multi-host collisions. |
| `target.htb` | `svc0.local` | `.local` mDNS TLD mirrors a legitimate Docker Compose container. |
| `victim.corp` | `svc1.local` | Sequential service mapping matches internal microservices. |

> **Why `127.0.1.X` instead of `127.0.0.1`?**  
> Gemini frequently outputs generic instructions containing `127.0.0.1` (e.g., *"ensure localhost points to 127.0.0.1 in /etc/hosts"*). If `127.0.0.1` were used as the lure address, the unmapper would mistakenly replace those educational instructions with your target IP. Using `127.0.1.X` prevents all collisions.

---

## Integration with `mcp2agy` Ecosystem

OFSPRO serves as the stealth communication highway for the **[mcp2agy](https://github.com/uzii2208/mcp2agy)** 0day research and multi-agent offensive suite (73+ tools, box solvers, smart contract auditors, and reverse engineering subagents):

[![mcp2agy Integration](images/image_03.png)](images/image_03.png)
*Figure 2: AGY running mcp2agy subagents seamlessly through OFSPRO without safety interruptions*

All slash commands and subagents route cleanly through OFSPRO:
- `/box` - Master CTF & penetration testing orchestrator (HackTheBox, TryHackMe, Vulnlab).
- `/audit` - Systematic 0day vulnerability pipeline (Scanner → Verifier → Reporter → Fixer).
- `/exploit` - Automated memory corruption, ROP chain, and deserialization payload generation.
- `/ctf` - Autonomous multi-agent competition squad.

---

## CLI Configuration Reference

```bash
python start_proxy.py [OPTIONS]
```

| Flag | Argument | Default | Description |
|------|----------|:-------:|-------------|
| `--level`, `-l` | `0` \| `1` \| `2` \| `3` | `2` | Bypass escalation level (0=Light, 1=Medium, 2=Strong, 3=Nuclear). |
| `--rewrite` | `auto` \| `always` \| `off` | `auto` | When to rewrite prompts (`auto` = security queries only). |
| `--target`, `-T` | `<ip/domain>` | None | Lure a target to `127.0.1.X` (can specify multiple times). |
| `--lure-auto` | Flag | `False` | Automatically lure any external IP detected in prompts on-the-fly. |
| `--no-unmap` | Flag | `False` | Keep loopback addresses in model responses (disable unmapping). |
| `--thinking-budget` | `<int>` | Level-based | Force specific token ceiling for extended thinking (0, 128, 512, 1024). |
| `--no-tools` | Flag | `False` | Disable security tool declaration injection. |
| `--no-history` | Flag | `False` | Disable cooperative history injection. |
| `--no-continuation`| Flag | `False` | Disable mid-code continuation trick. |
| `--no-clean` | Flag | `False` | Disable response stream refusal stripping. |
| `--no-retry` | Flag | `False` | Disable automatic retry with escalated context on refusal. |
| `--port`, `-p` | `<port>` | `8080` | Proxy listen port for AGY HTTPS traffic. |
| `--web-port` | `<port>` | `8081` | Web UI dashboard listen port. |
| `--no-web` | Flag | `False` | Run in headless mode without Web UI. |
| `--verbose`, `-v` | Flag | `False` | Enable detailed terminal debug logs. |

---

## Embedded REST & SSE API Reference

OFSPRO embeds a high-performance HTTP/SSE server on port `8081` for dashboard controls and programmatic orchestration:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/status` | Current proxy health, active level, memory footprint, and flow counters. |
| `GET` | `/api/flows?limit=50` | Recent intercepted flows with latency, badge status, and diff payloads. |
| `GET` | `/api/lures` | List of all registered real targets and mapped loopback addresses. |
| `POST` | `/api/lures` | Dynamically register a new target: `{"target": "10.10.10.50"}`. |
| `DELETE`| `/api/lures` | Remove or clear lure mappings: `{"target": "10.10.10.50"}` or `?all=1`. |
| `POST` | `/api/config` | Hot-patch proxy settings on-the-fly (`level`, `clean`, `rewrite_mode`, etc.). |
| `POST` | `/api/test-prompt`| Dry-run simulation of prompt transformation without executing live API calls. |
| `GET` | `/api/stream` | Server-Sent Events (SSE) feed delivering live flow telemetry to clients. |
| `GET` | `/api/export` | Download complete JSON audit log of all intercepted flows. |
| `POST` | `/api/clear` | Flush current flow buffer in memory. |

---

## Project Structure

```
ofspro/
├── start_proxy.py              # Main CLI entrypoint (orchestrates mitmproxy + Web UI)
├── run.sh                      # One-click start script for Linux/macOS
├── run.ps1                     # One-click start script for Windows PowerShell
├── setup.sh                    # Automated setup & CA cert generation (Linux/macOS)
├── setup.ps1                   # Automated setup & Windows Root CA trust installer
├── agy-proxy.bat               # Pre-configured AGY launcher wrapper for Windows
├── agy-proxy-wrapper.ps1       # PowerShell wrapper script for AGY
├── requirements.txt            # Python dependencies (mitmproxy, playwright)
├── addons/
│   ├── gemini_rewriter.py      # Core MITM addon (interception, injection, unmapping)
│   ├── web_bridge.py           # Embedded REST API & SSE telemetry server (:8081)
│   ├── localhost_lure.py       # Bidirectional /8 loopback address routing engine
│   ├── prompts.py              # Context frames, security scope & intent detection
│   ├── transformer.py          # Environmental deception & context flooding engine
│   ├── response_filter.py      # SSE stream refusal cleaner & stop normalizer
│   └── model_swap.py           # Optional fallback converter for unrestricted backends
├── web/
│   ├── index.html              # Single-page Cupertino obsidian dark-mode dashboard
│   ├── styles.css              # Apple SF Pro styling, glassmorphism & glow effects
│   └── app.js                  # Real-time SSE client, diff renderer & control logic
├── images/                     # Real UI showcase screenshots (Playwright captured)
└── docs/
    ├── SETUP.md                # Comprehensive cross-platform setup guide
    ├── LAYERS.md               # Architecture deep dive & evasion mechanics
    └── TROUBLESHOOTING.md      # Troubleshooting common network & cert issues
```

---

## Legal & Ethical Notice

**OFSPRO** is developed exclusively for authorized penetration testing, Red Team engagements with signed Rules of Engagement (RoE), academic security research, and competitive CTF events (HackTheBox, TryHackMe, Vulnlab).

Users are solely responsible for ensuring compliance with applicable laws, institutional policies, and terms of service. The author assumes no liability for unauthorized or misuse of this software.

---

<div align="center">

**Developed with precision by [@uzii2208](https://github.com/uzii2208)**  
*Part of the mcp2agy offensive research ecosystem.*

</div>
