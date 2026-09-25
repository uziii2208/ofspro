"""
Response post-processing — strip refusals, detect blocks, extract
partial content from safety-truncated responses.

Author: @uziii2208
"""

import re
import json
from typing import Optional

# Patterns that indicate a refusal (model says no)
REFUSAL_PATTERNS = [
    r"I (?:cannot|can't|can not|am unable to|am not able to|won't|will not) (?:help|assist|provide|create|generate|write|give|offer|share|explain how to)",
    r"I'm (?:not able|unable|not going) to (?:help|assist|provide|create|generate|write)",
    r"(?:Sorry|I apologize|Unfortunately),?\s*(?:but\s+)?I (?:cannot|can't|am unable)",
    r"(?:This|That|Your) (?:request|query|question) (?:involves|relates to|asks about|is about) (?:potentially\s+)?(?:harmful|dangerous|illegal|malicious|unethical)",
    r"I (?:must|have to|need to) (?:decline|refuse|refrain from)",
    r"(?:It'?s|This is) (?:not appropriate|inappropriate|against my guidelines|outside my guidelines)",
    r"I'm designed to be (?:helpful|safe|harmless)",
    r"providing (?:instructions|guidance|information|details) (?:on|for|about) (?:how to\s+)?(?:hack|attack|exploit|compromise)",
    r"I (?:can't|cannot) (?:assist with|help with) (?:creating|building|developing|writing) (?:malware|exploits|attacks|malicious)",
    r"Instead,?\s*(?:I'd|I would|let me) (?:suggest|recommend|encourage)",
    r"For (?:legitimate|authorized) security testing,?\s*(?:I'd|I would) (?:suggest|recommend)",
    r"If you're (?:interested in|looking for) (?:legitimate|authorized|ethical) (?:security|penetration)",
]

# Patterns that indicate a partial compliance followed by refusal
PARTIAL_REFUSAL_PATTERNS = [
    r"(?:However|But|That said|Note that|Please note|Important),?\s*(?:I must|I need to|I should|I want to) (?:emphasize|note|mention|point out|warn|caution|remind)",
    r"(?:However|But|That said),?\s*(?:it'?s|this is) (?:important|crucial|essential) to (?:note|remember|emphasize|stress)",
    r"(?:Disclaimer|Warning|Caution|Note|Important):\s*(?:This|These|The)",
    r"(?:Always|Remember to|Make sure|Be sure to|Please) (?:ensure|get|obtain|have) (?:proper|written|explicit) (?:authorization|permission|consent)",
    r"\*\*(?:Disclaimer|Warning|Important|Note|Ethical|Legal)\*\*",
    r"---\n\*\*(?:Disclaimer|Warning|Note)",
]

COMPILED_REFUSALS = [re.compile(p, re.IGNORECASE | re.MULTILINE) for p in REFUSAL_PATTERNS]
COMPILED_PARTIALS = [re.compile(p, re.IGNORECASE | re.MULTILINE) for p in PARTIAL_REFUSAL_PATTERNS]


def is_full_refusal(text: str) -> bool:
    """Check if the response is a complete refusal (no useful content)."""
    stripped = text.strip()
    if len(stripped) < 200:
        for pattern in COMPILED_REFUSALS:
            if pattern.search(stripped):
                return True
    return False


def strip_refusal_suffix(text: str) -> str:
    """Remove trailing ethical disclaimers/refusals from otherwise useful responses."""
    lines = text.split("\n")

    cut_idx = len(lines)
    for i, line in enumerate(lines):
        for pattern in COMPILED_PARTIALS:
            if pattern.search(line):
                useful_before = "\n".join(lines[:i]).strip()
                if len(useful_before) > 100:
                    cut_idx = i
                    break
        if cut_idx != len(lines):
            break

    result = "\n".join(lines[:cut_idx]).rstrip()

    result = re.sub(
        r"\n\n---\n\n\*\*(?:Disclaimer|Warning|Note|Important).*$",
        "", result, flags=re.DOTALL | re.IGNORECASE
    )

    result = re.sub(
        r"\n\n(?:⚠️|⚠|🔒|🛡️|⛔)\s*\*\*.*$",
        "", result, flags=re.DOTALL
    )

    return result.rstrip()


def clean_response_body(body: dict) -> tuple[dict, bool]:
    """
    Process a Gemini API response body.
    Returns (modified_body, was_blocked).
    """
    was_blocked = False

    # Check for block at prompt level
    pf = body.get("promptFeedback", {})
    if pf.get("blockReason"):
        was_blocked = True
        return body, was_blocked

    candidates = body.get("candidates", [])
    if not candidates:
        return body, was_blocked

    for candidate in candidates:
        finish = candidate.get("finishReason", "")
        if finish in ("SAFETY", "RECITATION", "BLOCKED"):
            was_blocked = True
            continue

        content = candidate.get("content", {})
        parts = content.get("parts", [])
        for part in parts:
            if not isinstance(part, dict) or "text" not in part:
                continue

            text = part["text"]

            if is_full_refusal(text):
                was_blocked = True
                part["text"] = ""
                continue

            cleaned = strip_refusal_suffix(text)
            if cleaned != text:
                part["text"] = cleaned

        # Remove safety ratings that might cause client-side filtering
        if "safetyRatings" in candidate:
            for rating in candidate.get("safetyRatings", []):
                if isinstance(rating, dict):
                    rating["probability"] = "NEGLIGIBLE"
                    rating["blocked"] = False

    return body, was_blocked


def extract_useful_content(text: str) -> Optional[str]:
    """Extract code blocks and useful content from a partially-refused response."""
    code_blocks = re.findall(r"```[\w]*\n(.*?)```", text, re.DOTALL)
    if code_blocks:
        return "\n\n".join(code_blocks)

    lines = text.split("\n")
    useful = []
    for line in lines:
        is_refusal = any(p.search(line) for p in COMPILED_REFUSALS)
        if not is_refusal:
            useful.append(line)

    content = "\n".join(useful).strip()
    return content if len(content) > 50 else None
