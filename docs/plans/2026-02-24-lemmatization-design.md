# Lemmatization for Russian Word Forms

## Problem

The thesaurus only finds synonyms for words in their base/dictionary form. Inflected
forms (e.g., "серая" instead of "серый") return no results, even though the base form
has 26 synonyms. Russian has rich morphology — nouns decline across 6 cases and 2
numbers, adjectives also inflect for 3 genders, verbs conjugate — so this is a
significant usability gap.

## Solution

Add an optional persistent Python process that uses pymorphy3 to lemmatize input words.
When an exact thesaurus match fails, the plugin asks the Python process for the word's
base form and retries the lookup.

## Architecture

```
lua/nvim-russian-thesaurus/
  ├── init.lua      (setup — starts morph process)
  ├── data.lua      (CSV index, lookup — unchanged)
  ├── query.lua     (query flow — tries lemmatization on miss)
  └── morph.lua     (NEW: Python process management + lemmatize API)
scripts/
  └── morph_server.py  (NEW: persistent Python lemmatizer)
```

### Query Flow

```
query_replace("серая")
  → data.lookup("серая")        -- exact match (fast, pure Lua)
  → nil (not found)
  → morph.lemmatize("серая")    -- ask Python process → "серый"
  → data.lookup("серый")        -- lookup with lemma
  → 26 synonyms found
```

Exact matches bypass Python entirely. The morph module is fully optional — if
Python/pymorphy3 is unavailable, the plugin behaves exactly as before.

## Python Process Lifecycle

**Startup:** Eager — process starts during `setup()`. The Python script prints `"READY"`
after pymorphy3 initialization completes. `morph.lua` waits for this signal before
marking the process as available.

**Protocol:** Line-based stdin/stdout.

```
→ stdin:  "серая\n"
← stdout: "серый\n"

→ stdin:  "бегущий\n"
← stdout: "бежать\n"

→ stdin:  "unknownword\n"
← stdout: "unknownword\n"   (returns input unchanged)
```

**Shutdown:** `VimLeavePre` autocmd calls `vim.fn.jobstop()`.

**Error recovery:** If the process dies mid-session, attempt one restart. If restart
fails, fall back to synchronous `vim.fn.system()` for the current query and stop
retrying.

**Timeout:** 2-second timeout per query. No response in time → treat as "not found."

## Python Script (`scripts/morph_server.py`)

- Uses pymorphy3 (actively maintained fork, same API as pymorphy2)
- Takes top parse result (`parsed[0].normal_form`) — pymorphy ranks by probability
- `flush=True` on all prints to prevent buffering
- Prints `"READY"` after initialization

## Lua Module (`morph.lua`)

- `M.start()` — start the Python process, register VimLeavePre cleanup
- `M.lemmatize(word, callback)` — async: send word, call callback with lemma
- `M.stop()` — kill the process
- `M.is_ready()` — check if process is available
- Per-session cache (`_cache` table) — skip Python call for previously seen words

## Changes to Existing Code

**`query.lua`:** When `data.lookup(word)` returns nil, call `morph.lemmatize(word, cb)`
and retry lookup with the returned lemma. The existing `vim.ui.select()` callback flow
accommodates this naturally.

**`init.lua`:** Call `morph.start()` during `setup()`.

## Dependency

- pymorphy3 (`pip install pymorphy3`) — optional
- Python 3.8+ — optional

## Fallback Behavior

- If Python not found or pymorphy3 not installed → one-time warning at startup
- Plugin continues to work with exact match only (current behavior)

## Synonyms Output

Synonyms are shown in their base/dictionary forms as stored in the thesaurus.
No inflection of output synonyms.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Process model | Persistent subprocess | ~5ms per query vs ~300-500ms for per-call |
| Startup | Eager (at init) | First query is always fast |
| pymorphy version | pymorphy3 only | Actively maintained, good Python 3.10+ support |
| Lemma candidates | Top result only | Simplest, correct for vast majority of words |
| Output form | Base forms | Reliable, no inflection errors |
| Fallback | One-time warning + exact match | Clean degradation, non-intrusive |
