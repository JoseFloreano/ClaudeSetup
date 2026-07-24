#!/usr/bin/env python3
"""
mark-code-dirty.py — Hook PostToolUse (Write|Edit|MultiEdit) de Claude Code.

Capa 1 del sistema anti-drift del vault: cuando la sesión edita un archivo de
CÓDIGO (cualquier cosa que no sea .md), deja un flag en .claude/vault-dirty.json.
El hook Stop (check-vault-updated.py) usa ese flag para exigir — una sola vez
por sesión — que los pendientes/estado del vault se actualicen antes de terminar.

Fail-open: cualquier error → exit 0 (un bug del hook no debe romper la sesión).
"""
import json
import os
import sys
import time


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_input = data.get("tool_input") or {}
    fp = (tool_input.get("file_path") or "").replace("\\", "/")
    if not fp:
        sys.exit(0)
    # Solo código cuenta: editar .md (vault, docs, planes) no ensucia el flag.
    low = fp.lower()
    if low.endswith(".md") or "/.obsidian/" in low or "/.claude/" in low:
        sys.exit(0)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    flag_dir = os.path.join(project_dir, ".claude")
    flag_path = os.path.join(flag_dir, "vault-dirty.json")
    session = data.get("session_id", "")

    try:
        os.makedirs(flag_dir, exist_ok=True)
        state = {}
        if os.path.exists(flag_path):
            with open(flag_path, "r", encoding="utf-8") as f:
                state = json.load(f) or {}
        if state.get("session_id") != session:
            state = {}  # sesión nueva: resetea el "ya se lo pedí"
        state.update({
            "session_id": session,
            "last_code_edit": time.time(),
            "enforced": bool(state.get("enforced", False)),
        })
        with open(flag_path, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
