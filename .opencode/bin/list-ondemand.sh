#!/usr/bin/env bash
#
# list-ondemand.sh — énumère les agents "on-demand" déployables à la volée par
# n'importe quel agent pipeline (specialist = advisory, contractor = action).
#
# Ces deux shells génériques n'ont PAS d'expertise pré-câblée : l'agent qui les
# invoque décrit leur rôle + tâche dans le prompt de l'invocation `task`. Voir
# AGENTS.pipeline.md (Phase 1.5 — Agents on-demand).
#
# Usage :
#   ./.opencode/bin/list-ondemand.sh              # lisible : "name — description"
#   ./.opencode/bin/list-ondemand.sh --names      # noms seuls (pour scripting)
#
# Sortie : 0 si OK (même si liste vide), 1 si opencode.json introuvable/invalid.
#
# Source of truth unique : .opencode/opencode.json. La liste des agents on-demand
# est l'ensemble fixe {"specialist", "contractor"} — la filtrer par nom plutôt
# que par suffixe évite tout faux positif sur d'éventuels futurs agents
# métiers pré-construits.

set -euo pipefail

# Trouve opencode.json : priorité ./.opencode/opencode.json (projet courant),
# fallback via répertoire du script (cas installation template).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${OPENCODE_CONFIG:-}"
if [ -z "$CONFIG" ]; then
  for candidate in "./.opencode/opencode.json" "$SCRIPT_DIR/../opencode.json"; do
    if [ -f "$candidate" ]; then CONFIG="$candidate"; break; fi
  done
fi

if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
  echo "list-ondemand: opencode.json introuvable (cherché ./.opencode/opencode.json)" >&2
  exit 1
fi

NAMES_ONLY=0
if [ "${1:-}" = "--names" ]; then NAMES_ONLY=1; fi

python3 - "$CONFIG" "$NAMES_ONLY" <<'PY'
import json, sys
config_path, names_only = sys.argv[1], int(sys.argv[2])
try:
    with open(config_path) as f:
        cfg = json.load(f)
except (OSError, json.JSONDecodeError) as e:
    print(f"list-ondemand: {config_path} illisible: {e}", file=sys.stderr)
    sys.exit(1)

# Ensemble fixe des shells on-demand. Ajouter un nouveau shell on-demand ici
# ET dans l'opencode.json + le grant task des agents pipeline.
ON_DEMAND = ("specialist", "contractor")

agents = cfg.get("agent", {})
rows = sorted(
    (name, meta.get("description", "").split("—")[0].strip())
    for name, meta in agents.items()
    if name in ON_DEMAND
)
if not rows:
    sys.exit(0)
for name, desc in rows:
    if names_only:
        print(name)
    else:
        print(f"{name} — {desc}" if desc else name)
PY
