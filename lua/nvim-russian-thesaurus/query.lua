local data = require("nvim-russian-thesaurus.data")
local morph = require("nvim-russian-thesaurus.morph")

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
  local seen = {}
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
      if not seen[synonym] then
        seen[synonym] = true
        items[#items + 1] = {
          display = prefix .. synonym,
          value = synonym,
        }
      end
    end
  end
  return items
end

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
    local lemma_results = nil
    -- Если лемма совпадает со словом — повторный поиск не нужен
    if lemma and lemma ~= word then
      lemma_results = data.lookup(lemma)
    end
    if lemma_results then
      show_results(lemma_results, word, mode)
    else
      vim.notify("Синонимы не найдены: " .. word, vim.log.levels.WARN)
    end
  end)
end

M._format_items = format_items

return M
