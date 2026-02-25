# nvim-russian-thesaurus

Плагин для Neovim для поиска синонимов русских слов. Основан на базе данных [YARN (Yet Another RussNet)](https://russianword.net/).

## Возможности

- Поиск синонимов для слова под курсором или выделенного текста
- Замена слова выбранным синонимом
- ~70 000 синсетов из базы YARN (включена в репозиторий, ~4 МБ)
- Интеграция с `vim.ui.select()` — работает с [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua), [dressing.nvim](https://github.com/stevearc/dressing.nvim)
- Регистронезависимый поиск с поддержкой кириллицы
- Лемматизация: поиск синонимов для склонённых/спрягаемых форм (опционально, через pymorphy3)

## Требования

- Neovim >= 0.9
- Python 3.8+ и pymorphy3 (опционально — для лемматизации)

## Установка

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Shougakusei/nvim-russian-thesaurus",
  keys = {
    { "<leader>ch", mode = { "n", "x" }, desc = "Синонимы" },
  },
  cmd = "ThesaurusQuery",
  opts = {},
}
```

### [pckr.nvim](https://github.com/lewis6991/pckr.nvim)

```lua
{ "Shougakusei/nvim-russian-thesaurus",
  config = function()
    require("nvim-russian-thesaurus").setup()
  end,
}
```

### Вручную

Клонируйте репозиторий в директорию плагинов:

```bash
git clone https://github.com/Shougakusei/nvim-russian-thesaurus.git \
  ~/.local/share/nvim/site/pack/plugins/start/nvim-russian-thesaurus
```

Добавьте в `init.lua`:

```lua
require("nvim-russian-thesaurus").setup()
```

## Настройка

```lua
require("nvim-russian-thesaurus").setup({
  -- Путь к CSV файлу с синонимами.
  -- По умолчанию используется встроенный data/yarn-synsets.csv.
  data_file = nil,

  keys = {
    -- Клавиша для поиска синонимов (normal + visual mode).
    -- Установите false для отключения.
    query_replace = "<leader>ch",
  },
})
```

## Использование

| Действие | Команда |
|----------|---------|
| Синонимы для слова под курсором | `<leader>ch` в normal mode |
| Синонимы для выделенного текста | `<leader>ch` в visual mode |
| Синонимы для произвольного слова | `:ThesaurusQuery слово` |

После вызова откроется список синонимов. Выберите нужный — он заменит исходное слово в буфере.

## Лемматизация

Плагин может приводить слово к начальной форме (лемме) перед поиском синонимов. Это позволяет находить синонимы для склонённых и спрягаемых форм: например, «серая» → находит синонимы для «серый».

Для работы лемматизации установите pymorphy3:

```bash
pip install pymorphy3
```

Arch Linux:

```bash
yay -S python-pymorphy3
```

Без pymorphy3 плагин работает в штатном режиме — поиск выполняется только по точному совпадению.

## Источник данных

Плагин использует базу [YARN (Yet Another RussNet)](https://russianword.net/) — открытый тезаурус русского языка, распространяемый под лицензией [CC BY-SA](https://creativecommons.org/licenses/by-sa/4.0/).

## Лицензия

MIT
