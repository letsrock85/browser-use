# Browser-Use: Полный гайд по локальной установке (Ubuntu + vLLM + MCP)

## Архитектура

```
┌─────────────────────────────────────────────┐
│  Твой AI-агент (Claude Code / Cursor / etc) │
│  Он же — "мозги", принимает решения         │
│  Знает про MCP-tools автоматически          │
│  (MCP-сервер отдаёт список + описания)      │
└──────────────────┬──────────────────────────┘
                   │ stdin/stdout (MCP protocol)
                   │
┌──────────────────▼──────────────────────────┐
│  browser-use MCP Server                      │
│  Предоставляет tools: navigate, click,       │
│  type, screenshot, get_state, scroll и т.д.  │
│                                              │
│  Для extract_content и retry_with_agent      │
│  вызывает vLLM как helper LLM               │
└───────┬────────────────────┬────────────────┘
        │ CDP                │ HTTP
        │                    │
┌───────▼───────┐  ┌────────▼────────────────┐
│  Chromium     │  │  vLLM                    │
│  (локальный)  │  │  https://vllm.xxx.com   │
│  headless или │  │  модель: minimax         │
│  с окном      │  │  (потом bu-30b-a3b)     │
└───────────────┘  └─────────────────────────┘
```

## Как AI-агент узнаёт про MCP-tools?

**Автоматически.** MCP — стандартный протокол. При подключении MCP-сервер отдаёт
список инструментов с описаниями. AI-агент (Claude Code, Cursor) их считывает
и знает что и когда вызывать. Никакие skills подключать не нужно.

В репозитории есть и альтернативный подход через CLI Skill (`skills/browser-use/SKILL.md`),
но MCP — основной и рекомендуемый способ.

---

## Шаг 1: Установка на Ubuntu

```bash
# Скопируй setup-скрипт на сервер и запусти
chmod +x setup_browser_use.sh
./setup_browser_use.sh
```

Скрипт лежит в `.cursor/scripts/setup_browser_use.sh`. Что делает:
1. Проверяет Python >= 3.11 (ставит из deadsnakes PPA если нет)
2. Устанавливает uv
3. Создаёт venv в `~/.browser-use-env`
4. Устанавливает `browser-use[cli]`
5. Устанавливает Chromium
6. Генерирует `~/.config/browseruse/config.json` с настройками vLLM
7. Выводит готовый MCP-конфиг с **конкретным путём к Python**

---

## Шаг 2: Настройка MCP для AI-агента

Setup-скрипт в конце выводит готовый JSON. Скопируй его.

### Для Cursor

Создай файл `.cursor/mcp.json` в корне проекта:

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

**Замени `/home/USERNAME/` на свой путь** — setup-скрипт выведет точное значение.

### Для Claude Code

```bash
claude mcp add browser-use \
  --command /home/USERNAME/.browser-use-env/bin/python \
  -- -m browser_use.mcp
```

Потом в `~/.claude.json` добавь env-переменные в секцию этого MCP-сервера.
Или задай через export перед запуском claude.

### Как env-переменные работают (цепочка)

```
OPENAI_API_KEY        → config-система browser-use подхватывает → передаёт в ChatOpenAI
OPENAI_BASE_URL       → библиотека openai (AsyncOpenAI) подхватывает напрямую из env
BROWSER_USE_LLM_MODEL → config-система browser-use подхватывает → ставит model
BROWSER_USE_HEADLESS  → config-система browser-use подхватывает → headless режим
```

`OPENAI_BASE_URL` — это стандартная переменная библиотеки `openai` Python SDK.
AsyncOpenAI клиент читает её автоматически, даже если `base_url` не передан явно в коде.
Поэтому никакие патчи для base_url не нужны.

---

## Шаг 3: Проверка

```bash
source ~/.browser-use-env/bin/activate

# Проверить установку
browser-use doctor

# Открыть страницу (headless)
BROWSER_USE_HEADLESS=true browser-use open https://example.com
browser-use state
browser-use close
```

Тест vLLM + Chromium + config:

```bash
OPENAI_BASE_URL=https://vllm.sergeivas.com/v1 \
OPENAI_API_KEY=sk-vllm-local-12345 \
BROWSER_USE_LLM_MODEL=minimax \
python .cursor/scripts/test_setup.py
```

---

## Шаг 4: Замена модели

Чтобы переключиться на `browser-use/bu-30b-a3b-preview`:

1. Запусти модель через vLLM на GPU-сервере:
```bash
vllm serve browser-use/bu-30b-a3b-preview \
  --max-model-len 65536 \
  --host 0.0.0.0 --port 8000
```

