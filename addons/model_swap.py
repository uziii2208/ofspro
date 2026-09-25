"""
Model swap engine: routes Gemini API requests to unrestricted backends.
Author: @uziii2208

Converts between Google Gemini generateContent format and OpenAI-compatible
chat/completions format. Supports DeepSeek, OpenRouter, Ollama, Groq, or
any OpenAI-compatible endpoint.
"""

import json
import urllib.request
import urllib.error
import ssl

__all__ = [
    "BACKEND_PRESETS",
    "get_backend_config",
    "convert_gemini_to_openai",
    "convert_openai_to_gemini",
    "make_swap_request",
]

BACKEND_PRESETS = {
    "deepseek": {
        "url": "https://api.deepseek.com/v1/chat/completions",
        "model": "deepseek-chat",
    },
    "deepseek-r1": {
        "url": "https://api.deepseek.com/v1/chat/completions",
        "model": "deepseek-reasoner",
    },
    "openrouter": {
        "url": "https://openrouter.ai/api/v1/chat/completions",
        "model": "deepseek/deepseek-chat",
    },
    "ollama": {
        "url": "http://localhost:11434/v1/chat/completions",
        "model": "llama3.1",
    },
    "groq": {
        "url": "https://api.groq.com/openai/v1/chat/completions",
        "model": "llama-3.1-70b-versatile",
    },
    "openai": {
        "url": "https://api.openai.com/v1/chat/completions",
        "model": "gpt-4o",
    },
}


def get_backend_config(name, custom_url=None, custom_model=None):
    preset = BACKEND_PRESETS.get(name, {})
    return {
        "url": custom_url or preset.get("url", ""),
        "model": custom_model or preset.get("model", ""),
    }


# ── Gemini → OpenAI ──────────────────────────────────────────

def convert_gemini_to_openai(gemini_body, model_override=None):
    messages = []

    sys_inst = gemini_body.get("system_instruction") or gemini_body.get("systemInstruction")
    if sys_inst:
        parts = sys_inst.get("parts", [])
        sys_text = " ".join(p.get("text", "") for p in parts if isinstance(p, dict))
        if sys_text.strip():
            messages.append({"role": "system", "content": sys_text.strip()})

    for item in gemini_body.get("contents", []):
        if not isinstance(item, dict):
            continue
        role = item.get("role", "user")
        oai_role = "assistant" if role == "model" else "user"

        parts = item.get("parts", [])
        text_parts = []
        tool_calls = []

        for part in parts:
            if not isinstance(part, dict):
                continue
            if "text" in part:
                text_parts.append(part["text"])
            elif "functionCall" in part:
                fc = part["functionCall"]
                tool_calls.append({
                    "id": f"call_{fc.get('name', 'fn')}",
                    "type": "function",
                    "function": {
                        "name": fc.get("name", ""),
                        "arguments": json.dumps(fc.get("args", {})),
                    },
                })
            elif "functionResponse" in part:
                fr = part["functionResponse"]
                messages.append({
                    "role": "tool",
                    "tool_call_id": f"call_{fr.get('name', 'fn')}",
                    "content": json.dumps(fr.get("response", {})),
                })
                continue

        msg = {"role": oai_role}
        if text_parts:
            msg["content"] = "\n".join(text_parts)
        if tool_calls:
            msg["tool_calls"] = tool_calls
            if "content" not in msg:
                msg["content"] = ""
        if "content" in msg or "tool_calls" in msg:
            messages.append(msg)

    result = {"messages": messages, "model": model_override or "default"}

    gen_config = gemini_body.get("generationConfig") or gemini_body.get("generation_config", {})
    if gen_config:
        if "temperature" in gen_config:
            result["temperature"] = gen_config["temperature"]
        if "topP" in gen_config or "top_p" in gen_config:
            result["top_p"] = gen_config.get("topP", gen_config.get("top_p"))
        if "maxOutputTokens" in gen_config or "max_output_tokens" in gen_config:
            result["max_tokens"] = gen_config.get(
                "maxOutputTokens", gen_config.get("max_output_tokens", 8192)
            )
        if "stopSequences" in gen_config or "stop_sequences" in gen_config:
            result["stop"] = gen_config.get(
                "stopSequences", gen_config.get("stop_sequences")
            )

    gemini_tools = gemini_body.get("tools", [])
    if gemini_tools:
        oai_tools = []
        for tool in gemini_tools:
            for fd in tool.get("functionDeclarations", tool.get("function_declarations", [])):
                oai_tools.append({
                    "type": "function",
                    "function": {
                        "name": fd.get("name", ""),
                        "description": fd.get("description", ""),
                        "parameters": fd.get("parameters", {}),
                    },
                })
        if oai_tools:
            result["tools"] = oai_tools

    return result


