# Hooks — Enforcement determinista (auditoría R2)

El aislamiento de memoria por proyecto NO puede depender solo de instrucciones
en CLAUDE.md (compliance probabilística que se degrada en sesiones largas).
Estos hooks lo convierten en garantía: la llamada inválida se **bloquea antes
de ejecutarse** y Claude recibe el motivo para autocorregirse.

> Solo aplica a **Claude Code** (los hooks de sesión no corren sobre tu disco
> en Cowork). En Cowork la mitigación equivalente es montar por proyecto solo
> `10-Projects/<proyecto>/` + `brain/`, no el vault completo.

## Hooks incluidos

| Hook | Evento | Qué garantiza |
|------|--------|---------------|
| `validate-graphiti-group-id.py` | PreToolUse sobre `mcp__graphiti*` | Ningún `add_episode` sin `group_id` válido; ninguna búsqueda sin `group_ids`. Bloquea `main`, vacío y placeholders |

Requiere Python 3 en el PATH (`python3` en macOS/Linux, `python` en Windows).

## Instalación

1. Copia el script a tu config de Claude Code (y a tu repo de dotfiles):

   ```bash
   mkdir -p ~/.claude/hooks && cp validate-graphiti-group-id.py ~/.claude/hooks/
   ```

2. Fusiona esto en `~/.claude/settings.json` (ajusta `python3`→`python` en Windows
   y `~` a tu ruta absoluta si tu shell no la expande):

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "mcp__graphiti",
           "hooks": [
             {
               "type": "command",
               "command": "python3 ~/.claude/hooks/validate-graphiti-group-id.py"
             }
           ]
         }
       ]
     }
   }
   ```

3. Verifica en una sesión nueva: pide a Claude guardar un episodio **sin**
   group_id — debe ser bloqueado y reintentar con el group_id correcto.

## Diseño

- **Fail-open** ante entrada ilegible: si el JSON del hook no parsea, no
  bloquea (un bug del hook no debe tumbar el resto de herramientas).
- **Fail-closed** ante group_id ausente/prohibido: exit 2 + mensaje accionable.
- El multi-cuenta hereda el hook si copias `hooks/` + settings a cada
  `CLAUDE_CONFIG_DIR` (el sync de dotfiles ya contempla `settings.json`).
