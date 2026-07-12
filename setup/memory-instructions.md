## Memory (Graphiti Knowledge Graph)

The `graphiti-memory` MCP is active at `http://localhost:8000/mcp/`.
It provides persistent temporal memory across sessions using a knowledge graph.

### Rules — ALWAYS follow these
1. **Search before saving**: call `search_facts` or `search_nodes` BEFORE `add_episode`.
   - If the information already exists (similarity > 0.8), update instead of creating.
2. **Always use project-scoped group_id**: `group_id: "<project-name>"`.
   - NEVER use `"main"` or omit group_id.
   - Global dev preferences go to `group_id: "dev-global"`.
3. **Save asynchronously**: `add_episode` is non-blocking (~25s to process).
   - Don't wait for confirmation before continuing work.

### What to save (high value)
- Architecture decisions (ADRs): why X was chosen over Y
- Bug root causes and their fixes (especially non-obvious ones)
- Library versions that are pinned and why
- Project-specific conventions that differ from defaults
- "Why NOT X" decisions — things explicitly rejected

### What NOT to save
- Temporary debugging output
- Content already in CLAUDE.md or .graphiti.json
- Speculative ideas not yet decided
- Anything that changes every session

### Episodio format (prefer structured JSON)
```python
# Architecture decision
add_episode(
  name="ADR: state management choice",
  episode_body={
    "decision": "Riverpod over Bloc",
    "rationale": "Better ergonomics, hooks integration, small team",
    "alternatives_rejected": ["Bloc (too verbose)", "Provider (deprecated)"],
    "date": "2026-07-12"
  },
  group_id="my-flutter-app"
)

# Bug fix
add_episode(
  name="Fix: Flutter hot reload breaks Riverpod state on Windows",
  episode_body={
    "symptom": "State resets on hot reload in debug mode",
    "root_cause": "Ref.invalidate() called on dispose in keepAlive provider",
    "fix": "Add ref.keepAlive() before dispose hook",
    "files": ["lib/providers/auth_provider.dart"]
  },
  group_id="my-flutter-app"
)
```

### At session start — auto-search context
```python
# Search relevant context at the start of a work session
search_facts(query="recent decisions and known issues", group_ids=["my-flutter-app", "dev-global"])
```
