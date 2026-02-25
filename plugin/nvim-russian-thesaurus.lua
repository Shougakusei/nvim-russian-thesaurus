if vim.g.loaded_nvim_russian_thesaurus then
  return
end
vim.g.loaded_nvim_russian_thesaurus = true

vim.api.nvim_create_user_command("ThesaurusQuery", function(cmd_opts)
  local word = cmd_opts.args ~= "" and cmd_opts.args or nil
  require("nvim-russian-thesaurus").query_replace({ word = word, mode = "n" })
end, {
  nargs = "?",
  desc = "Поиск синонимов для слова",
})
