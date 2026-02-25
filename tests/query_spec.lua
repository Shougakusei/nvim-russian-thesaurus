-- Предзагрузка зависимостей query.lua под именами, которые он ожидает.
package.preload["nvim-russian-thesaurus.data"] = function()
  return require("lua.nvim-russian-thesaurus.data")
end
package.preload["nvim-russian-thesaurus.morph"] = function()
  return require("lua.nvim-russian-thesaurus.morph")
end

describe("nvim-russian-thesaurus.query", function()
  local query = require("lua.nvim-russian-thesaurus.query")

  describe("format_items", function()
    it("форматирует элементы с грамматикой и доменом", function()
      local results = {
        {
          grammar = "n",
          domain = "транспортное",
          synonyms = { "автомашина", "авто", "автомобиль" },
        },
      }
      local items = query._format_items(results)
      assert.are.equal(3, #items)
      assert.are.equal("[n/транспортное] автомашина", items[1].display)
      assert.are.equal("автомашина", items[1].value)
    end)

    it("удаляет дубликаты синонимов из разных синсетов", function()
      local results = {
        {
          grammar = "n",
          domain = "транспортное",
          synonyms = { "автомашина", "авто", "автомобиль", "тачка" },
        },
        {
          grammar = "n",
          domain = "техническое",
          synonyms = { "механизм", "устройство", "автомобиль", "аппарат" },
        },
      }
      local items = query._format_items(results)

      local values = {}
      for _, item in ipairs(items) do
        values[#values + 1] = item.value
      end

      -- "автомобиль" присутствует в обоих синсетах, но должен появиться только один раз
      local count = 0
      for _, v in ipairs(values) do
        if v == "автомобиль" then
          count = count + 1
        end
      end
      assert.are.equal(1, count)
      assert.are.equal(7, #items) -- 4 + 4 - 1 дубликат
    end)

    it("сохраняет первое вхождение дубликата", function()
      local results = {
        {
          grammar = "n",
          domain = "транспортное",
          synonyms = { "авто" },
        },
        {
          grammar = "n",
          domain = "техническое",
          synonyms = { "авто" },
        },
      }
      local items = query._format_items(results)
      assert.are.equal(1, #items)
      assert.are.equal("[n/транспортное] авто", items[1].display)
    end)
  end)
end)
