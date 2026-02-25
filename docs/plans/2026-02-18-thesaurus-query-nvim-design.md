# nvim-russian-thesaurus — Design Document

Russian-language thesaurus/synonym lookup plugin for Neovim (LazyVim), written in Lua.
A focused clone of [thesaurus_query.vim](https://github.com/Ron89/thesaurus_query.vim), supporting only Russian via the YARN dataset.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data source | Local file only (yarn-synsets.csv) | No network dependency, works offline |
| Database | YARN (Yet Another RussNet) | Same as original plugin, well-structured, CC BY-SA |
| Distribution | CSV bundled in repo (~20MB) | Simplest for users, no download step |
| Architecture | Lazy-loaded Lua table | O(1) lookups after ~100-200ms initial parse |
| UI | `vim.ui.select()` | Integrates with telescope/fzf-lua/dressing.nvim |
| Modes | Normal + Visual | Word under cursor or selected text |
| Keybinding | `<leader>ch` | Free in LazyVim defaults |

## Plugin Structure

```
nvim-russian-thesaurus/
├── lua/
│   └── nvim-russian-thesaurus/
│       ├── init.lua          -- setup(), public API
│       ├── data.lua          -- CSV parser, in-memory index
│       └── query.lua         -- lookup logic, vim.ui.select integration
├── data/
│   └── yarn-synsets.csv      -- bundled YARN database (~20MB)
├── plugin/
│   └── nvim-russian-thesaurus.lua   -- user command registration
└── README.md
```

### Module responsibilities

- **`init.lua`** — `setup(opts)` merges user config with defaults, sets up keymaps, exposes `query_replace()`.
- **`data.lua`** — Parses CSV on first call, builds `word → [{grammar, domain, synonyms}]` index. Cached for the session.
- **`query.lua`** — Gets word under cursor / visual selection, calls data module, presents via `vim.ui.select()`, replaces text in buffer.
- **`plugin/nvim-russian-thesaurus.lua`** — Registers `:ThesaurusQuery` command.

## Data Layer

### CSV format (yarn-synsets.csv)

```
id,words,grammar,domain
1,автомашина;машина;колёса;драндулет;авто;автомобиль;тачка,n,транспортное
```

Columns: `id` (integer), `words` (semicolon-separated), `grammar` (part of speech), `domain` (subject area).

### In-memory index

```lua
-- Lowercase word → list of synset entries
{
  ["автомобиль"] = {
    {
      grammar = "n",
      domain = "транспортное",
      synonyms = {"автомашина", "машина", "колёса", "драндулет", "авто", "тачка"},
    },
  },
  ["машина"] = {
    {
      grammar = "n",
      domain = "транспортное",
      synonyms = {"автомашина", "колёса", "драндулет", "авто", "автомобиль", "тачка"},
    },
  },
}
```

- Parse is lazy — triggered on first query only.
- Each word in a synset gets its own entry pointing to the other words (excluding itself).
- Lookup keys are lowercase. Synonym values preserve original case from CSV.
- Words appearing in multiple synsets have multiple entries (multiple meanings).

## Query & UI Flow

1. User triggers via `<leader>ch` (normal/visual) or `:ThesaurusQuery [word]`.
2. **Normal mode:** `vim.fn.expand("<cword>")` gets word under cursor.
3. **Visual mode:** extract selected text via register.
4. Look up word in index (case-insensitive).
5. No results → `vim.notify("Синонимы не найдены: <word>", vim.log.levels.WARN)`.
6. Results found → format for `vim.ui.select()`:
   - Items displayed as `"[grammar/domain] synonym"`, e.g. `"[n/транспортное] автомашина"`.
   - Grouped by synset (meaning).
7. User picks synonym → replace original word/selection in buffer.

```lua
vim.ui.select(formatted_items, {
  prompt = "Синонимы для: " .. word,
  format_item = function(item) return item.display end,
}, function(choice)
  if choice then replace_word(choice.value) end
end)
```

## Configuration

```lua
require("nvim-russian-thesaurus").setup({
  data_file = nil,  -- auto-resolves to bundled data/yarn-synsets.csv
  keys = {
    query_replace = "<leader>ch",  -- normal + visual mode
  },
})
```

### LazyVim plugin spec

```lua
{
  "user/nvim-russian-thesaurus",
  keys = {
    { "<leader>ch", mode = { "n", "x" }, desc = "Синонимы" },
  },
  cmd = "ThesaurusQuery",
  opts = {},
}
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Word not found | `vim.notify("Синонимы не найдены: <word>", WARN)` |
| CSV missing/corrupt | `vim.notify("Ошибка: не удалось загрузить yarn-synsets.csv", ERROR)` |
| Empty selection / no word | Do nothing |
| User cancels picker | Do nothing (standard vim.ui.select cancel) |
| Case handling | Lowercase for lookup, preserve original case from DB for replacement |
