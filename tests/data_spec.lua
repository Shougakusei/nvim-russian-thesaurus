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
      pending("в busted нет vim.fn.tolower(); в Neovim кириллица обрабатывается корректно")
      local results = data.lookup("Дом")
      assert.is_not_nil(results)
      assert.are.equal(1, #results)
    end)

    it("возвращает nil для несуществующего слова", function()
      local results = data.lookup("абракадабра")
      assert.is_nil(results)
    end)
  end)
end)
