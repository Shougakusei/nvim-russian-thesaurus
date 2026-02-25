# Lemmatization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add optional pymorphy3-based lemmatization so synonym lookup works for inflected Russian word forms (e.g., "серая" → "серый").

**Architecture:** A persistent Python subprocess (`morph_server.py`) communicates with a new Lua module (`morph.lua`) via line-based stdin/stdout protocol. `query.lua` tries exact match first, then falls back to lemmatization on miss. The feature is entirely optional — without Python/pymorphy3, the plugin behaves as before.

**Tech Stack:** Lua (Neovim 0.9+), Python 3.8+ with pymorphy3 (optional runtime dep), pytest (dev dep)

**Design doc:** `docs/plans/2026-02-24-lemmatization-design.md`

---

### Task 1: Python morph server script

**Files:**
- Create: `scripts/morph_server.py`

**Step 1: Create pyproject.toml for dev dependencies**

Create `pyproject.toml` at project root:

```toml
[project]
name = "nvim-russian-thesaurus"
version = "0.1.0"
description = "Dev tooling for nvim-russian-thesaurus"
requires-python = ">=3.8"
dependencies = ["pymorphy3"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pytest.ini_options]
testpaths = ["tests"]

[dependency-groups]
dev = ["pytest"]
```

Run: `uv sync`

**Step 2: Write the morph_server.py script**

Create `scripts/morph_server.py`:

```python
#!/usr/bin/env python3
"""Сервер морфологического анализа для nvim-russian-thesaurus.

Читает слова из stdin (по одному на строку), возвращает лемму (нормальную форму)
в stdout. Используется как persistent subprocess из Neovim.

Протокол:
    → stdin:  "серая\n"
    ← stdout: "серый\n"
"""

import sys

import pymorphy3


def main():
    """Основной цикл сервера."""
    morph = pymorphy3.MorphAnalyzer()
    print("READY", flush=True)

    for line in sys.stdin:
        word = line.strip()
        if not word:
            continue
        parsed = morph.parse(word)
        lemma = parsed[0].normal_form if parsed else word
        print(lemma, flush=True)


if __name__ == "__main__":
    main()
```

**Step 3: Run the script manually to verify**

Run: `echo -e "серая\nбегущий\nмашину" | uv run python scripts/morph_server.py`

Expected output:
```
READY
серый
бежать
машина
```

**Step 4: Commit**

```bash
git add pyproject.toml uv.lock scripts/morph_server.py
git commit -m "feat(morph): add persistent Python lemmatizer server"
```

---

### Task 2: Python tests for morph_server

**Files:**
- Create: `tests/test_morph_server.py`

**Step 1: Write the tests**

Create `tests/test_morph_server.py`:

```python
"""Тесты для morph_server.py."""

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = str(Path(__file__).parent.parent / "scripts" / "morph_server.py")


@pytest.fixture
def server():
    """Запускает morph_server.py как subprocess."""
    proc = subprocess.Popen(
        [sys.executable, SCRIPT],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    # Ждём сигнал готовности
    ready = proc.stdout.readline().strip()
    assert ready == "READY", f"Ожидалось 'READY', получено '{ready}'"
    yield proc
    proc.stdin.close()
    proc.wait(timeout=5)


def query(proc, word):
    """Отправляет слово серверу и возвращает ответ."""
    proc.stdin.write(word + "\n")
    proc.stdin.flush()
    return proc.stdout.readline().strip()


class TestMorphServer:
    """Тесты морфологического сервера."""

    def test_adjective_feminine_to_base(self, server):
        """Женская форма прилагательного → мужская (словарная)."""
        assert query(server, "серая") == "серый"

    def test_adjective_neuter_to_base(self, server):
        """Средний род прилагательного → мужской (словарный)."""
        assert query(server, "серое") == "серый"

    def test_noun_accusative_to_nominative(self, server):
        """Винительный падеж существительного → именительный."""
        assert query(server, "машину") == "машина"

    def test_noun_genitive_plural(self, server):
        """Родительный падеж множественного числа → именительный единственного."""
        assert query(server, "домов") == "дом"

    def test_verb_participle_to_infinitive(self, server):
        """Причастие → инфинитив."""
        assert query(server, "бегущий") == "бежать"

    def test_verb_past_tense(self, server):
        """Прошедшее время глагола → инфинитив."""
        assert query(server, "бежал") == "бежать"

    def test_base_form_unchanged(self, server):
        """Словарная форма возвращается без изменений."""
        assert query(server, "серый") == "серый"

    def test_unknown_word_returned_as_is(self, server):
        """Неизвестное слово возвращается без изменений."""
        assert query(server, "абракадабра") == "абракадабра"

    def test_multiple_queries_sequential(self, server):
        """Несколько запросов подряд обрабатываются корректно."""
        assert query(server, "серая") == "серый"
        assert query(server, "домов") == "дом"
        assert query(server, "бежал") == "бежать"
```

