#!/usr/bin/env bash
# Ajoute une entrée à la mémoire du projet courant (.opencode/memory.md).
# Usage : append-memory.sh "<titre>" "<tag>" "<contexte>" "<decision>" "<pourquoi>" "<fichiers>"
#
# Override test : MEMORY_FILE=/tmp/test.md append-memory.sh ...
set -euo pipefail

# Racine projet : .opencode/bin/ -> .opencode/ -> racine projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if PROJECT_GIT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
  PROJECT_ROOT="$PROJECT_GIT"
fi

MEMORY_FILE="${MEMORY_FILE:-$PROJECT_ROOT/.opencode/memory.md}"
DATE=$(date +%Y-%m-%d)

TITLE="${1:?titre manquant}"
TAG="${2:?tag manquant}"
CONTEXTE="${3:?contexte manquant}"
DECISION="${4:?decision manquante}"
POURQUOI="${5:?pourquoi manquant}"
FICHIERS="${6:-non précisés}"

# Crée le fichier (et le dossier parent) si absent — première entrée.
mkdir -p "$(dirname "$MEMORY_FILE")"
touch "$MEMORY_FILE"

{
  echo ""
  echo "## [$DATE] $TITLE — [tag: $TAG]"
  echo ""
  echo "**Contexte** : $CONTEXTE"
  echo "**Décision/apprentissage** : $DECISION"
  echo "**Pourquoi** : $POURQUOI"
  echo "**Fichiers concernés** : $FICHIERS"
} >> "$MEMORY_FILE"

echo "Entrée ajoutée à $MEMORY_FILE"
