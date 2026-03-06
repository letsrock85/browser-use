#!/usr/bin/env python3
"""
Патч MCP-сервера browser-use для совместимости с vLLM.

Проблема:
  1. MCP-сервер создаёт ChatOpenAI без dont_force_structured_output=True.
     vLLM не поддерживает response_format=ResponseFormatJSONSchema → запросы падают.
  2. LLMEntry в config.py не имеет поля base_url → config.json не может хранить его.
     base_url из config всегда None, поэтому блок `if base_url:` никогда не срабатывает.
     Реально base_url задаётся через env var OPENAI_BASE_URL (AsyncOpenAI SDK читает его).

Решение:
  Добавляем dont_force_structured_output=True напрямую в ChatOpenAI() вызовы,
  а также проверяем OPENAI_BASE_URL env var для base_url.

Безопасно перезапускать после обновления browser-use:
  python patch_vllm_compat.py
"""

import importlib.util
import sys
from pathlib import Path

MARKER = '# [vllm-compat-patch]'


def find_server_py() -> Path | None:
	spec = importlib.util.find_spec('browser_use.mcp.server')
	if spec and spec.origin:
		return Path(spec.origin)
	return None


def patch_file(path: Path) -> bool:
	content = path.read_text()

	if MARKER in content:
		print(f'[✓] Патч уже применён: {path}')
		return False

	lines = content.split('\n')
	new_lines = []
	patched_count = 0

	i = 0
	while i < len(lines):
		line = lines[i]

		# Находим: base_url = llm_config.get('base_url', None)
		# Добавляем после: fallback на OPENAI_BASE_URL env var
		if "base_url = llm_config.get('base_url', None)" in line and MARKER not in line:
			indent = line[:len(line) - len(line.lstrip())]
			new_lines.append(line)
			new_lines.append(f"{indent}if not base_url:  {MARKER}")
			new_lines.append(f"{indent}\tbase_url = os.getenv('OPENAI_BASE_URL')")
			i += 1
			patched_count += 1
			continue

		# Находим: kwargs['base_url'] = base_url
		# Добавляем после: kwargs['dont_force_structured_output'] = True
		if "kwargs['base_url'] = base_url" in line and MARKER not in line:
			indent = line[:len(line) - len(line.lstrip())]
			new_lines.append(line)
			# Проверяем что следующая строка ещё не наш патч
			if i + 1 < len(lines) and 'dont_force_structured_output' in lines[i + 1]:
				i += 1
				continue
			new_lines.append(f"{indent}kwargs['dont_force_structured_output'] = True  {MARKER}")
			i += 1
			patched_count += 1
			continue

		new_lines.append(line)
		i += 1

	if patched_count == 0:
		print(f'[!] Не удалось найти паттерны для патча в: {path}')
		print('    Возможно файл изменился в новой версии browser-use.')
		print('    Проверь вручную: browser_use/mcp/server.py')
		return False

	path.write_text('\n'.join(new_lines))
	return True


def main():
	server_py = find_server_py()
	if not server_py:
		print('[✗] Не найден browser_use.mcp.server в текущем окружении.')
		print('    Убедись что browser-use установлен и venv активирован.')
		sys.exit(1)

	print(f'[*] Найден server.py: {server_py}')

	if patch_file(server_py):
		print(f'[✓] Патч применён ({MARKER}).')
		print(f'    Что изменилось:')
		print(f'    - base_url fallback на OPENAI_BASE_URL env var (2 места)')
		print(f'    - dont_force_structured_output=True для ChatOpenAI (2 места)')
	else:
		print(f'[*] Изменения не потребовались.')


if __name__ == '__main__':
	main()
