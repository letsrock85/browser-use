#!/usr/bin/env python3
"""
Тест установки browser-use + vLLM + MCP.

Запуск:
  source ~/.browser-use-env/bin/activate
  python test_setup.py

Или с кастомными параметрами:
  OPENAI_BASE_URL=https://vllm.sergeivas.com/v1 \
  OPENAI_API_KEY=sk-vllm-local-12345 \
  BROWSER_USE_LLM_MODEL=minimax \
  python test_setup.py
"""

import asyncio
import os
import sys

os.environ.setdefault('ANONYMIZED_TELEMETRY', 'false')
os.environ.setdefault('BROWSER_USE_LOGGING_LEVEL', 'warning')

PASS = '\033[0;32m[✓]\033[0m'
FAIL = '\033[0;31m[✗]\033[0m'
INFO = '\033[1;33m[*]\033[0m'

results: list[tuple[str, bool, str]] = []


def record(name: str, ok: bool, detail: str = ''):
	results.append((name, ok, detail))
	status = PASS if ok else FAIL
	msg = f'{status} {name}'
	if detail:
		msg += f' — {detail}'
	print(msg)


async def main():
	print('\n=== Browser-Use Setup Test ===\n')

	# --- 1. Import ---
	try:
		import browser_use
		from browser_use.utils import get_browser_use_version
		ver = get_browser_use_version()
		record('Import browser_use', True, f'v{ver}')
	except Exception as e:
		record('Import browser_use', False, str(e))
		print(f'\n{FAIL} Критическая ошибка: browser-use не установлен.')
		sys.exit(1)

	# --- 2. ChatOpenAI import ---
	try:
		from browser_use.llm.openai.chat import ChatOpenAI
		record('Import ChatOpenAI', True)
	except Exception as e:
		record('Import ChatOpenAI', False, str(e))

	# --- 3. Check env vars ---
	base_url = os.environ.get('OPENAI_BASE_URL', '')
	api_key = os.environ.get('OPENAI_API_KEY', '')
	model = os.environ.get('BROWSER_USE_LLM_MODEL', '')

	if base_url:
		record('OPENAI_BASE_URL', True, base_url)
	else:
		record('OPENAI_BASE_URL', False, 'не установлена — vLLM не будет работать')

	if api_key:
		record('OPENAI_API_KEY', True, f'{api_key[:8]}...')
	else:
		record('OPENAI_API_KEY', False, 'не установлена')

	if model:
		record('BROWSER_USE_LLM_MODEL', True, model)
	else:
		record('BROWSER_USE_LLM_MODEL', False, 'не установлена, будет дефолт gpt-4o')

	# --- 4. vLLM connectivity ---
	if base_url and api_key:
		try:
			llm = ChatOpenAI(
				model=model or 'minimax',
				api_key=api_key,
				dont_force_structured_output=True,
				temperature=0.6,
			)

			from browser_use.llm.messages import SystemMessage
			response = await llm.ainvoke([SystemMessage(content='Say "hello" and nothing else.')])
			text = str(response.completion)[:100]
			record('vLLM chat completion', True, f'ответ: {text}')
		except Exception as e:
			record('vLLM chat completion', False, str(e))
	else:
		print(f'{INFO} Пропуск теста vLLM — нет OPENAI_BASE_URL/OPENAI_API_KEY')

	# --- 5. Patch check ---
	try:
		import importlib.util
		spec = importlib.util.find_spec('browser_use.mcp.server')
		if spec and spec.origin:
			content = open(spec.origin).read()
			if 'dont_force_structured_output' in content:
				record('vLLM patch (dont_force_structured_output)', True, 'найден в server.py')
			else:
				record('vLLM patch (dont_force_structured_output)', False,
					   'НЕ найден! Запусти patch_vllm_compat.py')
		else:
			record('vLLM patch check', False, 'server.py не найден')
	except Exception as e:
		record('vLLM patch check', False, str(e))

	# --- 6. Chromium ---
	try:
		from browser_use.browser.session import BrowserSession
		from browser_use.browser.profile import BrowserProfile

		profile = BrowserProfile(headless=True)
		session = BrowserSession(browser_profile=profile)
		await session.start()

		state = await session.get_browser_state_summary()
		url = state.url if state else 'unknown'
		record('Chromium запуск', True, f'URL: {url}')

		await session.stop()
		record('Chromium остановка', True)
	except Exception as e:
		record('Chromium запуск', False, str(e))
		if 'Executable doesn' in str(e) or 'chromium' in str(e).lower():
			print(f'  {INFO} Попробуй: browser-use install')
			print(f'  {INFO} Или: sudo apt install chromium-browser')

	# --- 7. Config ---
	try:
		from browser_use.config import CONFIG
		config = CONFIG.load_config()
		llm_cfg = config.get('llm', {})
		record('Config.json загрузка', True,
			   f'model={llm_cfg.get("model", "?")}, api_key={"есть" if llm_cfg.get("api_key") else "нет"}')
	except Exception as e:
		record('Config.json загрузка', False, str(e))

	# --- Summary ---
	print('\n=== Итог ===\n')
	passed = sum(1 for _, ok, _ in results if ok)
	failed = sum(1 for _, ok, _ in results if not ok)
	total = len(results)
	print(f'Пройдено: {passed}/{total}')
	if failed:
		print(f'\nНе прошли:')
		for name, ok, detail in results:
			if not ok:
				print(f'  - {name}: {detail}')
		sys.exit(1)
	else:
		print(f'\n{PASS} Всё работает! Можно настраивать MCP.\n')


if __name__ == '__main__':
	asyncio.run(main())
