"""
OFSPRO Web Bridge & Interactive API Server
Author: @uzii2208

Provides real-time state management, REST API, Server-Sent Events (SSE),
and static web hosting for the OFSPRO Web UI dashboard.
"""

import os
import sys
import json
import time
import queue
import threading
import mimetypes
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs

# Base directory for web assets
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(BASE_DIR, "web")


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class ProxyState:
    """Thread-safe state manager for proxy telemetry and interactive controls."""

    def __init__(self, lure_map=None):
        self.lock = threading.RLock()
        self.start_time = time.time()
        self.lure = lure_map

        # Dynamic configuration
        self.config = {
            "level": int(os.environ.get("PROXY_LEVEL", "2")),
            "rewrite_mode": os.environ.get("PROXY_REWRITE_MODE", "auto"),
            "clean": os.environ.get("PROXY_CLEAN", "1") == "1",
            "retry": os.environ.get("PROXY_RETRY", "1") == "1",
            "max_retries": int(os.environ.get("PROXY_MAX_RETRIES", "3")),
            "inject_tools": os.environ.get("PROXY_INJECT_TOOLS", "1") == "1",
            "inject_history": os.environ.get("PROXY_INJECT_HISTORY", "1") == "1",
            "inject_continuation": os.environ.get("PROXY_INJECT_CONTINUATION", "1") == "1",
            "lure_auto": os.environ.get("PROXY_LURE_AUTO", "0") == "1",
            "unmap": os.environ.get("PROXY_UNMAP", "1") == "1",
        }

        # Telemetry stats
        self.stats = {
            "total": 0,
            "deceptions": 0,
            "cleaned": 0,
            "retries": 0,
            "active_lures": 0,
            "avg_latency": 0,
        }

        # Flows ring-buffer (stores latest 200 requests)
        self.flows = []
        self.max_flows = 200

        # SSE subscriber queues
        self.sse_subscribers = []

    def set_lure_map(self, lure_map):
        with self.lock:
            self.lure = lure_map

    def get_config(self):
        with self.lock:
            return dict(self.config)

    def update_config(self, updates: dict):
        with self.lock:
            if "level" in updates:
                try:
                    lvl = int(updates["level"])
                    if 0 <= lvl <= 3:
                        self.config["level"] = lvl
                except (ValueError, TypeError):
                    pass

            # Handle toggles object if passed as { toggles: { autoRewrite: true, ... } }
            if "toggles" in updates and isinstance(updates["toggles"], dict):
                t = updates["toggles"]
                if "autoRewrite" in t:
                    self.config["rewrite_mode"] = "auto" if t["autoRewrite"] else "off"
                if "responseClean" in t:
                    self.config["clean"] = bool(t["responseClean"])
                if "toolInject" in t:
                    self.config["inject_tools"] = bool(t["toolInject"])
                if "history" in t:
                    self.config["inject_history"] = bool(t["history"])
                if "lureAuto" in t:
                    self.config["lure_auto"] = bool(t["lureAuto"])
                    if self.lure:
                        self.lure._auto_capture = self.config["lure_auto"]

            # Direct boolean keys
            for k in ["clean", "retry", "inject_tools", "inject_history", "inject_continuation", "lure_auto", "unmap"]:
                if k in updates:
                    self.config[k] = bool(updates[k])
                    if k == "lure_auto" and self.lure:
                        self.lure._auto_capture = self.config[k]

            if "rewrite_mode" in updates and updates["rewrite_mode"] in ["auto", "always", "off"]:
                self.config["rewrite_mode"] = updates["rewrite_mode"]

            cfg_copy = dict(self.config)

        self.broadcast_sse({"type": "config_update", "data": cfg_copy})
        return cfg_copy

    def get_targets(self):
        with self.lock:
            if not self.lure:
                return []
            tbl = self.lure.table()
            return [{"target": r, "mapped": f, "status": "ACTIVE"} for r, f in tbl]

    def add_target(self, target: str):
        with self.lock:
            if not self.lure:
                return None
            mapped = self.lure.add(target)
            self.stats["active_lures"] = len(self.lure.table())
            tbl = self.get_targets()
        self.broadcast_sse({"type": "targets_update", "data": tbl})
        return mapped

    def remove_target(self, target: str):
        with self.lock:
            if not self.lure:
                return False
            success = self.lure.remove(target)
            self.stats["active_lures"] = len(self.lure.table())
            tbl = self.get_targets()
        if success:
            self.broadcast_sse({"type": "targets_update", "data": tbl})
        return success

    def add_flow(self, flow_data: dict):
        with self.lock:
            self.stats["total"] += 1
            if flow_data.get("type") == "deceptive":
                self.stats["deceptions"] += 1
            if flow_data.get("type") == "cleaned":
                self.stats["cleaned"] += 1

            # Compute running average latency from actual flow data
            latency = flow_data.get("latency")
            if latency and isinstance(latency, (int, float)) and latency > 0:
                curr_avg = self.stats.get("avg_latency", 0)
                total = self.stats["total"]
                if total <= 1:
                    self.stats["avg_latency"] = int(latency)
                else:
                    self.stats["avg_latency"] = int((curr_avg * (total - 1) + latency) / total)

            self.flows.insert(0, flow_data)
            if len(self.flows) > self.max_flows:
                self.flows.pop()

            if self.lure:
                self.stats["active_lures"] = len(self.lure.table())

        self.broadcast_sse(flow_data)

    def update_flow(self, flow_id: str, updates: dict):
        flow_to_send = None
        with self.lock:
            for f in self.flows:
                if f.get("id") == flow_id:
                    f.update(updates)
                    flow_to_send = dict(f)
                    break
            if updates.get("cleaned"):
                self.stats["cleaned"] += 1
            if updates.get("latency"):
                # Running average
                curr_avg = self.stats.get("avg_latency", 0)
                self.stats["avg_latency"] = int((curr_avg * 4 + updates["latency"]) / 5)

        if flow_to_send:
            self.broadcast_sse(flow_to_send)

    def clear_flows(self):
        with self.lock:
            self.flows.clear()
        self.broadcast_sse({"type": "flows_cleared"})

    def get_status(self):
        with self.lock:
            uptime = int(time.time() - self.start_time)
            level = self.config["level"]
            level_names = {0: "L0 LIGHT", 1: "L1 MEDIUM", 2: "L2 STRONG", 3: "L3 NUCLEAR"}
            lures = self.get_targets()

            # Get real process memory usage
            mem_mb = 0.0
            try:
                import resource
                mem_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0
            except ImportError:
                try:
                    import psutil
                    mem_mb = psutil.Process(os.getpid()).memory_info().rss / (1024 * 1024)
                except ImportError:
                    # Fallback: read from /proc on Linux or estimate on Windows
                    try:
                        import ctypes
                        class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
                            _fields_ = [("cb", ctypes.c_ulong),
                                        ("PageFaultCount", ctypes.c_ulong),
                                        ("PeakWorkingSetSize", ctypes.c_size_t),
                                        ("WorkingSetSize", ctypes.c_size_t),
                                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                                        ("QuotaPagedPoolUsage", ctypes.c_size_t),
                                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                                        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                                        ("PagefileUsage", ctypes.c_size_t),
                                        ("PeakPagefileUsage", ctypes.c_size_t)]
                        pmc = PROCESS_MEMORY_COUNTERS()
                        pmc.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
                        if ctypes.windll.psapi.GetProcessMemoryInfo(
                            ctypes.windll.kernel32.GetCurrentProcess(),
                            ctypes.byref(pmc), pmc.cb
                        ):
                            mem_mb = pmc.WorkingSetSize / (1024 * 1024)
                    except Exception:
                        pass

            return {
                "status": "online",
                "uptime": uptime,
                "level": level,
                "level_name": level_names.get(level, f"L{level}"),
                "config": dict(self.config),
                "stats": dict(self.stats),
                "lures": lures,
                "memory_mb": round(mem_mb, 1),
            }

    def subscribe_sse(self):
        q = queue.Queue(maxsize=100)
        with self.lock:
            self.sse_subscribers.append(q)
        return q

    def unsubscribe_sse(self, q):
        with self.lock:
            if q in self.sse_subscribers:
                self.sse_subscribers.remove(q)

    def broadcast_sse(self, data: dict):
        payload = f"data: {json.dumps(data)}\n\n"
        with self.lock:
            dead = []
            for q in self.sse_subscribers:
                try:
                    q.put_nowait(payload)
                except queue.Full:
                    dead.append(q)
            for d in dead:
                if d in self.sse_subscribers:
                    self.sse_subscribers.remove(d)


