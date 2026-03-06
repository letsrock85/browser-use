# Суммаризация чат-сессии: browser-use локальный сетап

**Дата:** 5-6 марта 2026
**Предыдущий чат:** `000dcb8b-becc-4e6b-a89d-2ae10f1a6019`

---

## Цель

Разобраться в проекте `browser-use` и настроить полностью локальный сетап:
- Запустить browser-use + Chromium локально
- Подключить свою LLM через vLLM (вместо облачной ChatBrowserUse)
- Интегрировать как MCP-сервер для Claude Code / Cursor / OpenCode
- Понять что доступно open-source, а что только в cloud

## Ключевые выводы

### Open-source vs Cloud

| Доступно локально | Только в cloud |
|---|---|
| Agent (полный цикл автоматизации) | Dashboard (web UI) |
| Локальный Chromium (headless/headful) | Live Preview (web-стрим браузера) |
| MCP Server (для Claude Code / Cursor) | Anti-detection / CAPTCHA bypass |
| Все tools: click, type, navigate, extract и т.д. | Profile Sync в облако |
| Любая LLM через ChatOpenAI / ChatOllama | Sandbox (`@sandbox`) декоратор |
| CLI (`browser-use doctor`, `browser-use open`) | `ChatBrowserUse` LLM API |

### Архитектура решения

```
AI-агент (Claude Code / Cursor)
    │ stdin/stdout (MCP protocol)
    ▼
browser-use MCP Server (нативная установка, НЕ Docker)
    ├── CDP → Chromium (локальный)
    └── HTTP → vLLM (https://vllm.sergeivas.com)
                модель: minimax (потом bu-30b-a3b-preview)
```

**Почему не Docker для browser-use?** MCP использует stdin/stdout для связи с AI-агентом. Docker усложняет этот пайплайн без выгоды. Нативная установка через `uv` + venv — надёжнее и проще.

### Конфигурация vLLM

- **base_url:** `https://vllm.sergeivas.com/v1`
- **api-key:** `sk-vllm-local-12345`
- **model:** `minimax` (с возможностью замены на `browser-use/bu-30b-a3b-preview`)
- **OPENAI_BASE_URL** — стандартная переменная OpenAI Python SDK, AsyncOpenAI читает её автоматически из env

### MCP-конфигурация (Cursor)

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "/home/USERNAME/.browser-use-env/bin/python",
      "args": ["-m", "browser_use.mcp"],
      "env": {
        "OPENAI_API_KEY": "sk-vllm-local-12345",
        "OPENAI_BASE_URL": "https://vllm.sergeivas.com/v1",
        "BROWSER_USE_LLM_MODEL": "minimax",
        "ANONYMIZED_TELEMETRY": "false",
        "BROWSER_USE_HEADLESS": "true"
      }
    }
  }
}
```

### MCP-конфигурация (Claude Code)

```bash
claude mcp add browser-use \
  --command /home/USERNAME/.browser-use-env/bin/python \
  -- -m browser_use.mcp
```
Плюс env-переменные через `~/.claude.json` или `export` перед запуском.

## Технические решения и уроки

### Почему BROWSER_USE_API_KEY в .env.example?
Это для cloud-функций: `ChatBrowserUse`, `use_cloud=True`, `@sandbox`, profile sync. При полностью локальном сетапе — **не нужен**.

### Structured output и vLLM
- vLLM 0.12+ поддерживает `response_format: {"type": "json_schema"}` из коробки
- `dont_force_structured_output=True` — опциональная оптимизация скорости для `bu-30b-a3b-preview`
- Патч `.cursor/scripts/patch_vllm_compat.py` **не обязателен**, нужен только если модель плохо работает с constrained decoding

### Как AI-агент узнаёт про tools?
MCP — стандартный протокол. При подключении MCP-сервер отдаёт полный список инструментов с описаниями. AI-агент (Claude Code, Cursor) считывает их автоматически. Skills или дополнительная настройка не требуются.

### LLMEntry и base_url
`LLMEntry` в `browser_use/config.py` не имеет поля `base_url`. Это не проблема — `OPENAI_BASE_URL` работает на уровне OpenAI Python SDK (AsyncOpenAI подхватывает из env напрямую).

## Модель bu-30b-a3b-preview

- **Архитектура:** Qwen3-VL-30B-A3B (Mixture of Experts, 30B total / 3B active)
- **Контекст:** 65,536 токенов
- **Тип:** Vision-Language (понимает скриншоты)
- **Требования vLLM:** >= 0.12.0
- **Запуск:** `vllm serve browser-use/bu-30b-a3b-preview --max-model-len 65536 --host 0.0.0.0 --port 8000`
- **HuggingFace:** https://huggingface.co/browser-use/bu-30b-a3b-preview

## Созданные файлы

| Файл | Назначение |
|---|---|
| `.cursor/scratchpad.md` | Полный гайд по установке и настройке |
| `.cursor/scripts/setup_browser_use.sh` | Автоматическая установка на Ubuntu |
| `.cursor/scripts/patch_vllm_compat.py` | Опциональный патч для ускорения vLLM |
| `.cursor/scripts/test_setup.py` | Тест всего pipeline (импорты, vLLM, Chromium, config) |
| `.cursor/chat_summary.md` | Этот файл — суммаризация чат-сессии |

## Git

- **Fork:** https://github.com/letsrock85/browser-use
- `origin` → `letsrock85/browser-use` (твой fork)
- `upstream` → `browser-use/browser-use` (оригинал)
- Обновления из оригинала: `git pull upstream main`

## Чеклист для новой машины

```
[ ] git clone https://github.com/letsrock85/browser-use.git
[ ] Прочитать .cursor/scratchpad.md
[ ] Запустить .cursor/scripts/setup_browser_use.sh
[ ] browser-use doctor
[ ] Проверить vLLM: curl https://vllm.sergeivas.com/v1/models
[ ] Запустить .cursor/scripts/test_setup.py
[ ] Добавить MCP-конфиг в Cursor/Claude Code
[ ] Заменить /home/USERNAME/ на реальный путь (скрипт выведет)
[ ] BROWSER_USE_HEADLESS=true (сервер) или false (десктоп с монитором)
```

## Как продолжить работу в новом чате

Начни новый чат с:

> "Прочитай `.cursor/scratchpad.md` и `.cursor/chat_summary.md` — там полный контекст предыдущей работы. Продолжай в режиме Executor."