**Step 2: Run tests to verify they pass**

Run: `uv run pytest tests/test_morph_server.py -v`

Expected: All 9 tests PASS.

**Step 3: Commit**

```bash
git add tests/test_morph_server.py
git commit -m "test(morph): add Python tests for morph_server"
```

---

### Task 3: Lua morph module — process management

**Files:**
- Create: `lua/nvim-russian-thesaurus/morph.lua`

**Step 1: Write morph.lua**

Create `lua/nvim-russian-thesaurus/morph.lua`:

```lua
--- Модуль морфологического анализа.
---
--- Управляет persistent Python-процессом для лемматизации русских слов.
--- При недоступности Python/pymorphy3 плагин работает без лемматизации.

local M = {}

local _job_id = nil
local _ready = false
local _pending = nil -- {callback, timer_id}
local _cache = {}
local _warned = false
local _restart_attempted = false

--- Определяет путь к скрипту morph_server.py.
---
--- Returns:
---   Абсолютный путь к scripts/morph_server.py внутри директории плагина.
local function script_path()
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h")
  return plugin_dir .. "/scripts/morph_server.py"
end

--- Показывает одноразовое предупреждение о недоступности лемматизации.
---
--- Args:
---   reason: Причина недоступности.
local function warn_once(reason)
  if not _warned then
    _warned = true
    vim.notify(
      "nvim-russian-thesaurus: лемматизация недоступна: " .. reason,
      vim.log.levels.WARN
    )
  end
end

--- Callback для stdout от Python-процесса.
---
--- Args:
---   _id: Job ID (не используется).
---   data: Массив строк из stdout.
---   _event: Тип события (не используется).
local function on_stdout(_id, data, _event)
  if not data then
    return
  end
  for _, line in ipairs(data) do
    line = vim.trim(line)
    if line == "" then
      -- пустая строка, пропускаем
    elseif line == "READY" then
      _ready = true
    elseif _pending then
      local cb = _pending.callback
      if _pending.timer_id then
        vim.fn.timer_stop(_pending.timer_id)
      end
      _pending = nil
      cb(line)
    end
  end
end

--- Callback при завершении Python-процесса.
---
--- Args:
---   _id: Job ID.
---   exit_code: Код завершения.
---   _event: Тип события.
local function on_exit(_id, exit_code, _event)
  _job_id = nil
  _ready = false

  -- Отменяем ожидающий запрос
  if _pending then
    local cb = _pending.callback
    if _pending.timer_id then
      vim.fn.timer_stop(_pending.timer_id)
    end
    _pending = nil
    cb(nil)
  end

  if exit_code ~= 0 and not _restart_attempted then
    _restart_attempted = true
    M.start()
  end
end

--- Запускает Python-процесс лемматизации.
---
--- Вызывается при setup() плагина. При ошибке выводит одноразовое предупреждение.
function M.start()
  if _job_id then
    return
  end

  local python = vim.fn.exepath("python3")
  if python == "" then
    warn_once("python3 не найден")
    return
  end

  local script = script_path()
  if vim.fn.filereadable(script) ~= 1 then
    warn_once("скрипт не найден: " .. script)
    return
  end

  _job_id = vim.fn.jobstart({ python, script }, {
    on_stdout = on_stdout,
    on_exit = on_exit,
    stdout_buffered = false,
  })

  if _job_id <= 0 then
    _job_id = nil
    warn_once("не удалось запустить процесс лемматизации")
    return
  end

  -- Регистрируем очистку при выходе из Neovim
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.stop()
    end,
    once = true,
  })
end

--- Останавливает Python-процесс.
function M.stop()
  if _job_id then
    vim.fn.jobstop(_job_id)
    _job_id = nil
    _ready = false
  end
end

--- Проверяет готовность процесса лемматизации.
---
--- Returns:
---   true если процесс запущен и готов к запросам.
function M.is_ready()
  return _ready
end

--- Лемматизирует слово через Python-процесс.
---
--- Args:
---   word: Слово для лемматизации.
---   callback: Функция callback(lemma). Получает лемму или nil при ошибке/таймауте.
function M.lemmatize(word, callback)
  if not _ready then
    callback(nil)
    return
  end

  -- Проверяем кэш
  if _cache[word] then
    callback(_cache[word])
    return
  end

  -- Отменяем предыдущий запрос если есть
  if _pending then
    local old_cb = _pending.callback
    if _pending.timer_id then
      vim.fn.timer_stop(_pending.timer_id)
    end
    _pending = nil
    old_cb(nil)
  end

  -- Таймаут 2 секунды
  local timer_id = vim.fn.timer_start(2000, function()
    if _pending then
      local cb = _pending.callback
      _pending = nil
      cb(nil)
    end
  end)

  _pending = {
    callback = function(lemma)
      if lemma then
        _cache[word] = lemma
      end
      callback(lemma)
    end,
    timer_id = timer_id,
  }

  vim.fn.chansend(_job_id, word .. "\n")
end

--- Сбрасывает состояние модуля (для тестирования).
function M.reset()
  M.stop()
  _cache = {}
  _warned = false
  _restart_attempted = false
  _pending = nil
end

return M
```

