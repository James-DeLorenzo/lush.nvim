-- Head exporter, accepts an AST, returns a table of strings,
--
-- Exports the given theme as a lua-configurable function
local value_or_NONE = require("lush.compiler.plugin.utils").value_or_NONE
local is_spec = require("lush.transform.helpers").is_lush_spec

local build_function_code = [[
-- Generated by lush builder on $LUSH_BUILD_DATE
--
-- You can configure how this build function operates by passing in optional
-- function handlers via the options table.
--
-- See each default handler below for guidance on writing your own.
--
-- {
--   configure_group_fn = function(group) ... end,
--   generate_group_fn = function(group) .. end,
--   before_apply_fn = function(rules) ... end,
--   apply_fn = function(rules) ... end,
-- }

local lush_groups = {
$LUSH_GROUPS
}

local lush_apply = function(groups, opts)
  -- we may not always get given any options, so act safely
  local options = opts or {}

  -- configure_group(group) -> group
  --
  -- Accepts a group table (group.name, group.type (link or group) and
  -- group.data (table of fg, bg, gui, sp and blend)). Should return the group
  -- data with any desired alterations.
  --
  -- By default we make no modifications.
  local configure_group = options.configure_group_fn or
    function(group)
      -- by default don't modify anything
      return group
    end

  -- generate_group(group) -> any
  --
  -- Accepts a group table (group.name, group.type (link or group) and
  -- group.data (table of fg, bg, gui, sp and blend)). Should return something
  -- which apply() knows how to handle.
  --
  -- By default we generate a viml highlight rule.
  local generate_group = options.generate_group_fn or
    function(group)
      if group.type == "link" then
        return string.format("highlight! link %s %s", group.name, group.data.to)
      elseif group.type == "group" then
        return string.format("highlight! %s guifg=%s guibg=%s guisp=%s gui=%s blend=%s",
          group.name,
          group.data.fg, group.data.bg, group.data.sp, group.data.gui, group.data.blend)
      else
        error("unknown group type: " .. group.type .. " for group " .. group.name)
      end
    end

  -- apply(any) -> any
  --
  -- Accepts a list of something and does something with it.
  --
  -- By default we assume generate_group_fn has created a highlight
  -- rule for each group and we can simply pass those on to the vim
  -- interpreter.
  local apply = options.apply_fn or
    function(rules)
      -- just send all the rules through to vim
      for _, cmd in ipairs(rules) do
        vim.api.nvim_command(cmd)
      end
    end

  -- before_apply(any) -> any
  --
  -- Accepts a list of each group's result from generate_group_fn. Should
  -- return something apply_fn can understand.
  --
  -- By default, generate_group_fn returns a viml "highlight ..." command and
  -- apply_fn assumes it's recieving a list of commands to pass to vim.cmd, but
  -- you could for example, return a table of functions here and the apply_fn
  -- could call those functions.
  local before_apply = options.before_apply_fn or function(rules)
    -- by default we dont alter anything
    return rules
  end

  local rules = {}
  for _, group in ipairs(groups) do
    group = configure_group(group)
    table.insert(rules, generate_group(group))
  end

  rules = before_apply(rules)
  return apply(rules)
end
]]

local group_to_string = function(group_name, group_data)
  local link_str = [[    {name = "$GROUP_NAME",type = "link", data = {to = "$GROUP_TO"}},]]
  local group_str = [[    {name = "$GROUP_NAME", type = "group", data = {fg = "$GROUP_FG", bg = "$GROUP_BG", sp = "$GROUP_SP", gui = "$GROUP_GUI", blend = "$GROUP_BLEND"}},]]
  local subbed = nil
  if group_data.link then
    subbed = string.gsub(link_str, "%$([%w_]+)", {
      GROUP_NAME = group_name,
      GROUP_TO = group_data.link
    })
  else
    subbed = string.gsub(group_str, "%$([%w_]+)", {
      GROUP_NAME = group_name,
      GROUP_FG = value_or_NONE(group_data.fg),
      GROUP_BG = value_or_NONE(group_data.bg),
      GROUP_SP = value_or_NONE(group_data.sp),
      GROUP_GUI = value_or_NONE(group_data.gui),
      GROUP_BLEND = value_or_NONE(group_data.blend),
    })
  end

  return subbed
end

local ast_to_groups_string = function(ast)
  local groups = {}
  for name, data in pairs(ast) do
    table.insert(groups, group_to_string(name, data))
  end
  return table.concat(groups, "\n")
end

local transform = function(ast)
  assert(is_spec(ast),
    "first argument to lua transform must be a parsed lush spec")

  local groups = ast_to_groups_string(ast)
  local output = string.gsub(build_function_code, "$([%w_]+)", {
    LUSH_BUILD_DATE = os.date(),
    LUSH_GROUPS = groups
  })

  local lines = {}
  for s in string.gmatch(output, "[^\n]+") do
    table.insert(lines, s)
  end

  return lines
end

return transform