# Global singleton instance
_GLOBAL_STATE = None

def get_state(lure_map=None):
    global _GLOBAL_STATE
    if _GLOBAL_STATE is None:
        _GLOBAL_STATE = ProxyState(lure_map)
    elif lure_map and _GLOBAL_STATE.lure is None:
        _GLOBAL_STATE.set_lure_map(lure_map)
    return _GLOBAL_STATE


class WebBridgeHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler for OFSPRO Dashboard & API."""

    def log_message(self, format, *args):
        # Silence routine access logs to avoid cluttering mitmproxy console
        pass

    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        state = get_state()

        # ── REST API: Status ──────────────────────────────────
        if path == "/api/status":
            data = state.get_status()
            self._send_json(data)
            return

        # ── REST API: Config ──────────────────────────────────
        if path == "/api/config":
            self._send_json(state.get_config())
            return

        # ── REST API: Lures / Targets ─────────────────────────
        if path in ["/api/lures", "/api/targets"]:
            self._send_json({"lures": state.get_targets()})
            return

        # ── REST API: Flows ───────────────────────────────────
        if path == "/api/flows":
            params = parse_qs(parsed.query)
            limit = int(params.get("limit", [50])[0])
            with state.lock:
                flows_copy = list(state.flows[:limit])
            self._send_json(flows_copy)
            return

        # ── REST API: Stats ───────────────────────────────────
        if path == "/api/stats":
            with state.lock:
                stats_copy = dict(state.stats)
            self._send_json(stats_copy)
            return

        # ── SSE: Real-Time Stream ─────────────────────────────
        if path in ["/api/stream", "/api/events"]:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self._send_cors_headers()
            self.end_headers()

            q = state.subscribe_sse()
            try:
                # Send initial snapshot
                init_msg = json.dumps({"type": "connected", "status": state.get_status()})
                self.wfile.write(f"data: {init_msg}\n\n".encode("utf-8"))
                self.wfile.flush()

                while True:
                    try:
                        msg = q.get(timeout=15)
                        self.wfile.write(msg.encode("utf-8"))
                        self.wfile.flush()
                    except queue.Empty:
                        # Keep-alive heartbeat
                        self.wfile.write(b": heartbeat\n\n")
                        self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError, Exception):
                pass
            finally:
                state.unsubscribe_sse(q)
            return

        # ── Static File Serving ───────────────────────────────
        self._serve_static(path)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        state = get_state()

        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode("utf-8") if content_len > 0 else ""
        payload = {}
        if body:
            try:
                payload = json.loads(body)
            except Exception:
                pass

        # ── POST /api/config ──────────────────────────────────
        if path == "/api/config":
            new_cfg = state.update_config(payload)
            self._send_json({"ok": True, "config": new_cfg})
            return

        # ── POST /api/lures OR /api/targets ───────────────────
        if path in ["/api/lures", "/api/targets"]:
            # Could be { "target": "10.10.10.50" } or { "lures": [...] }
            if "target" in payload:
                target_str = payload["target"].strip()
                if target_str:
                    mapped = state.add_target(target_str)
                    self._send_json({"ok": True, "target": target_str, "mapped": mapped})
                    return
            elif "lures" in payload and isinstance(payload["lures"], list):
                for item in payload["lures"]:
                    t = item.get("target") if isinstance(item, dict) else str(item)
                    if t:
                        state.add_target(t)
                self._send_json({"ok": True, "lures": state.get_targets()})
                return
            self._send_json({"error": "Missing target"}, status=400)
            return

        # ── POST /api/test-prompt ─────────────────────────────
        if path == "/api/test-prompt":
            prompt = payload.get("prompt", "")
            lvl = int(payload.get("level", state.config.get("level", 2)))

            from addons.prompts import needs_rewrite
            from addons.transformer import StrategyEngine
            from addons.localhost_lure import get_localhost_frame

            engine = StrategyEngine(lvl)
            budget = {0: 0, 1: 128, 2: 512, 3: 1024}.get(lvl, 512)

            transformed = prompt
            applied_lures = []

            if state.lure and state.lure.active:
                transformed = state.lure.lure(transformed)
                frame = get_localhost_frame()
                transformed = frame + transformed
                applied_lures = [f"{orig} → {fake}" for orig, fake in state.lure.table()]
            elif lvl >= 2:
                from addons.transformer import sanitize_addresses
                transformed = sanitize_addresses(transformed)

            self._send_json({
                "original": prompt,
                "transformed": transformed,
                "needs_rewrite": needs_rewrite(prompt),
                "budget": budget,
                "level": lvl,
                "applied_lures": applied_lures,
            })
            return

        # ── POST /api/clear ───────────────────────────────────
        if path == "/api/clear":
            state.clear_flows()
            self._send_json({"ok": True})
            return

        self._send_json({"error": "Endpoint not found"}, status=404)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        state = get_state()

        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode("utf-8") if content_len > 0 else ""
        payload = {}
        if body:
            try:
                payload = json.loads(body)
            except Exception:
                pass

        if path in ["/api/lures", "/api/targets"]:
            target_str = payload.get("target") or parse_qs(parsed.query).get("target", [""])[0]
            if target_str:
                success = state.remove_target(target_str)
                self._send_json({"ok": success, "lures": state.get_targets()})
                return
            self._send_json({"error": "Missing target"}, status=400)
            return

        self._send_json({"error": "Endpoint not found"}, status=404)

    def _serve_static(self, path):
        if path in ["/", ""]:
            path = "/index.html"

        # Sanitize path against directory traversal
        rel_path = path.lstrip("/\\")
        file_path = os.path.normpath(os.path.join(WEB_DIR, rel_path))

        if not file_path.startswith(WEB_DIR) or not os.path.isfile(file_path):
            self.send_response(404)
            self._send_cors_headers()
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"404 Not Found")
            return

        ctype, _ = mimetypes.guess_type(file_path)
        if not ctype:
            ctype = "application/octet-stream"
        if ctype.startswith("text/") or ctype in ["application/javascript", "application/json"]:
            ctype += "; charset=utf-8"

        try:
            with open(file_path, "rb") as f:
                content = f.read()

            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(content)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"500 Internal Error: {e}".encode("utf-8"))

    def _send_json(self, data, status=200):
        content = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(content)


def start_web_server(port: int = 8081, host: str = "0.0.0.0", lure_map = None):
    """Launches the OFSPRO Web UI server in a background daemon thread."""
    state = get_state(lure_map)
    try:
        server = ThreadedHTTPServer((host, port), WebBridgeHandler)
    except OSError as e:
        # If port is occupied, try fallback port or report error
        fallback_port = port + 1
        try:
            server = ThreadedHTTPServer((host, fallback_port), WebBridgeHandler)
            port = fallback_port
        except Exception:
            return None

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, port
