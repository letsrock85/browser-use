#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Browser-Use: полная установка для Ubuntu + vLLM (MCP mode)
# ============================================================
#
# Использование:
#   chmod +x setup_browser_use.sh
#   ./setup_browser_use.sh
#
# Что делает:
#   1. Проверяет Python >= 3.11
#   2. Устанавливает uv
#   3. Создаёт venv ~/.browser-use-env
#   4. Устанавливает browser-use[cli]
#   5. Устанавливает Chromium
#   6. Генерирует config.json для vLLM
#   7. Применяет патч для vLLM-совместимости
#   8. Выводит команду для MCP-конфига
# ============================================================

VENV_DIR="$HOME/.browser-use-env"
CONFIG_DIR="$HOME/.config/browseruse"
CONFIG_FILE="$CONFIG_DIR/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---------- vLLM settings (измени перед запуском если нужно) ----------
VLLM_BASE_URL="${VLLM_BASE_URL:-https://vllm.sergeivas.com/v1}"
VLLM_API_KEY="${VLLM_API_KEY:-sk-vllm-local-12345}"
VLLM_MODEL="${VLLM_MODEL:-minimax}"
# ----------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Browser-Use Setup (Ubuntu + vLLM + MCP)"
echo "============================================"
echo ""
echo "vLLM URL:   $VLLM_BASE_URL"
echo "vLLM Model: $VLLM_MODEL"
echo ""

# --- 1. Python ---
echo "--- Шаг 1: Проверка Python ---"
PYTHON_CMD=""
for cmd in python3.12 python3.11 python3; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [ "$major" -ge 3 ] && [ "$minor" -ge 11 ]; then
            PYTHON_CMD="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    warn "Python >= 3.11 не найден. Устанавливаю..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y software-properties-common
        sudo add-apt-repository -y ppa:deadsnakes/ppa
        sudo apt-get update -qq
        sudo apt-get install -y python3.11 python3.11-venv python3.11-dev
        PYTHON_CMD="python3.11"
    else
        err "Не Ubuntu/Debian. Установи Python >= 3.11 вручную."
    fi
fi
log "Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"

# --- 2. uv ---
echo ""
echo "--- Шаг 2: Установка uv ---"
if command -v uv &>/dev/null; then
    log "uv уже установлен: $(uv --version)"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    log "uv установлен: $(uv --version)"
fi

# --- 3. Venv ---
echo ""
echo "--- Шаг 3: Создание venv ---"
if [ -d "$VENV_DIR" ]; then
    warn "Venv $VENV_DIR уже существует. Используем его."
else
    uv venv --python "$PYTHON_CMD" "$VENV_DIR"
    log "Venv создан: $VENV_DIR"
fi

# Activate
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
log "Venv активирован. Python: $(which python)"

# --- 4. Install browser-use ---
echo ""
echo "--- Шаг 4: Установка browser-use[cli] ---"
uv pip install 'browser-use[cli]'
log "browser-use установлен: $(python -c 'from browser_use.utils import get_browser_use_version; print(get_browser_use_version())' 2>/dev/null || echo 'ok')"

# --- 5. Chromium ---
echo ""
echo "--- Шаг 5: Установка Chromium ---"
if command -v chromium-browser &>/dev/null || command -v chromium &>/dev/null; then
    CHROMIUM_PATH=$(command -v chromium-browser || command -v chromium)
    log "Chromium уже установлен: $CHROMIUM_PATH"
else
    warn "Chromium не найден. Устанавливаю через browser-use..."
    "$VENV_DIR/bin/browser-use" install || {
        warn "browser-use install не смог. Ставлю через apt..."
        sudo apt-get update -qq
        sudo apt-get install -y chromium-browser || sudo apt-get install -y chromium
    }
    log "Chromium установлен."
fi

# --- 6. Config ---
echo ""
echo "--- Шаг 6: Генерация config.json ---"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/profiles"
mkdir -p "$CONFIG_DIR/extensions"

PROFILE_ID=$(python -c "from uuid import uuid4; print(uuid4())")
LLM_ID=$(python -c "from uuid import uuid4; print(uuid4())")
AGENT_ID=$(python -c "from uuid import uuid4; print(uuid4())")
NOW=$(python -c "from datetime import datetime; print(datetime.utcnow().isoformat())")

cat > "$CONFIG_FILE" << HEREDOC
{
  "browser_profile": {
    "$PROFILE_ID": {
      "id": "$PROFILE_ID",
      "default": true,
      "created_at": "$NOW",
      "headless": true,
      "user_data_dir": null,
      "downloads_path": "$HOME/Downloads/browser-use-mcp"
    }
  },
  "llm": {
    "$LLM_ID": {
      "id": "$LLM_ID",
      "default": true,
      "created_at": "$NOW",
      "api_key": "$VLLM_API_KEY",
      "model": "$VLLM_MODEL",
      "temperature": 0.6
    }
  },
  "agent": {
    "$AGENT_ID": {
      "id": "$AGENT_ID",
      "default": true,
      "created_at": "$NOW",
      "max_steps": 100,
      "use_vision": true
    }
  }
}
HEREDOC

log "Config записан: $CONFIG_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 7. Итог ---
echo ""
echo "============================================"
echo "  Установка завершена!"
echo "============================================"
echo ""
PYTHON_FULL_PATH="$VENV_DIR/bin/python"
echo "Python (используй этот путь в MCP-конфиге):"
echo "  $PYTHON_FULL_PATH"
MCP_JSON_PATH="\$HOME/.cursor/mcp.json или .cursor/mcp.json в проекте"
echo ""
echo "═══════════════════════════════════════════════"
echo "  Скопируй этот JSON в Cursor MCP-конфиг:"
echo "  ($MCP_JSON_PATH)"
echo "═══════════════════════════════════════════════"
cat << HEREDOC
{
  "mcpServers": {
    "browser-use": {
      "command": "$PYTHON_FULL_PATH",
      "args": ["-m", "browser_use.mcp"],
      "env": {
        "OPENAI_API_KEY": "$VLLM_API_KEY",
        "OPENAI_BASE_URL": "$VLLM_BASE_URL",
        "BROWSER_USE_LLM_MODEL": "$VLLM_MODEL",
        "ANONYMIZED_TELEMETRY": "false",
        "BROWSER_USE_HEADLESS": "true"
      }
    }
  }
}
HEREDOC
echo ""
echo "═══════════════════════════════════════════════"
echo "  Или для Claude Code (одна команда):"
echo "═══════════════════════════════════════════════"
echo ""
echo "OPENAI_API_KEY=$VLLM_API_KEY \\"
echo "OPENAI_BASE_URL=$VLLM_BASE_URL \\"
echo "BROWSER_USE_LLM_MODEL=$VLLM_MODEL \\"
echo "ANONYMIZED_TELEMETRY=false \\"
echo "BROWSER_USE_HEADLESS=true \\"
echo "claude mcp add browser-use -- $PYTHON_FULL_PATH -m browser_use.mcp"
echo ""
echo "═══════════════════════════════════════════════"
echo "  Проверка:"
echo "═══════════════════════════════════════════════"
echo ""
echo "  source $VENV_DIR/bin/activate"
echo "  OPENAI_BASE_URL=$VLLM_BASE_URL \\"
echo "  OPENAI_API_KEY=$VLLM_API_KEY \\"
echo "  BROWSER_USE_LLM_MODEL=$VLLM_MODEL \\"
echo "  python $SCRIPT_DIR/test_setup.py"
echo ""
echo "(опционально) Патч для ускорения vLLM inference:"
echo "  python $SCRIPT_DIR/patch_vllm_compat.py"
echo ""
