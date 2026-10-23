#!/bin/bash
# Instala o assistente de voz.
# Uso: ./install.sh [--nome Luna] [--voz pf_dora] [--atalho option+space]
set -euo pipefail
cd "$(dirname "$0")"

ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nome) ARGS+=(name "$2"); shift 2 ;;
        --voz)
            case "$2" in pf_dora|pm_alex|pm_santa) ;; *) echo "Voz inválida: $2 (use pf_dora, pm_alex ou pm_santa)"; exit 2 ;; esac
            ARGS+=(voice "$2"); shift 2 ;;
        --atalho) ARGS+=(hotkey "$2"); shift 2 ;;
        *) echo "Opção desconhecida: $1"; exit 2 ;;
    esac
done

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "Precisa de um Mac com chip Apple (M1 ou mais novo)."; exit 1; }
command -v swift >/dev/null || { echo "Instale as ferramentas do Xcode: xcode-select --install (e rode de novo)."; exit 1; }
command -v brew >/dev/null || { echo "Instale o Homebrew (https://brew.sh) e rode de novo."; exit 1; }
command -v uv >/dev/null || brew install uv
command -v espeak-ng >/dev/null || brew install espeak-ng  # pronúncia do Kokoro
if ! command -v claude >/dev/null && [[ ! -x ~/.local/bin/claude ]]; then
    echo "Instale o Claude Code e faça login (https://claude.com/claude-code), depois rode de novo."
    exit 1
fi

echo "Instalando o servidor de voz (Whisper + Kokoro)..."
(cd backend && uv sync)

# Junta nome/voz/atalho ao ~/.ava/config.json sem apagar o que já existe (cores, mascote).
mkdir -p ~/.ava
backend/.venv/bin/python -I - "${ARGS[@]+"${ARGS[@]}"}" <<'EOF'
import json, os, sys
path = os.path.expanduser("~/.ava/config.json")
config = json.load(open(path)) if os.path.exists(path) else {}
pairs = sys.argv[1:]
config.update(zip(pairs[::2], pairs[1::2]))
json.dump(config, open(path, "w"), ensure_ascii=False, indent=2)
print("Configuração:", json.dumps({k: config.get(k) for k in ("name", "voice", "hotkey")}, ensure_ascii=False))
EOF

./build-app.sh
open /Applications/Ava.app
echo
echo "Pronto! Aperte o atalho para começar uma conversa (padrão: Control+Espaço)."
echo "Se usar Control+Espaço, desative em Ajustes do Sistema > Teclado > Atalhos > Fontes de Entrada."
