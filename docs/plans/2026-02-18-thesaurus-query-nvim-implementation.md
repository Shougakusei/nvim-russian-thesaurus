# nvim-russian-thesaurus Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Russian-language thesaurus plugin for Neovim/LazyVim that looks up synonyms from a bundled YARN dataset and presents them via `vim.ui.select()`.

**Architecture:** Pure Lua plugin with lazy-loaded in-memory index. CSV parsed on first query into a `word → [{grammar, domain, synonyms}]` hash table. UI delegates to Neovim's built-in `vim.ui.select()`. No network calls, no external dependencies beyond Neovim.

**Tech Stack:** Lua (Neovim runtime), busted (unit tests), yarn-synsets.csv (YARN dataset)

---

### Task 1: Project Scaffolding & Data File

**Files:**
- Create: `lua/nvim-russian-thesaurus/init.lua` (empty placeholder)
- Create: `lua/nvim-russian-thesaurus/data.lua` (empty placeholder)
- Create: `lua/nvim-russian-thesaurus/query.lua` (empty placeholder)
- Create: `plugin/nvim-russian-thesaurus.lua` (empty placeholder)
- Create: `tests/fixtures/test-synsets.csv` (small test fixture)
- Download: `data/yarn-synsets.csv` (from YARN GitHub releases)

**Step 1: Create directory structure**

```bash
mkdir -p lua/nvim-russian-thesaurus tests/fixtures plugin data
```

**Step 2: Create empty module placeholders**

`lua/nvim-russian-thesaurus/init.lua`:
```lua
local M = {}
return M
```

`lua/nvim-russian-thesaurus/data.lua`:
```lua
local M = {}
return M
```

`lua/nvim-russian-thesaurus/query.lua`:
```lua
local M = {}
return M
```

`plugin/nvim-russian-thesaurus.lua`:
```lua
-- Будет реализовано позже
```

**Step 3: Create test fixture CSV**

`tests/fixtures/test-synsets.csv`:
```csv
id,words,grammar,domain
1,автомашина;машина;авто;автомобиль;тачка,n,транспортное
2,дом;жилище;жильё;обиталище,n,бытовое
3,машина;механизм;устройство;аппарат,n,техническое
4,быстрый;скорый;стремительный;проворный,adj,
5,бежать;мчаться;нестись,v,
```

Note: word "машина" appears in synsets 1 and 3 (multiple meanings) — important for testing.

**Step 4: Download yarn-synsets.csv**

```bash
curl -L -o data/yarn-synsets.csv https://github.com/russianwordnet/yarn/releases/download/eol/yarn-synsets.csv
```

Verify: `wc -l data/yarn-synsets.csv` should show ~180,000+ lines.
Verify: `head -2 data/yarn-synsets.csv` should show the CSV header and first data row.

**Step 5: Install busted for testing**

```bash
sudo luarocks install busted
```

Verify: `busted --version` prints version info.

**Step 6: Commit**

```bash
git add lua/ tests/ plugin/ data/yarn-synsets.csv
git commit -m "feat: scaffold project structure with YARN dataset"
```

---

### Task 2: Data Layer — CSV Line Parser (TDD)

**Files:**
- Create: `tests/data_spec.lua`
- Modify: `lua/nvim-russian-thesaurus/data.lua`

**Step 1: Write the failing test**

`tests/data_spec.lua`:
```lua
describe("nvim-russian-thesaurus.data", function()
  local data = require("lua.nvim-russian-thesaurus.data")

  describe("parse_line", function()
    it("парсит стандартную строку CSV", function()
      local result = data.parse_line("1,автомашина;машина;авто;автомобиль;тачка,n,транспортное")
      assert.are.equal("n", result.grammar)
      assert.are.equal("транспортное", result.domain)
      assert.are.same({"автомашина", "машина", "авто", "автомобиль", "тачка"}, result.words)
    end)

    it("парсит строку с пустым доменом", function()
      local result = data.parse_line("4,быстрый;скорый;стремительный;проворный,adj,")
      assert.are.equal("adj", result.grammar)
      assert.are.equal("", result.domain)
      assert.are.same({"быстрый", "скорый", "стремительный", "проворный"}, result.words)
    end)

    it("парсит строку с одним словом", function()
      local result = data.parse_line("99,одинокое,n,тест")
      assert.are.same({"одинокое"}, result.words)
    end)

    it("возвращает nil для пустой строки", function()
      assert.is_nil(data.parse_line(""))
    end)

    it("возвращает nil для строки заголовка", function()
      assert.is_nil(data.parse_line("id,words,grammar,domain"))
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

```bash
busted tests/data_spec.lua --verbose
```

Expected: FAIL — `parse_line` is not defined.

**Step 3: Write minimal implementation**

Add to `lua/nvim-russian-thesaurus/data.lua`:
```lua
local M = {}

