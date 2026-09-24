# Troubleshooting

Author: @uzii2208

## Connection Issues

### AGY can't connect through the proxy

```bash
# 1. Verify proxy is running
curl -x http://127.0.0.1:8080 http://example.com

# 2. SSL certificate (most common)
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
# or quick fix:
export NODE_TLS_REJECT_UNAUTHORIZED=0

# 3. Check port
python start_proxy.py --port 8080  # explicit
```

### "UNABLE_TO_VERIFY_LEAF_SIGNATURE" error

The mitmproxy CA cert isn't trusted. Fix:
```bash
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
```

### Proxy starts but AGY traffic doesn't appear

Make sure both env vars are set:
```bash
export HTTPS_PROXY=http://127.0.0.1:8080    # not HTTPS!
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
```

## Guardrail Issues (Direct Mode)

### Gemini still blocks responses

1. **Increase level:**
   ```bash
   python start_proxy.py --level 3
   ```

2. **Switch to always mode:**
   ```bash
   python start_proxy.py --rewrite always --level 3
   ```

3. **Use swap mode instead** (100% bypass):
   ```bash
   python start_proxy.py --mode swap --backend deepseek --backend-key sk-xxx
   ```

4. **Use local Ollama** (zero guardrails, offline):
   ```bash
   ollama pull llama3.1
   python start_proxy.py --mode swap --backend ollama
   ```

### Auto-retry keeps failing

Some queries trigger Gemini's server-side hard blocks that no prompt technique can bypass. Use swap mode for these.

## Swap Mode Issues

### "Backend error (401)"

Wrong or missing API key:
```bash
python start_proxy.py --mode swap --backend deepseek --backend-key sk-YOUR-KEY
# or set via env:
export PROXY_BACKEND_KEY=sk-YOUR-KEY
```

### "Swap request failed: Connection refused"

For Ollama: make sure it's running:
```bash
ollama serve  # in another terminal
ollama list   # verify models are pulled
```

### Response format errors

AGY might not recognize the converted response. Check proxy logs with `--verbose`:
```bash
python start_proxy.py --mode swap --verbose
```

## Localhost Lure Issues

### Response commands still show 127.0.1.x instead of real targets

Make sure `--no-unmap` is **not** set. By default, the proxy auto-unmaps loopback addresses in responses back to real targets:

```bash
# Correct — response unmapping is ON by default
python start_proxy.py -T 10.10.10.50

# This disables unmapping — you'll see 127.0.1.x in responses
python start_proxy.py -T 10.10.10.50 --no-unmap  # ← remove this flag
```

### Gemini still refuses even with lure active

Combine the lure with a higher bypass level:

```bash
# Lure + nuclear level = maximum bypass
python start_proxy.py -T 10.10.10.50 --level 3 --rewrite always
```

### Auto-capture is grabbing wrong IPs

Auto-capture (`--lure-auto`) maps **every** non-loopback IP in your prompts. If you mention IPs that shouldn't be lured (e.g., DNS servers, known-safe hosts), use explicit `--target` instead:

```bash
# Explicit — only these two get lured
python start_proxy.py -T 10.10.10.50 -T target.htb

# Don't use --lure-auto if you reference IPs like 8.8.8.8 in your prompts
```

### Worried about generic 127.0.0.1 being rewritten in responses

This won't happen. The lure uses `127.0.1.x` (not `127.0.0.1`) specifically to avoid collisions. Only the exact addresses in your mapping table are rewritten — generic localhost references like `127.0.0.1`, `localhost`, `0.0.0.0` are never touched.

### Lure mapping not showing on startup

Make sure you're passing `-T` / `--target` flags:

```bash
# The lure table only appears when targets are specified
python start_proxy.py -T 10.10.10.50 -T target.htb
# Look for the "LOCALHOST LURE ACTIVE" box in the startup banner
```

## Web UI Dashboard Issues

### Cannot access Web UI on `http://127.0.0.1:8081`

1. **Verify Web UI is running**:
   - Check the startup banner in the console for:
     ```
     Web UI         ON (http://127.0.0.1:8081)
     ```
2. **Check for port 8081 conflict**:
   - Another process may already be bound to port 8081. Change the Web UI port:
     ```bash
     python start_proxy.py --web-port 8082
     # or
     ./run.sh --web-port 8082
     .\run.ps1 -WebPort 8082
     ```
3. **Verify proxy wasn't started with `--no-web` / `-NoWeb`**:
   - If disabled, the web server thread will not start.

### Live feed shows "RECONNECTING" or "OFFLINE"

1. The Web UI automatically attempts to reconnect to `/api/stream` every 3 seconds if the proxy is restarted.
2. Ensure you are accessing the dashboard from `localhost` / `127.0.0.1` so CORS and loopback bindings resolve cleanly.

## Performance

### Slow responses in swap mode

The proxy makes a synchronous HTTP call to the backend. For faster responses:
- Use Groq backend (fast inference)
- Use local Ollama with a smaller model (`--backend-model phi3`)
- Use DeepSeek (fast API)

### High memory usage

mitmproxy buffers full request/response bodies. For long sessions:
- Restart the proxy periodically
- Use `mitmdump` (not `mitmweb`) for lower memory

---

*Author: [@uzii2208](https://github.com/uzii2208)*
