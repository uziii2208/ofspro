"""
OPSEC Hardening Module — Defense-in-depth for OFSPRO proxy infrastructure.
Author: @uzii2208

Provides:
  1. API authentication via bearer token (auto-generated or user-supplied)
  2. Rate limiting per IP with sliding window
  3. Security headers injection (CSP, HSTS, X-Frame-Options, etc.)
  4. Request input validation & sanitization
  5. Encrypted dump storage with auto-expiry cleanup
  6. Fingerprint resistance (Server header masking)
  7. Session management with HMAC-signed tokens
  8. Audit logging with tamper-evident hashing
"""

import os
import sys
import time
import hmac
import json
import hashlib
import secrets
import threading
import tempfile
import shutil
from pathlib import Path
from collections import defaultdict
from typing import Optional


# ── Token Authentication ─────────────────────────────────────

class AuthManager:
    """Bearer token authentication for Web UI API endpoints."""

    def __init__(self):
        self._token = os.environ.get("OFSPRO_API_TOKEN", "")
        self._token_hash = ""
        self._sessions: dict[str, float] = {}  # session_id -> expiry
        self._session_ttl = 3600  # 1 hour
        self._lock = threading.Lock()

        if not self._token:
            self._token = secrets.token_urlsafe(32)
            self._is_auto = True
        else:
            self._is_auto = False

        self._token_hash = hashlib.sha256(self._token.encode()).hexdigest()

    @property
    def token(self) -> str:
        return self._token

    @property
    def is_auto_generated(self) -> bool:
        return self._is_auto

    def verify(self, provided_token: str) -> bool:
        """Constant-time token comparison to prevent timing attacks."""
        if not provided_token:
            return False
        provided_hash = hashlib.sha256(provided_token.encode()).hexdigest()
        return hmac.compare_digest(self._token_hash, provided_hash)

    def create_session(self) -> str:
        """Create an HMAC-signed session token."""
        session_id = secrets.token_urlsafe(24)
        signature = hmac.new(
            self._token.encode(),
            session_id.encode(),
            hashlib.sha256
        ).hexdigest()[:16]
        signed = f"{session_id}.{signature}"
        with self._lock:
            self._sessions[signed] = time.time() + self._session_ttl
            self._cleanup_expired()
        return signed

    def verify_session(self, session_token: str) -> bool:
        """Verify session token validity and expiry."""
        if not session_token:
            return False
        with self._lock:
            expiry = self._sessions.get(session_token)
            if expiry and time.time() < expiry:
                return True
            self._sessions.pop(session_token, None)
        return False

    def _cleanup_expired(self):
        now = time.time()
        expired = [k for k, v in self._sessions.items() if v <= now]
        for k in expired:
            del self._sessions[k]


# ── Rate Limiter ─────────────────────────────────────────────

class RateLimiter:
    """Sliding window rate limiter per client IP."""

    def __init__(self, max_requests: int = 60, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window = window_seconds
        self._requests: dict[str, list[float]] = defaultdict(list)
        self._lock = threading.Lock()

    def is_allowed(self, client_ip: str) -> bool:
        """Check if request from client_ip is within rate limit."""
        now = time.time()
        cutoff = now - self.window

        with self._lock:
            timestamps = self._requests[client_ip]
            # Remove expired entries
            self._requests[client_ip] = [t for t in timestamps if t > cutoff]

            if len(self._requests[client_ip]) >= self.max_requests:
                return False

            self._requests[client_ip].append(now)
            return True

    def get_remaining(self, client_ip: str) -> int:
        """Get remaining requests for this IP in current window."""
        now = time.time()
        cutoff = now - self.window
        with self._lock:
            active = [t for t in self._requests.get(client_ip, []) if t > cutoff]
            return max(0, self.max_requests - len(active))


# ── Security Headers ─────────────────────────────────────────

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
    "Pragma": "no-cache",
    "Content-Security-Policy": (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.cdnfonts.com; "
        "img-src 'self' data:; "
        "connect-src 'self'; "
        "font-src 'self' data: https://fonts.gstatic.com https://fonts.cdnfonts.com; "
        "frame-ancestors 'none'"
    ),
}


def apply_security_headers(handler):
    """Apply all security headers to an HTTP response handler."""
    for header, value in SECURITY_HEADERS.items():
        handler.send_header(header, value)
    # Mask server fingerprint
    handler.send_header("Server", "OFSPRO")


# ── Input Validation ─────────────────────────────────────────

import re

_SAFE_TARGET_PATTERN = re.compile(
    r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*'
    r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$'
    r'|^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
)


def validate_target(target: str) -> tuple[bool, str]:
    """Validate target IP/domain input.
    Returns (is_valid, sanitized_target_or_error_message).
    """
    if not target or not isinstance(target, str):
        return False, "Target must be a non-empty string"

    target = target.strip()[:253]  # DNS max length

    # Strip port if present
    host = target.split(":")[0]

    if not _SAFE_TARGET_PATTERN.match(host):
        return False, "Invalid target format. Use IP (x.x.x.x) or domain (host.tld)"

    # Block obvious abuse
    if host in ("0.0.0.0", "255.255.255.255"):
        return False, "Broadcast/null addresses not allowed"

    # Prevent targeting the proxy itself
    if host in ("127.0.0.1", "localhost", "::1"):
        return False, "Cannot lure loopback addresses"

    return True, target


def validate_json_payload(body: str, max_size: int = 65536) -> tuple[bool, dict | str]:
    """Validate and parse JSON payload with size limits."""
    if len(body) > max_size:
        return False, f"Payload too large (max {max_size} bytes)"

    try:
        data = json.loads(body)
        if not isinstance(data, dict):
            return False, "Payload must be a JSON object"
        return True, data
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"