**Step 2: Commit**

```bash
git add lua/nvim-russian-thesaurus/morph.lua
git commit -m "feat(morph): add Lua module for Python process management"
```

---

### Task 4: Integrate morph into query flow

**Files:**
- Modify: `lua/nvim-russian-thesaurus/query.lua:1,92-96`
- Modify: `lua/nvim-russian-thesaurus/init.lua:1-2,33-37`

**Step 1: Add morph require to query.lua**

In `query.lua`, add morph require at line 1 (after the data require):

```lua
local data = require("nvim-russian-thesaurus.data")
local morph = require("nvim-russian-thesaurus.morph")
```

**Step 2: Extract show_results helper in query.lua**

Extract the vim.ui.select block (lines 98-113) into a local function, and rewrite `query_replace` to use it with lemmatization fallback.

Replace `query.lua` lines 92-114 (the results handling and vim.ui.select block) with:

```lua
  local results = data.lookup(word)
  if results then
    show_results(results, word, mode)
    return
  end

  -- Пробуем лемматизацию при отсутствии точного совпадения
  if not morph.is_ready() then
    vim.notify("Синонимы не найдены: " .. word, vim.log.levels.WARN)
    return
  end

  morph.lemmatize(word, function(lemma)
    if lemma and lemma ~= word then
      results = data.lookup(lemma)
    end
    if results then
      show_results(results, word, mode)
    else
      vim.notify("Синонимы не найдены: " .. word, vim.log.levels.WARN)
    end
  end)
```

Add the `show_results` helper function before `query_replace` (after `format_items`):

```lua
--- Отображает результаты поиска синонимов в vim.ui.select.
---
--- Args:
---   results: Массив результатов из data.lookup().
---   word: Исходное слово (для заголовка).
---   mode: Режим вызова ("n" или "v").
local function show_results(results, word, mode)
  local items = format_items(results)
  if #items == 0 then
    vim.notify("Синонимы не найдены: " .. word, vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = "Синонимы для: " .. word,
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      replace_text(choice.value, mode)
    end
  end)
end
```

**Step 3: Add morph.start() to init.lua**

In `init.lua`, add the morph require at line 2:

```lua
local data = require("nvim-russian-thesaurus.data")
local morph = require("nvim-russian-thesaurus.morph")
local query = require("nvim-russian-thesaurus.query")
```

After data.init() succeeds (after line 37, before the keymaps section), add:

```lua
  morph.start()
```

**Step 4: Commit**

```bash
git add lua/nvim-russian-thesaurus/query.lua lua/nvim-russian-thesaurus/init.lua
git commit -m "feat(query): integrate lemmatization fallback into synonym lookup"
```

---

### Task 5: Lua unit tests for morph module

**Files:**
- Create: `tests/morph_spec.lua`

