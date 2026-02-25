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
  local was_ready = _ready
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

  -- Не перезапускаем при завершении Neovim — иначе новый процесс
  -- не будет убит (VimLeavePre уже отработал) и заблокирует выход.
  if vim.v.dying > 0 or vim.v.exiting ~= vim.NIL then
    return
  end

  if exit_code ~= 0 and not was_ready and _restart_attempted then
    warn_once("процесс завершился с кодом " .. exit_code .. " (pymorphy3 установлен?)")
    return
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