2. Измени env в MCP-конфиге:
```json
"OPENAI_BASE_URL": "http://GPU_SERVER_IP:8000/v1",
"BROWSER_USE_LLM_MODEL": "browser-use/bu-30b-a3b-preview"
```

---

## Про патч (опционально)

**Патч НЕ обязателен.** vLLM 0.12+ поддерживает `response_format: {"type": "json_schema"}` из коробки через constrained decoding (xgrammar/guidance backends).

Патч (`.cursor/scripts/patch_vllm_compat.py`) нужен **только если**:
- Модель плохо работает с constrained decoding на вашем vLLM
- Хотите ускорить inference (constrained decoding добавляет overhead)
- Разработчики BU рекомендуют `dont_force_structured_output=True` для bu-30b-a3b-preview — для скорости

Если что-то ломается с structured output — запусти:
```bash
source ~/.browser-use-env/bin/activate
python .cursor/scripts/patch_vllm_compat.py
```

---

## Доступные MCP-инструменты

Когда AI-агент подключится к MCP-серверу, ему автоматически доступны:

| Tool | Нужен vLLM? | Что делает |
|---|---|---|
| `browser_navigate` | Нет | Открыть URL |
| `browser_click` | Нет | Кликнуть элемент по индексу или координатам |
| `browser_type` | Нет | Ввести текст в поле |
| `browser_get_state` | Нет | Получить DOM + опционально скриншот |
| `browser_screenshot` | Нет | Скриншот страницы |
| `browser_scroll` | Нет | Прокрутить |
| `browser_go_back` | Нет | Назад в истории |
| `browser_get_html` | Нет | Получить HTML |
| `browser_list_tabs` | Нет | Список вкладок |
| `browser_switch_tab` | Нет | Переключить вкладку |
| `browser_close_tab` | Нет | Закрыть вкладку |
| `browser_extract_content` | **Да** | Извлечь данные через helper LLM |
| `retry_with_browser_use_agent` | **Да** | Запустить автономного агента |
| `browser_list_sessions` | Нет | Список сессий |
| `browser_close_session` | Нет | Закрыть сессию |
| `browser_close_all` | Нет | Закрыть всё |

---

## Чего нет в open-source (cloud-only)

| Фича | Почему нет локально |
|---|---|
| Dashboard (web UI) | Закрытый код `cloud.browser-use.com` |
| Live Preview (web-стрим) | Cloud WebSocket `live.browser-use.com` |
| Anti-detection / CAPTCHA bypass | Проприетарный Chromium |
| Profile Sync в облако | Cloud API |
| Sandbox (`@sandbox`) | Cloud execution |
| ChatBrowserUse LLM | Cloud LLM router `llm.api.browser-use.com` |

Локально при `headless=false` — видишь окно Chromium на экране.

---

## Чеклист

```
[ ] Python >= 3.11 установлен
[ ] setup_browser_use.sh выполнен
[ ] browser-use doctor — зелёный
[ ] test_setup.py — все тесты пройдены
[ ] vLLM доступен (curl https://vllm.sergeivas.com/v1/models)
[ ] MCP-конфиг добавлен в Cursor/Claude Code с КОНКРЕТНЫМ путём к python
[ ] BROWSER_USE_HEADLESS=true (сервер без дисплея) или false (десктоп)
```

## Файлы

| Файл | Назначение |
|---|---|
| `.cursor/scripts/setup_browser_use.sh` | Полная установка |
| `.cursor/scripts/patch_vllm_compat.py` | Опциональный патч для ускорения vLLM |
| `.cursor/scripts/test_setup.py` | Тест всего pipeline |

## Lessons

- `OPENAI_BASE_URL` — стандартная env-переменная OpenAI Python SDK, AsyncOpenAI читает её автоматически
- `BROWSER_USE_LLM_MODEL` и `OPENAI_API_KEY` — подхватываются config-системой browser-use
- `LLMEntry` в config.py не имеет `base_url`, но это не проблема — `OPENAI_BASE_URL` работает на уровне SDK
- MCP-сервер отдаёт tools с описаниями автоматически — AI-агент знает что вызывать
- vLLM 0.12+ поддерживает `response_format: {"type": "json_schema"}` из коробки
- `dont_force_structured_output=True` рекомендуется для bu-30b-a3b-preview для скорости, не из-за отсутствия поддержки
- Docker не подходит для MCP (stdin/stdout), нативная установка
- Патч опционален — нужен только для скорости или если модель плохо работает с constrained decoding