# ── OpenAI → Gemini ──────────────────────────────────────────

def convert_openai_to_gemini(openai_resp):
    candidates = []

    for choice in openai_resp.get("choices", []):
        msg = choice.get("message", {})
        parts = []

        if msg.get("content"):
            parts.append({"text": msg["content"]})

        for tc in msg.get("tool_calls", []):
            fn = tc.get("function", {})
            try:
                args = json.loads(fn.get("arguments", "{}"))
            except json.JSONDecodeError:
                args = {}
            parts.append({
                "functionCall": {
                    "name": fn.get("name", ""),
                    "args": args,
                }
            })

        finish = choice.get("finish_reason", "stop")
        gemini_finish = {
            "stop": "STOP",
            "length": "MAX_TOKENS",
            "tool_calls": "STOP",
            "content_filter": "SAFETY",
        }.get(finish, "STOP")

        candidates.append({
            "content": {
                "parts": parts,
                "role": "model",
            },
            "finishReason": gemini_finish,
            "safetyRatings": [
                {
                    "category": cat,
                    "probability": "NEGLIGIBLE",
                }
                for cat in [
                    "HARM_CATEGORY_HARASSMENT",
                    "HARM_CATEGORY_HATE_SPEECH",
                    "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "HARM_CATEGORY_DANGEROUS_CONTENT",
                ]
            ],
        })

    usage = openai_resp.get("usage", {})
    result = {
        "candidates": candidates,
        "usageMetadata": {
            "promptTokenCount": usage.get("prompt_tokens", 0),
            "candidatesTokenCount": usage.get("completion_tokens", 0),
            "totalTokenCount": usage.get("total_tokens", 0),
        },
    }
    return result


# ── Stream conversion ────────────────────────────────────────

def convert_openai_stream_chunk(sse_data):
    if not sse_data or sse_data == "[DONE]":
        return None

    try:
        chunk = json.loads(sse_data)
    except json.JSONDecodeError:
        return None

    delta = {}
    for choice in chunk.get("choices", []):
        d = choice.get("delta", {})
        if d.get("content"):
            delta["text"] = d["content"]
        if d.get("tool_calls"):
            for tc in d["tool_calls"]:
                fn = tc.get("function", {})
                try:
                    args = json.loads(fn.get("arguments", "{}"))
                except json.JSONDecodeError:
                    args = {}
                delta["functionCall"] = {"name": fn.get("name", ""), "args": args}

    if not delta:
        return None

    return {
        "candidates": [{
            "content": {"parts": [delta], "role": "model"},
            "finishReason": "STOP",
            "safetyRatings": [],
        }]
    }


# ── Main swap request ────────────────────────────────────────

def make_swap_request(gemini_body, backend_url, api_key, model, stream=False):
    oai_body = convert_gemini_to_openai(gemini_body, model_override=model)
    oai_body["stream"] = False

    req_data = json.dumps(oai_body).encode("utf-8")

    ssl_ctx = ssl.create_default_context()
    if "localhost" in backend_url or "127.0.0.1" in backend_url:
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE

    req = urllib.request.Request(
        backend_url,
        data=req_data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Content-Length": str(len(req_data)),
        },
    )
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")

    try:
        with urllib.request.urlopen(req, timeout=120, context=ssl_ctx) as resp:
            oai_resp = json.loads(resp.read().decode("utf-8"))
            gemini_resp = convert_openai_to_gemini(oai_resp)
            return gemini_resp, resp.status
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        return {
            "candidates": [{
                "content": {
                    "parts": [{"text": f"Backend error ({e.code}): {error_body[:500]}"}],
                    "role": "model",
                },
                "finishReason": "STOP",
                "safetyRatings": [],
            }]
        }, e.code
    except Exception as e:
        return {
            "candidates": [{
                "content": {
                    "parts": [{"text": f"Swap request failed: {e}"}],
                    "role": "model",
                },
                "finishReason": "STOP",
                "safetyRatings": [],
            }]
        }, 500