--- Парсит одну строку CSV файла yarn-synsets.csv.
---
--- Args:
---   line: Строка CSV в формате "id,слова;через;точкуСЗапятой,грамматика,домен".
---
--- Returns:
---   Таблица {words={...}, grammar=str, domain=str} или nil для пустых/заголовочных строк.
function M.parse_line(line)
  if not line or line == "" then
    return nil
  end

  local id, words_str, grammar, domain = line:match("^(%d+),(.+),([^,]*),([^,]*)$")
  if not id then
    return nil
  end

  local words = {}
  for word in words_str:gmatch("[^;]+") do
    words[#words + 1] = word
  end

  return {
    words = words,
    grammar = grammar or "",
    domain = domain or "",
  }
end

return M
```

**Step 4: Run test to verify it passes**

```bash
busted tests/data_spec.lua --verbose
```

Expected: all 5 tests PASS.

**Step 5: Commit**

```bash
git add tests/data_spec.lua lua/nvim-russian-thesaurus/data.lua
git commit -m "feat(data): add CSV line parser with tests"
```

---

### Task 3: Data Layer — Index Builder (TDD)

**Files:**
- Modify: `tests/data_spec.lua`
- Modify: `lua/nvim-russian-thesaurus/data.lua`

**Step 1: Write the failing test**

Append to `tests/data_spec.lua` inside the outer `describe` block:
```lua
  describe("build_index", function()
    local index

    setup(function()
      local lines = {
        "1,автомашина;машина;авто;автомобиль;тачка,n,транспортное",
        "2,дом;жилище;жильё;обиталище,n,бытовое",
        "3,машина;механизм;устройство;аппарат,n,техническое",
      }
      index = data.build_index(lines)
    end)

    it("индексирует каждое слово из синсета", function()
      assert.is_not_nil(index["автомашина"])
      assert.is_not_nil(index["машина"])
      assert.is_not_nil(index["дом"])
      assert.is_not_nil(index["механизм"])
    end)

    it("исключает само слово из списка синонимов", function()
      local entries = index["автомашина"]
      assert.are.equal(1, #entries)
      local synonyms = entries[1].synonyms
      for _, syn in ipairs(synonyms) do
        assert.are_not.equal("автомашина", syn)
      end
      assert.are.equal(4, #synonyms) -- машина, авто, автомобиль, тачка
    end)

    it("поддерживает слово в нескольких синсетах", function()
      local entries = index["машина"]
      assert.are.equal(2, #entries)

      -- Один entry из транспортного синсета, другой из технического
      local domains = {}
      for _, entry in ipairs(entries) do
        domains[#domains + 1] = entry.domain
      end
      table.sort(domains)
      assert.are.same({"техническое", "транспортное"}, domains)
    end)

    it("индексирует ключи в нижнем регистре", function()
      assert.is_not_nil(index["дом"])
      assert.is_nil(index["Дом"]) -- uppercase key should not exist
    end)

    it("сохраняет грамматику и домен", function()
      local entries = index["дом"]
      assert.are.equal(1, #entries)
      assert.are.equal("n", entries[1].grammar)
      assert.are.equal("бытовое", entries[1].domain)
    end)
  end)
```

**Step 2: Run test to verify it fails**

```bash
busted tests/data_spec.lua --verbose
```

Expected: FAIL — `build_index` is not defined.

**Step 3: Write minimal implementation**

Add to `lua/nvim-russian-thesaurus/data.lua` before `return M`:
```lua
--- Строит индекс синонимов из массива строк CSV.
---
--- Args:
---   lines: Массив строк в формате yarn-synsets.csv (без заголовка).
---
--- Returns:
---   Таблица {[слово_в_нижнем_регистре] = {{grammar=str, domain=str, synonyms={...}}, ...}}.
function M.build_index(lines)
  local index = {}

  for _, line in ipairs(lines) do
    local parsed = M.parse_line(line)
    if parsed and #parsed.words > 1 then
      for i, word in ipairs(parsed.words) do
        local key = word:lower()
        local synonyms = {}
        for j, other in ipairs(parsed.words) do
          if j ~= i then
            synonyms[#synonyms + 1] = other
          end
        end

        if not index[key] then
          index[key] = {}
        end

        index[key][#index[key] + 1] = {
          grammar = parsed.grammar,
          domain = parsed.domain,
          synonyms = synonyms,
        }
      end
    end
  end

  return index
end
```

**Step 4: Run test to verify it passes**

```bash
busted tests/data_spec.lua --verbose
```

Expected: all 10 tests PASS.

**Step 5: Commit**

```bash
git add tests/data_spec.lua lua/nvim-russian-thesaurus/data.lua
git commit -m "feat(data): add index builder with multi-synset support"
```

---

### Task 4: Data Layer — File Loading & Lookup (TDD)

**Files:**
- Modify: `tests/data_spec.lua`
- Modify: `lua/nvim-russian-thesaurus/data.lua`

**Step 1: Write the failing test**

Append to `tests/data_spec.lua` inside the outer `describe` block:
```lua
  describe("load_file", function()
    it("загружает CSV файл и строит индекс", function()
      local index = data.load_file("tests/fixtures/test-synsets.csv")
      assert.is_not_nil(index)
      assert.is_not_nil(index["автомашина"])
      assert.is_not_nil(index["дом"])
      assert.is_not_nil(index["быстрый"])
    end)

    it("возвращает nil и сообщение для несуществующего файла", function()
      local index, err = data.load_file("nonexistent.csv")
      assert.is_nil(index)
      assert.is_string(err)
    end)
  end)

  describe("lookup", function()
    setup(function()
      data.reset()
      data.init("tests/fixtures/test-synsets.csv")
    end)

    it("находит синонимы для существующего слова", function()
      local results = data.lookup("дом")
      assert.is_not_nil(results)
      assert.are.equal(1, #results)
      assert.are.equal("n", results[1].grammar)
      assert.are.equal("бытовое", results[1].domain)
      assert.are.same({"жилище", "жильё", "обиталище"}, results[1].synonyms)
    end)

    it("находит несколько значений для многозначного слова", function()
      local results = data.lookup("машина")
      assert.is_not_nil(results)
      assert.are.equal(2, #results)
    end)

    it("поиск регистронезависимый", function()
      local results = data.lookup("Дом")
      assert.is_not_nil(results)
      assert.are.equal(1, #results)
    end)

    it("возвращает nil для несуществующего слова", function()
      local results = data.lookup("абракадабра")
      assert.is_nil(results)
    end)
  end)
```

**Step 2: Run test to verify it fails**

```bash
busted tests/data_spec.lua --verbose
```

Expected: FAIL — `load_file`, `lookup`, `init`, `reset` are not defined.

**Step 3: Write minimal implementation**

Add to `lua/nvim-russian-thesaurus/data.lua` before `return M`:
```lua
local _index = nil

--- Загружает CSV файл и строит индекс синонимов.
---
--- Args:
---   filepath: Путь к файлу yarn-synsets.csv.
---
--- Returns:
---   Индексная таблица или nil и сообщение об ошибке.
function M.load_file(filepath)
  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Ошибка: не удалось открыть файл: " .. (err or filepath)
  end

  local lines = {}
  local first = true
  for line in file:lines() do
    if first then
      first = false -- пропускаем заголовок
    else
      lines[#lines + 1] = line
    end
  end
  file:close()

  return M.build_index(lines)
end

--- Инициализирует модуль данных, загружая указанный CSV файл.
---
--- Args:
---   filepath: Путь к файлу yarn-synsets.csv.
---
--- Returns:
---   true при успехе, nil и сообщение об ошибке при неудаче.
function M.init(filepath)
  local index, err = M.load_file(filepath)
  if not index then
    return nil, err
  end
  _index = index
  return true
end

--- Ищет синонимы для заданного слова.
---
--- Args:
---   word: Слово для поиска (регистронезависимо).
---
--- Returns:
---   Массив {{grammar=str, domain=str, synonyms={...}}, ...} или nil если не найдено.
function M.lookup(word)
  if not _index then
    return nil
  end
  return _index[word:lower()]
end

--- Сбрасывает кэш индекса.
function M.reset()
  _index = nil
end
```

**Step 4: Run test to verify it passes**

```bash
busted tests/data_spec.lua --verbose
```

Expected: all 14 tests PASS.

**Step 5: Commit**

```bash
git add tests/data_spec.lua lua/nvim-russian-thesaurus/data.lua
git commit -m "feat(data): add file loading, lazy init, and lookup API"
```

---

### Task 5: Query Module — Synonym Selection & Replacement

**Files:**
- Modify: `lua/nvim-russian-thesaurus/query.lua`

This module depends on Neovim APIs (`vim.*`), so it cannot be tested with busted standalone. Implementation only.

**Step 1: Implement query.lua**

`lua/nvim-russian-thesaurus/query.lua`:
```lua
local data = require("nvim-russian-thesaurus.data")

local M = {}

--- Получает текст визуального выделения.
---
--- Returns:
---   Выделенный текст или nil.
local function get_visual_selection()
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))
  if ls ~= le then
    return nil -- многострочное выделение не поддерживается
  end
  local line = vim.api.nvim_buf_get_lines(0, ls - 1, ls, false)[1]
  if not line then
    return nil
  end
  return line:sub(cs, ce)
end

--- Заменяет слово под курсором или визуальное выделение на указанный текст.
---
--- Args:
---   replacement: Текст для замены.
---   mode: Режим вызова ("n" или "v").
local function replace_text(replacement, mode)
  if mode == "v" then
    local _, ls, cs = unpack(vim.fn.getpos("'<"))
    local _, le, ce = unpack(vim.fn.getpos("'>"))
    local line = vim.api.nvim_buf_get_lines(0, ls - 1, ls, false)[1]
    local new_line = line:sub(1, cs - 1) .. replacement .. line:sub(ce + 1)
    vim.api.nvim_buf_set_lines(0, ls - 1, le, false, { new_line })
  else
    vim.cmd("normal! ciw" .. replacement)
    vim.cmd("stopinsert")
  end
end

--- Форматирует результаты поиска для vim.ui.select.
---
--- Args:
---   results: Массив результатов из data.lookup().
---
--- Returns:
---   Массив элементов {display=str, value=str} для vim.ui.select.
local function format_items(results)
  local items = {}
  for _, entry in ipairs(results) do
    local prefix = ""
    if entry.grammar ~= "" or entry.domain ~= "" then
      local parts = {}
      if entry.grammar ~= "" then
        parts[#parts + 1] = entry.grammar
      end
      if entry.domain ~= "" then
        parts[#parts + 1] = entry.domain
      end
      prefix = "[" .. table.concat(parts, "/") .. "] "
    end
    for _, synonym in ipairs(entry.synonyms) do
      items[#items + 1] = {
        display = prefix .. synonym,
        value = synonym,
      }
    end
  end
  return items
end

--- Основная функция: ищет синонимы и предлагает замену.
---
--- Args:
---   opts: Таблица опций. opts.mode — режим ("n" или "v"). opts.word — слово для поиска (опционально).
function M.query_replace(opts)
  opts = opts or {}
  local mode = opts.mode or "n"

  local word
  if opts.word and opts.word ~= "" then
    word = opts.word
  elseif mode == "v" then
    word = get_visual_selection()
  else
    word = vim.fn.expand("<cword>")
  end

  if not word or word == "" then
    return
  end

  local results = data.lookup(word)
  if not results then
    vim.notify("Синонимы не найдены: " .. word, vim.log.levels.WARN)
    return
  end

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

return M
```

**Step 2: Commit**

```bash
git add lua/nvim-russian-thesaurus/query.lua
git commit -m "feat(query): add synonym lookup, selection UI, and text replacement"
```

---

### Task 6: Plugin Init & Command Registration

**Files:**
- Modify: `lua/nvim-russian-thesaurus/init.lua`
- Modify: `plugin/nvim-russian-thesaurus.lua`

**Step 1: Implement init.lua**

`lua/nvim-russian-thesaurus/init.lua`:
```lua
local data = require("nvim-russian-thesaurus.data")
local query = require("nvim-russian-thesaurus.query")

local M = {}

local defaults = {
  data_file = nil, -- автоопределение: data/yarn-synsets.csv внутри плагина
  keys = {
    query_replace = "<leader>ch",
  },
}

local config = {}

--- Определяет путь к файлу данных по умолчанию (bundled yarn-synsets.csv).
---
--- Returns:
---   Абсолютный путь к data/yarn-synsets.csv внутри директории плагина.
local function default_data_file()
  local source = debug.getinfo(1, "S").source:sub(2) -- убираем '@'
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h") -- lua/nvim-russian-thesaurus/ → корень плагина
  return plugin_dir .. "/data/yarn-synsets.csv"
end

--- Настраивает плагин.
---
--- Args:
---   opts: Таблица пользовательских настроек (опционально). Мержится с defaults.
function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})

  local data_file = config.data_file or default_data_file()
  local ok, err = data.init(data_file)
  if not ok then
    vim.notify("nvim-russian-thesaurus: " .. (err or "Ошибка загрузки данных"), vim.log.levels.ERROR)
    return
  end

  -- Keymaps
  local key = config.keys.query_replace
  if key then
    vim.keymap.set("n", key, function()
      query.query_replace({ mode = "n" })
    end, { desc = "Синонимы" })

    vim.keymap.set("x", key, function()
      -- Сначала выходим из визуального режима чтобы установить '< и '>
      vim.cmd("normal! ")
      vim.schedule(function()
        query.query_replace({ mode = "v" })
      end)
    end, { desc = "Синонимы" })
  end
end

--- Публичный API для вызова поиска синонимов.
---
--- Args:
---   opts: Таблица опций, передаётся в query.query_replace().
function M.query_replace(opts)
  query.query_replace(opts)
end

return M
```

**Step 2: Implement command registration**

`plugin/nvim-russian-thesaurus.lua`:
```lua
if vim.g.loaded_nvim_russian_thesaurus then
  return
end
vim.g.loaded_nvim_russian_thesaurus = true

vim.api.nvim_create_user_command("ThesaurusQuery", function(cmd_opts)
  local word = cmd_opts.args ~= "" and cmd_opts.args or nil
  require("nvim-russian-thesaurus").query_replace({ word = word, mode = "n" })
end, {
  nargs = "?",
  desc = "Поиск синонимов для слова",
})
```

**Step 3: Commit**

```bash
git add lua/nvim-russian-thesaurus/init.lua plugin/nvim-russian-thesaurus.lua
git commit -m "feat: add plugin setup, keymaps, and :ThesaurusQuery command"
```

---

### Task 7: Integration Smoke Test

**Step 1: Test the plugin in Neovim**

Create a temporary test file and load the plugin manually:

```bash
nvim --cmd "set rtp+=." -c "lua require('nvim-russian-thesaurus').setup()" /tmp/test-thesaurus.txt
```

Inside Neovim:
1. Type `автомобиль` in the buffer
2. Place cursor on the word
3. Press `<leader>ch`
4. Verify: picker appears with synonyms like автомашина, машина, авто, тачка
5. Select one — verify it replaces the word

Test `:ThesaurusQuery дом` — verify picker shows жилище, жильё, обиталище.

Test with a non-existent word: `:ThesaurusQuery абракадабра` — verify warning notification.

**Step 2: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address issues found during integration testing"
```
