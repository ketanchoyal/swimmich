#!/usr/bin/env bash
# Rappel ciblé par mot-clé dans la mémoire du projet courant.
# Usage : recall.sh <mot-clé>
#
# Cherche dans .opencode/memory.md à la racine du projet courant les blocs
# d'entrée (## ...) contenant le mot-clé (insensible à la casle, sous-chaîne).
# Sortie : les blocs correspondants, ou un message "Aucune entrée".
#
# Override test : MEMORY_FILE=/tmp/test.md recall.sh "kw"
set -euo pipefail

KEYWORD="${1:?mot-clé manquant}"

# Racine projet : .opencode/bin/ -> .opencode/ -> racine projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# git override si dispo : un sous-dossier pourrait être worktree séparé
if PROJECT_GIT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
  PROJECT_ROOT="$PROJECT_GIT"
fi

MEMORY_FILE="${MEMORY_FILE:-$PROJECT_ROOT/.opencode/memory.md}"

if [ ! -f "$MEMORY_FILE" ]; then
  echo "Mémoire projet introuvable ($MEMORY_FILE)."
  echo "Crée-la avec .opencode/bin/append-memory.sh ou en copiant le template."
  exit 0
fi

MATCHES=$(awk -v kw="$KEYWORD" '
  BEGIN { kw = tolower(kw) }
  /^```/ { infence = !infence; next }   # toggle état code block markdown
  /^## \[/ && !infence {                # vraie entrée : ## [YYYY-MM-DD] Titre — [tag: kw]
    if (block != "" && hit) print block "\n";
    block=$0"\n"; hit=0; if (index(tolower($0), kw)) hit=1; next
  }
  /^<!--/, /^-->/ { next }              # skip HTML comment blocks (template scaffolding)
  block != "" && !infence { block = block $0 "\n"; if (index(tolower($0), kw)) hit=1 }
  END { if (block != "" && hit) print block }
' "$MEMORY_FILE")

if [ -n "$MATCHES" ]; then
  echo "$MATCHES"
else
  echo "Aucune entrée trouvée pour \"$KEYWORD\" dans la mémoire projet ($MEMORY_FILE)."
fi
