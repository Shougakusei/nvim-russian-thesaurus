local data = require("nvim-russian-thesaurus.data")
local morph = require("nvim-russian-thesaurus.morph")
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

  morph.start()

  -- Keymaps
  local key = config.keys.query_replace
  if key then
    vim.keymap.set("n", key, function()
      query.query_replace({ mode = "n" })
    end, { desc = "Синонимы" })

    vim.keymap.set("x", key, function()
      -- Сначала выходим из визуального режима чтобы установить '< и '>
      vim.cmd("normal! \27")
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