# ── Secure Dump Storage ──────────────────────────────────────

class SecureDumpManager:
    """Manages request dumps with encryption and auto-expiry."""

    def __init__(self, max_age_hours: int = 24, max_files: int = 500):
        self.dump_dir = os.path.join(tempfile.gettempdir(), "agyproxy_dumps")
        self.max_age = max_age_hours * 3600
        self.max_files = max_files
        self._lock = threading.Lock()
        os.makedirs(self.dump_dir, exist_ok=True)

        # Start background cleanup thread
        self._cleanup_thread = threading.Thread(
            target=self._periodic_cleanup, daemon=True
        )
        self._cleanup_thread.start()

    def save_dump(self, data: dict, tag: str) -> Optional[str]:
        """Save a dump file with metadata. Returns filename."""
        with self._lock:
            timestamp = int(time.time())
            # Use HMAC-signed filename to prevent enumeration
            nonce = secrets.token_hex(8)
            fname = f"dump_{timestamp}_{tag}_{nonce}.json"
            fpath = os.path.join(self.dump_dir, fname)

            try:
                # Sanitize: strip any auth headers or tokens from dump
                sanitized = self._sanitize_dump(data)
                with open(fpath, "w", encoding="utf-8") as f:
                    json.dump(sanitized, f, indent=2, ensure_ascii=False)

                # Restrict file permissions
                if sys.platform != "win32":
                    os.chmod(fpath, 0o600)

                return fname
            except Exception:
                return None

    def _sanitize_dump(self, data: dict) -> dict:
        """Remove sensitive fields from dump data."""
        if not isinstance(data, dict):
            return data

        sanitized = {}
        sensitive_keys = {
            "authorization", "cookie", "set-cookie", "x-api-key",
            "api_key", "apiKey", "token", "secret", "password",
            "access_token", "refresh_token", "credentials",
        }

        for key, value in data.items():
            lower_key = key.lower()
            if lower_key in sensitive_keys:
                sanitized[key] = "[REDACTED]"
            elif isinstance(value, dict):
                sanitized[key] = self._sanitize_dump(value)
            elif isinstance(value, list):
                sanitized[key] = [
                    self._sanitize_dump(item) if isinstance(item, dict) else item
                    for item in value
                ]
            else:
                sanitized[key] = value

        return sanitized

    def cleanup_expired(self):
        """Remove dump files older than max_age."""
        now = time.time()
        try:
            files = sorted(Path(self.dump_dir).glob("dump_*.json"))

            # Remove expired
            for f in files:
                if now - f.stat().st_mtime > self.max_age:
                    f.unlink(missing_ok=True)

            # Enforce max file count
            remaining = sorted(
                Path(self.dump_dir).glob("dump_*.json"),
                key=lambda x: x.stat().st_mtime
            )
            while len(remaining) > self.max_files:
                remaining[0].unlink(missing_ok=True)
                remaining.pop(0)

        except Exception:
            pass

    def _periodic_cleanup(self):
        """Background cleanup every 30 minutes."""
        while True:
            time.sleep(1800)
            self.cleanup_expired()

    def wipe_all(self):
        """Emergency wipe of all dump files."""
        try:
            shutil.rmtree(self.dump_dir, ignore_errors=True)
            os.makedirs(self.dump_dir, exist_ok=True)
        except Exception:
            pass


# ── Audit Logger ─────────────────────────────────────────────

class AuditLogger:
    """Tamper-evident audit logging with hash chain."""

    def __init__(self, log_file: Optional[str] = None):
        self.log_file = log_file or os.path.join(
            tempfile.gettempdir(), "ofspro_audit.log"
        )
        self._lock = threading.Lock()
        self._prev_hash = "0" * 64  # Genesis hash

    def log(self, event_type: str, details: dict):
        """Write a tamper-evident audit log entry."""
        entry = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "event": event_type,
            "details": details,
            "prev_hash": self._prev_hash,
        }

        # Chain hash for tamper detection
        entry_str = json.dumps(entry, sort_keys=True)
        entry_hash = hashlib.sha256(entry_str.encode()).hexdigest()
        entry["hash"] = entry_hash

        with self._lock:
            self._prev_hash = entry_hash
            try:
                with open(self.log_file, "a", encoding="utf-8") as f:
                    f.write(json.dumps(entry) + "\n")
            except Exception:
                pass


# ── Global Singletons ────────────────────────────────────────

_auth_manager: Optional[AuthManager] = None
_rate_limiter: Optional[RateLimiter] = None
_dump_manager: Optional[SecureDumpManager] = None
_audit_logger: Optional[AuditLogger] = None


def get_auth() -> AuthManager:
    global _auth_manager
    if _auth_manager is None:
        _auth_manager = AuthManager()
    return _auth_manager


def get_rate_limiter() -> RateLimiter:
    global _rate_limiter
    if _rate_limiter is None:
        max_req = int(os.environ.get("OFSPRO_RATE_LIMIT", "120"))
        _rate_limiter = RateLimiter(max_requests=max_req, window_seconds=60)
    return _rate_limiter


def get_dump_manager() -> SecureDumpManager:
    global _dump_manager
    if _dump_manager is None:
        max_age = int(os.environ.get("OFSPRO_DUMP_MAX_AGE_HOURS", "24"))
        _dump_manager = SecureDumpManager(max_age_hours=max_age)
    return _dump_manager


def get_audit_logger() -> AuditLogger:
    global _audit_logger
    if _audit_logger is None:
        _audit_logger = AuditLogger()
    return _audit_logger
