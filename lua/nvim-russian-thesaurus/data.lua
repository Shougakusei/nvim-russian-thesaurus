local M = {}

--- Приводит строку к нижнему регистру с поддержкой UTF-8.
---
--- Использует vim.fn.tolower() в Neovim (корректно для кириллицы),
--- string.lower() в качестве fallback (только ASCII).
---
--- Args:
---   s: Строка для приведения к нижнему регистру.
---
--- Returns:
---   Строка в нижнем регистре.
local function lowercase(s)
  if vim and vim.fn and vim.fn.tolower then
    return vim.fn.tolower(s)
  end
  return s:lower()
end

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
        local key = lowercase(word)
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
  return _index[lowercase(word)]
end

--- Сбрасывает кэш индекса.
function M.reset()
  _index = nil
end

return M