Note: morph.lua depends on vim.fn.jobstart which is unavailable in busted. These tests mock the vim API to test the cache and fallback logic. The Python integration is tested by Task 2 (pytest) and Task 6 (manual).

**Step 1: Write morph_spec.lua**

Create `tests/morph_spec.lua`:

```lua
describe("nvim-russian-thesaurus.morph", function()
  local morph

  setup(function()
    -- Мок vim API для busted
    _G.vim = _G.vim or {}
    vim.fn = vim.fn or {}
    vim.fn.exepath = vim.fn.exepath or function() return "" end
    vim.fn.filereadable = vim.fn.filereadable or function() return 0 end
    vim.fn.fnamemodify = vim.fn.fnamemodify or function(path, _) return path end
    vim.fn.jobstart = vim.fn.jobstart or function() return -1 end
    vim.fn.jobstop = vim.fn.jobstop or function() end
    vim.fn.chansend = vim.fn.chansend or function() end
    vim.fn.timer_start = vim.fn.timer_start or function() return 0 end
    vim.fn.timer_stop = vim.fn.timer_stop or function() end
    vim.trim = vim.trim or function(s) return s:match("^%s*(.-)%s*$") end
    vim.notify = vim.notify or function() end
    vim.log = vim.log or { levels = { WARN = 2 } }
    vim.api = vim.api or {}
    vim.api.nvim_create_autocmd = vim.api.nvim_create_autocmd or function() end

    morph = require("lua.nvim-russian-thesaurus.morph")
  end)

  before_each(function()
    morph.reset()
  end)

  describe("start", function()
    it("выводит предупреждение если python3 не найден", function()
      local warned = false
      vim.notify = function(msg, _level)
        if msg:find("python3 не найден") then
          warned = true
        end
      end
      vim.fn.exepath = function() return "" end

      morph.start()
      assert.is_true(warned)
    end)

    it("предупреждение показывается только один раз", function()
      local warn_count = 0
      vim.notify = function(msg, _level)
        if msg:find("лемматизация недоступна") then
          warn_count = warn_count + 1
        end
      end
      vim.fn.exepath = function() return "" end

      morph.start()
      morph.start()
      assert.are.equal(1, warn_count)
    end)
  end)

  describe("is_ready", function()
    it("возвращает false до запуска", function()
      assert.is_false(morph.is_ready())
    end)
  end)

  describe("lemmatize", function()
    it("вызывает callback(nil) если процесс не готов", function()
      local result = "not_called"
      morph.lemmatize("серая", function(lemma)
        result = lemma
      end)
      assert.is_nil(result)
    end)
  end)
end)
```

**Step 2: Run tests**

Run: `busted tests/morph_spec.lua` (if busted is available) or skip if not installed.

**Step 3: Commit**

```bash
git add tests/morph_spec.lua
git commit -m "test(morph): add Lua unit tests for morph module"
```

---

### Task 6: Update existing tests and run full suite

**Files:**
- Modify: `tests/data_spec.lua` (no changes needed — data.lua is unchanged)

**Step 1: Run existing Lua tests**

Run: `busted tests/data_spec.lua` (if busted available)

Expected: All existing tests still pass (data.lua was not modified).

**Step 2: Run Python tests**

Run: `uv run pytest tests/test_morph_server.py -v`

Expected: All 9 tests PASS.

**Step 3: Manual integration test in Neovim**

1. Install pymorphy3: `uv pip install pymorphy3` (or `pip install pymorphy3`)
2. Open Neovim with the plugin loaded
3. Type "серая" in a buffer, position cursor on it
4. Press `<leader>ch`
5. Expected: synonym list appears (from "серый" synset)
6. Verify no errors in `:messages`

**Step 4: Test fallback (without pymorphy3)**

1. Temporarily rename `scripts/morph_server.py`
2. Restart Neovim
3. Check `:messages` for one-time warning
4. Lookup "серая" — should show "Синонимы не найдены"
5. Lookup "серый" — should still work (exact match)
6. Restore script name

**Step 5: Commit (if any test fixes were needed)**

```bash
git commit -m "test: verify existing tests pass with morph integration"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

**Step 1: Add lemmatization section to README**

Add a section documenting:
- The optional pymorphy3 dependency
- How to install it (`pip install pymorphy3`)
- What it enables (synonym lookup for inflected forms)
- That the plugin works without it (exact match only)

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add pymorphy3 lemmatization to README"
```
