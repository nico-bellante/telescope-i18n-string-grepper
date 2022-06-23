local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"
local conf = require("telescope.config").values

local Path = require "plenary.path"

local flatten = vim.tbl_flatten

local escape_chars = function(string)
  return string.gsub(string, "[%(|%)|\\|%[|%]|%-|%{%}|%?|%+|%*|%^|%$|%.]", {
    ["\\"] = "\\\\",
    ["-"] = "\\-",
    ["("] = "\\(",
    [")"] = "\\)",
    ["["] = "\\[",
    ["]"] = "\\]",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["?"] = "\\?",
    ["+"] = "\\+",
    ["*"] = "\\*",
    ["^"] = "\\^",
    ["$"] = "\\$",
    ["."] = "\\.",
  })
end

local grep_code_for_keys = function(opts) 
  local vimgrep_arguments = opts.vimgrep_arguments or conf.vimgrep_arguments
  local search_dirs = opts.search_dirs
  local word = opts.search or vim.fn.expand "<cword>"
  local search = opts.use_regex and word or escape_chars(word)
  local word_match = opts.word_match
  opts.entry_maker = opts.entry_maker or make_entry.gen_from_vimgrep(opts)

  local additional_args = {}
  if opts.additional_args ~= nil and type(opts.additional_args) == "function" then
    additional_args = opts.additional_args(opts)
  end

  local args = flatten {
    vimgrep_arguments,
    additional_args,
    word_match,
    "--",
    search,
  }

  if search_dirs then
    for _, path in ipairs(search_dirs) do
      table.insert(args, vim.fn.expand(path))
    end
  end

  pickers.new(opts, {
    prompt_title = "Find Key (" .. word .. ")",
    finder = finders.new_oneshot_job(args, opts),
    previewer = conf.grep_previewer(opts),
    sorter = conf.generic_sorter(opts),
    file_ignore_patterns = {"i18n/messages", "typings/messages.d.ts"}
  }):find()
end

local find_strings = function(opts)
  local vimgrep_arguments = opts.vimgrep_arguments or conf.vimgrep_arguments
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()

  local filelist = {}
  table.insert(filelist, Path:new(opts.string_file_path):make_relative(opts.cwd))


  local additional_args = {}
  if opts.additional_args ~= nil and type(opts.additional_args) == "function" then
    additional_args = opts.additional_args(opts)
  end

  if opts.type_filter then
    additional_args[#additional_args + 1] = "--type=" .. opts.type_filter
  end

  if opts.glob_pattern then
    additional_args[#additional_args + 1] = "--glob=" .. opts.glob_pattern
  end

  local entry_maker = function(entry) 
    local full_string_key = string.gsub(entry, '.*i18n/messages/', ''):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[^%s]*%s+", "") 
    local string_key = string.gsub(full_string_key, ":.*", '')
    return {
      value = full_string_key,
      display = full_string_key,
      ordinal = full_string_key,
      key = string_key,
    }
  end

  local live_grepper = finders.new_job(function(prompt)
    -- TODO: Probably could add some options for smart case and whatever else rg offers.

    if not prompt or prompt == "" then
      return nil
    end

    local search_list = filelist

    print(prompt)

    local regex_prompt = "(['`\"])(?:(?=(\\\\?))\\2" .. prompt .. ")\\1"

    additional_args[#additional_args + 1] = "-P"
    additional_args[#additional_args + 1] = "--multiline"

    return flatten { vimgrep_arguments, additional_args, "--", regex_prompt, search_list }
  end, entry_maker, opts.max_results, opts.cwd)

  pickers.new(opts, {
    prompt_title = "Searching for i18n keys..",
    finder = live_grepper,
    -- previewer = conf.grep_previewer(opts),
    -- TODO: It would be cool to use `--json` output for this
    -- and then we could get the highlight positions directly.
    sorter = sorters.highlighter_only(opts),
    attach_mappings = function(prompt_bufnr, map)

      action_set.select:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()

        local g = string.gsub(selection.key, "^%s+", ""):gsub("%s+$", "")

        local new_filelist = {}
        table.insert(new_filelist, Path:new(opts.repo_root):make_relative(opts.cwd))
        grep_code_for_keys({search = g, search_dirs = new_filelist})

      end)
      return true
    end,
  }):find()
end


return require("telescope").register_extension {
  exports = {
    find_strings = find_strings
  }
}
