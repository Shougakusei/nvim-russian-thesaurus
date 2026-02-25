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
