#!/usr/bin/env python3
"""
Relay Card 敏感信息脱敏 (Python 核心) - 幂等版
====================================================

用法: cat content | python3 relay_card_sanitize.py

脱敏规则:
  - API keys (sk-*, sk-ant-*, ghp_*, xoxb-*, AIza*, etc.)
  - Bearer tokens
  - AWS access key id (AKIA*) + secret
  - GitHub tokens (gh[opsu]_, github_pat_)
  - Slack tokens (xox[baprs]-)
  - ENV-style API_KEY/TOKEN/SECRET/PASSWORD assignments
  - PEM private key blocks
  - Email addresses
  - JWT tokens (header.payload.signature)

幂等保护:
  已经是 [REDACTED:xxx] 的块先抠出来占位, 处理完再贴回, 避免嵌套脱敏。
"""
import sys
import re

text = sys.stdin.read()
hits = {}

# === 幂等保护: 先把已脱敏块抠出来 ===
PLACEHOLDER_PREFIX = "\x00REDACTED_SLOT_"
PLACEHOLDER_SUFFIX = "\x00"
already_redacted = []


def stash_existing(m):
    idx = len(already_redacted)
    already_redacted.append(m.group(0))
    return f"{PLACEHOLDER_PREFIX}{idx}{PLACEHOLDER_SUFFIX}"


text = re.sub(r"\[REDACTED:[^\]]*\]", stash_existing, text)


def sub_count(pattern, replacement, label, flags=0):
    """替换并计数命中"""
    global text, hits
    new_text, n = re.subn(pattern, replacement, text, flags=flags)
    if n > 0:
        hits[label] = hits.get(label, 0) + n
    text = new_text


# === 高风险: API keys / tokens ===
sub_count(r"sk-ant-[a-zA-Z0-9_\-]{20,}", "[REDACTED:anthropic-key]", "anthropic-key")
sub_count(r"sk-[a-zA-Z0-9_\-]{20,}", "[REDACTED:api-key]", "sk-api-key")
sub_count(r"gh[opsu]_[a-zA-Z0-9]{30,}", "[REDACTED:github-token]", "github-token")
sub_count(r"github_pat_[a-zA-Z0-9_]{20,}", "[REDACTED:github-pat]", "github-pat")
sub_count(r"xox[baprs]-[a-zA-Z0-9\-]{10,}", "[REDACTED:slack-token]", "slack-token")
sub_count(
    r"(?i)Bearer\s+[a-zA-Z0-9._\-]{20,}",
    "Bearer [REDACTED:bearer-token]",
    "bearer-token",
)
sub_count(r"\bAKIA[0-9A-Z]{16}\b", "[REDACTED:aws-akid]", "aws-akid")
sub_count(
    r"(?i)(aws_secret_access_key|aws_secret)[\"\s:=]+[\"']?[A-Za-z0-9/+=]{40}[\"']?",
    r"\1=[REDACTED:aws-secret]",
    "aws-secret",
)
sub_count(r"\bAIza[0-9A-Za-z\-_]{35}\b", "[REDACTED:google-key]", "google-key")

# === 中风险: ENV 变量赋值 ===
sub_count(
    r"(?i)([A-Z_]*(?:API_KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD))\s*[=:]\s*[\"']?([^\s\"'\n]{8,})[\"']?",
    r"\1=[REDACTED:env-secret]",
    "env-secret",
)

# === 中风险: 私钥头部 ===
sub_count(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
    "[REDACTED:private-key-block]",
    "private-key",
)

# === 中风险: 邮箱 ===
sub_count(
    r"\b([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b",
    lambda m: f"[REDACTED:email@{m.group(2)}]",
    "email",
)

# === 低风险: JWT ===
sub_count(
    r"\beyJ[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}\b",
    "[REDACTED:jwt]",
    "jwt",
)

# === 还原占位符 ===
def restore_existing(m):
    idx = int(m.group(1))
    return already_redacted[idx] if idx < len(already_redacted) else m.group(0)


text = re.sub(
    re.escape(PLACEHOLDER_PREFIX) + r"(\d+)" + re.escape(PLACEHOLDER_SUFFIX),
    restore_existing,
    text,
)

sys.stdout.write(text)

if hits:
    report = " ".join(f"{k}={v}" for k, v in sorted(hits.items()))
    sys.stderr.write(f"[sanitize] hits: {report}\n")