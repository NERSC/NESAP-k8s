#!/usr/bin/env lua
do
local _ENV = _ENV
package.preload[ "F" ] = function( ... ) local arg = _G.arg;
local F = {}

local load = load

if _VERSION == "Lua 5.1" then
   load = function(code, name, _, env)
      local fn, err = loadstring(code, name)
      if fn then
         setfenv(fn, env)
         return fn
      end
      return nil, err
   end
end

local function scan_using(scanner, arg, searched)
   local i = 1
   repeat
      local name, value = scanner(arg, i)
      if name == searched then
         return true, value
      end
      i = i + 1
   until name == nil
   return false
end

local function snd(_, b) return b end

local function format(_, str)
   local outer_env = _ENV and (snd(scan_using(debug.getlocal, 3, "_ENV")) or snd(scan_using(debug.getupvalue, debug.getinfo(2, "f").func, "_ENV")) or _ENV) or getfenv(2)
   return (str:gsub("%b{}", function(block)
      local code, fmt = block:match("{(.*):(%%.*)}")
      code = code or block:match("{(.*)}")
      local exp_env = {}
      setmetatable(exp_env, { __index = function(_, k)
         local level = 6
         while true do
            local funcInfo = debug.getinfo(level, "f")
            if not funcInfo then break end
            local ok, value = scan_using(debug.getupvalue, funcInfo.func, k)
            if ok then return value end
            ok, value = scan_using(debug.getlocal, level + 1, k)
            if ok then return value end
            level = level + 1
         end
         return rawget(outer_env, k)
      end })
      local fn, err = load("return "..code, "expression `"..code.."`", "t", exp_env)
      if fn then
         return fmt and string.format(fmt, fn()) or tostring(fn())
      else
         error(err, 0)
      end         
   end))
end

setmetatable(F, {
   __call = format
})

return F
end
end

do
local _ENV = _ENV
package.preload[ "argparse" ] = function( ... ) local arg = _G.arg;
-- The MIT License (MIT)

-- Copyright (c) 2013 - 2018 Peter Melnichenko

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local function deep_update(t1, t2)
   for k, v in pairs(t2) do
      if type(v) == "table" then
         v = deep_update({}, v)
      end

      t1[k] = v
   end

   return t1
end

-- A property is a tuple {name, callback}.
-- properties.args is number of properties that can be set as arguments
-- when calling an object.
local function class(prototype, properties, parent)
   -- Class is the metatable of its instances.
   local cl = {}
   cl.__index = cl

   if parent then
      cl.__prototype = deep_update(deep_update({}, parent.__prototype), prototype)
   else
      cl.__prototype = prototype
   end

   if properties then
      local names = {}

      -- Create setter methods and fill set of property names.
      for _, property in ipairs(properties) do
         local name, callback = property[1], property[2]

         cl[name] = function(self, value)
            if not callback(self, value) then
               self["_" .. name] = value
            end

            return self
         end

         names[name] = true
      end

      function cl.__call(self, ...)
         -- When calling an object, if the first argument is a table,
         -- interpret keys as property names, else delegate arguments
         -- to corresponding setters in order.
         if type((...)) == "table" then
            for name, value in pairs((...)) do
               if names[name] then
                  self[name](self, value)
               end
            end
         else
            local nargs = select("#", ...)

            for i, property in ipairs(properties) do
               if i > nargs or i > properties.args then
                  break
               end

               local arg = select(i, ...)

               if arg ~= nil then
                  self[property[1]](self, arg)
               end
            end
         end

         return self
      end
   end

   -- If indexing class fails, fallback to its parent.
   local class_metatable = {}
   class_metatable.__index = parent

   function class_metatable.__call(self, ...)
      -- Calling a class returns its instance.
      -- Arguments are delegated to the instance.
      local object = deep_update({}, self.__prototype)
      setmetatable(object, self)
      return object(...)
   end

   return setmetatable(cl, class_metatable)
end

local function typecheck(name, types, value)
   for _, type_ in ipairs(types) do
      if type(value) == type_ then
         return true
      end
   end

   error(("bad property '%s' (%s expected, got %s)"):format(name, table.concat(types, " or "), type(value)))
end

local function typechecked(name, ...)
   local types = {...}
   return {name, function(_, value) typecheck(name, types, value) end}
end

local multiname = {"name", function(self, value)
   typecheck("name", {"string"}, value)

   for alias in value:gmatch("%S+") do
      self._name = self._name or alias
      table.insert(self._aliases, alias)
   end

   -- Do not set _name as with other properties.
   return true
end}

local function parse_boundaries(str)
   if tonumber(str) then
      return tonumber(str), tonumber(str)
   end

   if str == "*" then
      return 0, math.huge
   end

   if str == "+" then
      return 1, math.huge
   end

   if str == "?" then
      return 0, 1
   end

   if str:match "^%d+%-%d+$" then
      local min, max = str:match "^(%d+)%-(%d+)$"
      return tonumber(min), tonumber(max)
   end

   if str:match "^%d+%+$" then
      local min = str:match "^(%d+)%+$"
      return tonumber(min), math.huge
   end
end

local function boundaries(name)
   return {name, function(self, value)
      typecheck(name, {"number", "string"}, value)

      local min, max = parse_boundaries(value)

      if not min then
         error(("bad property '%s'"):format(name))
      end

      self["_min" .. name], self["_max" .. name] = min, max
   end}
end

local actions = {}

local option_action = {"action", function(_, value)
   typecheck("action", {"function", "string"}, value)

   if type(value) == "string" and not actions[value] then
      error(("unknown action '%s'"):format(value))
   end
end}

local option_init = {"init", function(self)
   self._has_init = true
end}

local option_default = {"default", function(self, value)
   if type(value) ~= "string" then
      self._init = value
      self._has_init = true
      return true
   end
end}

local add_help = {"add_help", function(self, value)
   typecheck("add_help", {"boolean", "string", "table"}, value)

   if self._has_help then
      table.remove(self._options)
      self._has_help = false
   end

   if value then
      local help = self:flag()
         :description "Show this help message and exit."
         :action(function()
            print(self:get_help())
            os.exit(0)
         end)

      if value ~= true then
         help = help(value)
      end

      if not help._name then
         help "-h" "--help"
      end

      self._has_help = true
   end
end}

local Parser = class({
   _arguments = {},
   _options = {},
   _commands = {},
   _mutexes = {},
   _groups = {},
   _require_command = true,
   _handle_options = true
}, {
   args = 3,
   typechecked("name", "string"),
   typechecked("description", "string"),
   typechecked("epilog", "string"),
   typechecked("usage", "string"),
   typechecked("help", "string"),
   typechecked("require_command", "boolean"),
   typechecked("handle_options", "boolean"),
   typechecked("action", "function"),
   typechecked("command_target", "string"),
   typechecked("help_vertical_space", "number"),
   typechecked("usage_margin", "number"),
   typechecked("usage_max_width", "number"),
   typechecked("help_usage_margin", "number"),
   typechecked("help_description_margin", "number"),
   typechecked("help_max_width", "number"),
   add_help
})

local Command = class({
   _aliases = {}
}, {
   args = 3,
   multiname,
   typechecked("description", "string"),
   typechecked("epilog", "string"),
   typechecked("target", "string"),
   typechecked("usage", "string"),
   typechecked("help", "string"),
   typechecked("require_command", "boolean"),
   typechecked("handle_options", "boolean"),
   typechecked("action", "function"),
   typechecked("command_target", "string"),
   typechecked("help_vertical_space", "number"),
   typechecked("usage_margin", "number"),
   typechecked("usage_max_width", "number"),
   typechecked("help_usage_margin", "number"),
   typechecked("help_description_margin", "number"),
   typechecked("help_max_width", "number"),
   typechecked("hidden", "boolean"),
   add_help
}, Parser)

local Argument = class({
   _minargs = 1,
   _maxargs = 1,
   _mincount = 1,
   _maxcount = 1,
   _defmode = "unused",
   _show_default = true
}, {
   args = 5,
   typechecked("name", "string"),
   typechecked("description", "string"),
   option_default,
   typechecked("convert", "function", "table"),
   boundaries("args"),
   typechecked("target", "string"),
   typechecked("defmode", "string"),
   typechecked("show_default", "boolean"),
   typechecked("argname", "string", "table"),
   typechecked("hidden", "boolean"),
   option_action,
   option_init
})

local Option = class({
   _aliases = {},
   _mincount = 0,
   _overwrite = true
}, {
   args = 6,
   multiname,
   typechecked("description", "string"),
   option_default,
   typechecked("convert", "function", "table"),
   boundaries("args"),
   boundaries("count"),
   typechecked("target", "string"),
   typechecked("defmode", "string"),
   typechecked("show_default", "boolean"),
   typechecked("overwrite", "boolean"),
   typechecked("argname", "string", "table"),
   typechecked("hidden", "boolean"),
   option_action,
   option_init
}, Argument)

function Parser:_inherit_property(name, default)
   local element = self

   while true do
      local value = element["_" .. name]

      if value ~= nil then
         return value
      end

      if not element._parent then
         return default
      end

      element = element._parent
   end
end

function Argument:_get_argument_list()
   local buf = {}
   local i = 1

   while i <= math.min(self._minargs, 3) do
      local argname = self:_get_argname(i)

      if self._default and self._defmode:find "a" then
         argname = "[" .. argname .. "]"
      end

      table.insert(buf, argname)
      i = i+1
   end

   while i <= math.min(self._maxargs, 3) do
      table.insert(buf, "[" .. self:_get_argname(i) .. "]")
      i = i+1

      if self._maxargs == math.huge then
         break
      end
   end

   if i < self._maxargs then
      table.insert(buf, "...")
   end

   return buf
end

function Argument:_get_usage()
   local usage = table.concat(self:_get_argument_list(), " ")

   if self._default and self._defmode:find "u" then
      if self._maxargs > 1 or (self._minargs == 1 and not self._defmode:find "a") then
         usage = "[" .. usage .. "]"
      end
   end

   return usage
end

function actions.store_true(result, target)
   result[target] = true
end

function actions.store_false(result, target)
   result[target] = false
end

function actions.store(result, target, argument)
   result[target] = argument
end

function actions.count(result, target, _, overwrite)
   if not overwrite then
      result[target] = result[target] + 1
   end
end

function actions.append(result, target, argument, overwrite)
   result[target] = result[target] or {}
   table.insert(result[target], argument)

   if overwrite then
      table.remove(result[target], 1)
   end
end

function actions.concat(result, target, arguments, overwrite)
   if overwrite then
      error("'concat' action can't handle too many invocations")
   end

   result[target] = result[target] or {}

   for _, argument in ipairs(arguments) do
      table.insert(result[target], argument)
   end
end

function Argument:_get_action()
   local action, init

   if self._maxcount == 1 then
      if self._maxargs == 0 then
         action, init = "store_true", nil
      else
         action, init = "store", nil
      end
   else
      if self._maxargs == 0 then
         action, init = "count", 0
      else
         action, init = "append", {}
      end
   end

   if self._action then
      action = self._action
   end

   if self._has_init then
      init = self._init
   end

   if type(action) == "string" then
      action = actions[action]
   end

   return action, init
end

-- Returns placeholder for `narg`-th argument.
function Argument:_get_argname(narg)
   local argname = self._argname or self:_get_default_argname()

   if type(argname) == "table" then
      return argname[narg]
   else
      return argname
   end
end

function Argument:_get_default_argname()
   return "<" .. self._name .. ">"
end

function Option:_get_default_argname()
   return "<" .. self:_get_default_target() .. ">"
end

-- Returns labels to be shown in the help message.
function Argument:_get_label_lines()
   return {self._name}
end

function Option:_get_label_lines()
   local argument_list = self:_get_argument_list()

   if #argument_list == 0 then
      -- Don't put aliases for simple flags like `-h` on different lines.
      return {table.concat(self._aliases, ", ")}
   end

   local longest_alias_length = -1

   for _, alias in ipairs(self._aliases) do
      longest_alias_length = math.max(longest_alias_length, #alias)
   end

   local argument_list_repr = table.concat(argument_list, " ")
   local lines = {}

   for i, alias in ipairs(self._aliases) do
      local line = (" "):rep(longest_alias_length - #alias) .. alias .. " " .. argument_list_repr

      if i ~= #self._aliases then
         line = line .. ","
      end

      table.insert(lines, line)
   end

   return lines
end

function Command:_get_label_lines()
   return {table.concat(self._aliases, ", ")}
end

function Argument:_get_description()
   if self._default and self._show_default then
      if self._description then
         return ("%s (default: %s)"):format(self._description, self._default)
      else
         return ("default: %s"):format(self._default)
      end
   else
      return self._description or ""
   end
end

function Command:_get_description()
   return self._description or ""
end

function Option:_get_usage()
   local usage = self:_get_argument_list()
   table.insert(usage, 1, self._name)
   usage = table.concat(usage, " ")

   if self._mincount == 0 or self._default then
      usage = "[" .. usage .. "]"
   end

   return usage
end

function Argument:_get_default_target()
   return self._name
end

function Option:_get_default_target()
   local res

   for _, alias in ipairs(self._aliases) do
      if alias:sub(1, 1) == alias:sub(2, 2) then
         res = alias:sub(3)
         break
      end
   end

   res = res or self._name:sub(2)
   return (res:gsub("-", "_"))
end

function Option:_is_vararg()
   return self._maxargs ~= self._minargs
end

function Parser:_get_fullname()
   local parent = self._parent
   local buf = {self._name}

   while parent do
      table.insert(buf, 1, parent._name)
      parent = parent._parent
   end

   return table.concat(buf, " ")
end

function Parser:_update_charset(charset)
   charset = charset or {}

   for _, command in ipairs(self._commands) do
      command:_update_charset(charset)
   end

   for _, option in ipairs(self._options) do
      for _, alias in ipairs(option._aliases) do
         charset[alias:sub(1, 1)] = true
      end
   end

   return charset
end

function Parser:argument(...)
   local argument = Argument(...)
   table.insert(self._arguments, argument)
   return argument
end

function Parser:option(...)
   local option = Option(...)

   if self._has_help then
      table.insert(self._options, #self._options, option)
   else
      table.insert(self._options, option)
   end

   return option
end

function Parser:flag(...)
   return self:option():args(0)(...)
end

function Parser:command(...)
   local command = Command():add_help(true)(...)
   command._parent = self
   table.insert(self._commands, command)
   return command
end

function Parser:mutex(...)
   local elements = {...}

   for i, element in ipairs(elements) do
      local mt = getmetatable(element)
      assert(mt == Option or mt == Argument, ("bad argument #%d to 'mutex' (Option or Argument expected)"):format(i))
   end

   table.insert(self._mutexes, elements)
   return self
end

function Parser:group(name, ...)
   assert(type(name) == "string", ("bad argument #1 to 'group' (string expected, got %s)"):format(type(name)))

   local group = {name = name, ...}

   for i, element in ipairs(group) do
      local mt = getmetatable(element)
      assert(mt == Option or mt == Argument or mt == Command,
         ("bad argument #%d to 'group' (Option or Argument or Command expected)"):format(i + 1))
   end

   table.insert(self._groups, group)
   return self
end

local usage_welcome = "Usage: "

function Parser:get_usage()
   if self._usage then
      return self._usage
   end

   local usage_margin = self:_inherit_property("usage_margin", #usage_welcome)
   local max_usage_width = self:_inherit_property("usage_max_width", 70)
   local lines = {usage_welcome .. self:_get_fullname()}

   local function add(s)
      if #lines[#lines]+1+#s <= max_usage_width then
         lines[#lines] = lines[#lines] .. " " .. s
      else
         lines[#lines+1] = (" "):rep(usage_margin) .. s
      end
   end

   -- Normally options are before positional arguments in usage messages.
   -- However, vararg options should be after, because they can't be reliable used
   -- before a positional argument.
   -- Mutexes come into play, too, and are shown as soon as possible.
   -- Overall, output usages in the following order:
   -- 1. Mutexes that don't have positional arguments or vararg options.
   -- 2. Options that are not in any mutexes and are not vararg.
   -- 3. Positional arguments - on their own or as a part of a mutex.
   -- 4. Remaining mutexes.
   -- 5. Remaining options.

   local elements_in_mutexes = {}
   local added_elements = {}
   local added_mutexes = {}
   local argument_to_mutexes = {}

   local function add_mutex(mutex, main_argument)
      if added_mutexes[mutex] then
         return
      end

      added_mutexes[mutex] = true
      local buf = {}

      for _, element in ipairs(mutex) do
         if not element._hidden and not added_elements[element] then
            if getmetatable(element) == Option or element == main_argument then
               table.insert(buf, element:_get_usage())
               added_elements[element] = true
            end
         end
      end

      if #buf == 1 then
         add(buf[1])
      elseif #buf > 1 then
         add("(" .. table.concat(buf, " | ") .. ")")
      end
   end

   local function add_element(element)
      if not element._hidden and not added_elements[element] then
         add(element:_get_usage())
         added_elements[element] = true
      end
   end

   for _, mutex in ipairs(self._mutexes) do
      local is_vararg = false
      local has_argument = false

      for _, element in ipairs(mutex) do
         if getmetatable(element) == Option then
            if element:_is_vararg() then
               is_vararg = true
            end
         else
            has_argument = true
            argument_to_mutexes[element] = argument_to_mutexes[element] or {}
            table.insert(argument_to_mutexes[element], mutex)
         end

         elements_in_mutexes[element] = true
      end

      if not is_vararg and not has_argument then
         add_mutex(mutex)
      end
   end

   for _, option in ipairs(self._options) do
      if not elements_in_mutexes[option] and not option:_is_vararg() then
         add_element(option)
      end
   end

   -- Add usages for positional arguments, together with one mutex containing them, if they are in a mutex.
   for _, argument in ipairs(self._arguments) do
      -- Pick a mutex as a part of which to show this argument, take the first one that's still available.
      local mutex

      if elements_in_mutexes[argument] then
         for _, argument_mutex in ipairs(argument_to_mutexes[argument]) do
            if not added_mutexes[argument_mutex] then
               mutex = argument_mutex
            end
         end
      end

      if mutex then
         add_mutex(mutex, argument)
      else
         add_element(argument)
      end
   end

   for _, mutex in ipairs(self._mutexes) do
      add_mutex(mutex)
   end

   for _, option in ipairs(self._options) do
      add_element(option)
   end

   if #self._commands > 0 then
      if self._require_command then
         add("<command>")
      else
         add("[<command>]")
      end

      add("...")
   end

   return table.concat(lines, "\n")
end

local function split_lines(s)
   if s == "" then
      return {}
   end

   local lines = {}

   if s:sub(-1) ~= "\n" then
      s = s .. "\n"
   end

   for line in s:gmatch("([^\n]*)\n") do
      table.insert(lines, line)
   end

   return lines
end

local function autowrap_line(line, max_length)
   -- Algorithm for splitting lines is simple and greedy.
   local result_lines = {}

   -- Preserve original indentation of the line, put this at the beginning of each result line.
   -- If the first word looks like a list marker ('*', '+', or '-'), add spaces so that starts
   -- of the second and the following lines vertically align with the start of the second word.
   local indentation = line:match("^ *")

   if line:find("^ *[%*%+%-]") then
      indentation = indentation .. " " .. line:match("^ *[%*%+%-]( *)")
   end

   -- Parts of the last line being assembled.
   local line_parts = {}

   -- Length of the current line.
   local line_length = 0

   -- Index of the next character to consider.
   local index = 1

   while true do
      local word_start, word_finish, word = line:find("([^ ]+)", index)

      if not word_start then
         -- Ignore trailing spaces, if any.
         break
      end

      local preceding_spaces = line:sub(index, word_start - 1)
      index = word_finish + 1

      if (#line_parts == 0) or (line_length + #preceding_spaces + #word <= max_length) then
         -- Either this is the very first word or it fits as an addition to the current line, add it.
         table.insert(line_parts, preceding_spaces) -- For the very first word this adds the indentation.
         table.insert(line_parts, word)
         line_length = line_length + #preceding_spaces + #word
      else
         -- Does not fit, finish current line and put the word into a new one.
         table.insert(result_lines, table.concat(line_parts))
         line_parts = {indentation, word}
         line_length = #indentation + #word
      end
   end

   if #line_parts > 0 then
      table.insert(result_lines, table.concat(line_parts))
   end

   if #result_lines == 0 then
      -- Preserve empty lines.
      result_lines[1] = ""
   end

   return result_lines
end

-- Automatically wraps lines within given array,
-- attempting to limit line length to `max_length`.
-- Existing line splits are preserved.
local function autowrap(lines, max_length)
   local result_lines = {}

   for _, line in ipairs(lines) do
      local autowrapped_lines = autowrap_line(line, max_length)

      for _, autowrapped_line in ipairs(autowrapped_lines) do
         table.insert(result_lines, autowrapped_line)
      end
   end

   return result_lines
end

function Parser:_get_element_help(element)
   local label_lines = element:_get_label_lines()
   local description_lines = split_lines(element:_get_description())

   local result_lines = {}

   -- All label lines should have the same length (except the last one, it has no comma).
   -- If too long, start description after all the label lines.
   -- Otherwise, combine label and description lines.

   local usage_margin_len = self:_inherit_property("help_usage_margin", 3)
   local usage_margin = (" "):rep(usage_margin_len)
   local description_margin_len = self:_inherit_property("help_description_margin", 25)
   local description_margin = (" "):rep(description_margin_len)

   local help_max_width = self:_inherit_property("help_max_width")

   if help_max_width then
      local description_max_width = math.max(help_max_width - description_margin_len, 10)
      description_lines = autowrap(description_lines, description_max_width)
   end

   if #label_lines[1] >= (description_margin_len - usage_margin_len) then
      for _, label_line in ipairs(label_lines) do
         table.insert(result_lines, usage_margin .. label_line)
      end

      for _, description_line in ipairs(description_lines) do
         table.insert(result_lines, description_margin .. description_line)
      end
   else
      for i = 1, math.max(#label_lines, #description_lines) do
         local label_line = label_lines[i]
         local description_line = description_lines[i]

         local line = ""

         if label_line then
            line = usage_margin .. label_line
         end

         if description_line and description_line ~= "" then
            line = line .. (" "):rep(description_margin_len - #line) .. description_line
         end

         table.insert(result_lines, line)
      end
   end

   return table.concat(result_lines, "\n")
end

local function get_group_types(group)
   local types = {}

   for _, element in ipairs(group) do
      types[getmetatable(element)] = true
   end

   return types
end

function Parser:_add_group_help(blocks, added_elements, label, elements)
   local buf = {label}

   for _, element in ipairs(elements) do
      if not element._hidden and not added_elements[element] then
         added_elements[element] = true
         table.insert(buf, self:_get_element_help(element))
      end
   end

   if #buf > 1 then
      table.insert(blocks, table.concat(buf, ("\n"):rep(self:_inherit_property("help_vertical_space", 0) + 1)))
   end
end

function Parser:get_help()
   if self._help then
      return self._help
   end

   local blocks = {self:get_usage()}

   local help_max_width = self:_inherit_property("help_max_width")

   if self._description then
      local description = self._description

      if help_max_width then
         description = table.concat(autowrap(split_lines(description), help_max_width), "\n")
      end

      table.insert(blocks, description)
   end

   -- 1. Put groups containing arguments first, then other arguments.
   -- 2. Put remaining groups containing options, then other options.
   -- 3. Put remaining groups containing commands, then other commands.
   -- Assume that an element can't be in several groups.
   local groups_by_type = {
      [Argument] = {},
      [Option] = {},
      [Command] = {}
   }

   for _, group in ipairs(self._groups) do
      local group_types = get_group_types(group)

      for _, mt in ipairs({Argument, Option, Command}) do
         if group_types[mt] then
            table.insert(groups_by_type[mt], group)
            break
         end
      end
   end

   local default_groups = {
      {name = "Arguments", type = Argument, elements = self._arguments},
      {name = "Options", type = Option, elements = self._options},
      {name = "Commands", type = Command, elements = self._commands}
   }

   local added_elements = {}

   for _, default_group in ipairs(default_groups) do
      local type_groups = groups_by_type[default_group.type]

      for _, group in ipairs(type_groups) do
         self:_add_group_help(blocks, added_elements, group.name .. ":", group)
      end

      local default_label = default_group.name .. ":"

      if #type_groups > 0 then
         default_label = "Other " .. default_label:gsub("^.", string.lower)
      end

      self:_add_group_help(blocks, added_elements, default_label, default_group.elements)
   end

   if self._epilog then
      local epilog = self._epilog

      if help_max_width then
         epilog = table.concat(autowrap(split_lines(epilog), help_max_width), "\n")
      end

      table.insert(blocks, epilog)
   end

   return table.concat(blocks, "\n\n")
end

local function get_tip(context, wrong_name)
   local context_pool = {}
   local possible_name
   local possible_names = {}

   for name in pairs(context) do
      if type(name) == "string" then
         for i = 1, #name do
            possible_name = name:sub(1, i - 1) .. name:sub(i + 1)

            if not context_pool[possible_name] then
               context_pool[possible_name] = {}
            end

            table.insert(context_pool[possible_name], name)
         end
      end
   end

   for i = 1, #wrong_name + 1 do
      possible_name = wrong_name:sub(1, i - 1) .. wrong_name:sub(i + 1)

      if context[possible_name] then
         possible_names[possible_name] = true
      elseif context_pool[possible_name] then
         for _, name in ipairs(context_pool[possible_name]) do
            possible_names[name] = true
         end
      end
   end

   local first = next(possible_names)

   if first then
      if next(possible_names, first) then
         local possible_names_arr = {}

         for name in pairs(possible_names) do
            table.insert(possible_names_arr, "'" .. name .. "'")
         end

         table.sort(possible_names_arr)
         return "\nDid you mean one of these: " .. table.concat(possible_names_arr, " ") .. "?"
      else
         return "\nDid you mean '" .. first .. "'?"
      end
   else
      return ""
   end
end

local ElementState = class({
   invocations = 0
})

function ElementState:__call(state, element)
   self.state = state
   self.result = state.result
   self.element = element
   self.target = element._target or element:_get_default_target()
   self.action, self.result[self.target] = element:_get_action()
   return self
end

function ElementState:error(fmt, ...)
   self.state:error(fmt, ...)
end

function ElementState:convert(argument, index)
   local converter = self.element._convert

   if converter then
      local ok, err

      if type(converter) == "function" then
         ok, err = converter(argument)
      elseif type(converter[index]) == "function" then
         ok, err = converter[index](argument)
      else
         ok = converter[argument]
      end

      if ok == nil then
         self:error(err and "%s" or "malformed argument '%s'", err or argument)
      end

      argument = ok
   end

   return argument
end

function ElementState:default(mode)
   return self.element._defmode:find(mode) and self.element._default
end

local function bound(noun, min, max, is_max)
   local res = ""

   if min ~= max then
      res = "at " .. (is_max and "most" or "least") .. " "
   end

   local number = is_max and max or min
   return res .. tostring(number) .. " " .. noun ..  (number == 1 and "" or "s")
end

function ElementState:set_name(alias)
   self.name = ("%s '%s'"):format(alias and "option" or "argument", alias or self.element._name)
end

function ElementState:invoke()
   self.open = true
   self.overwrite = false

   if self.invocations >= self.element._maxcount then
      if self.element._overwrite then
         self.overwrite = true
      else
         local num_times_repr = bound("time", self.element._mincount, self.element._maxcount, true)
         self:error("%s must be used %s", self.name, num_times_repr)
      end
   else
      self.invocations = self.invocations + 1
   end

   self.args = {}

   if self.element._maxargs <= 0 then
      self:close()
   end

   return self.open
end

function ElementState:pass(argument)
   argument = self:convert(argument, #self.args + 1)
   table.insert(self.args, argument)

   if #self.args >= self.element._maxargs then
      self:close()
   end

   return self.open
end

function ElementState:complete_invocation()
   while #self.args < self.element._minargs do
      self:pass(self.element._default)
   end
end

function ElementState:close()
   if self.open then
      self.open = false

      if #self.args < self.element._minargs then
         if self:default("a") then
            self:complete_invocation()
         else
            if #self.args == 0 then
               if getmetatable(self.element) == Argument then
                  self:error("missing %s", self.name)
               elseif self.element._maxargs == 1 then
                  self:error("%s requires an argument", self.name)
               end
            end

            self:error("%s requires %s", self.name, bound("argument", self.element._minargs, self.element._maxargs))
         end
      end

      local args

      if self.element._maxargs == 0 then
         args = self.args[1]
      elseif self.element._maxargs == 1 then
         if self.element._minargs == 0 and self.element._mincount ~= self.element._maxcount then
            args = self.args
         else
            args = self.args[1]
         end
      else
         args = self.args
      end

      self.action(self.result, self.target, args, self.overwrite)
   end
end

local ParseState = class({
   result = {},
   options = {},
   arguments = {},
   argument_i = 1,
   element_to_mutexes = {},
   mutex_to_element_state = {},
   command_actions = {}
})

function ParseState:__call(parser, error_handler)
   self.parser = parser
   self.error_handler = error_handler
   self.charset = parser:_update_charset()
   self:switch(parser)
   return self
end

function ParseState:error(fmt, ...)
   self.error_handler(self.parser, fmt:format(...))
end

function ParseState:switch(parser)
   self.parser = parser

   if parser._action then
      table.insert(self.command_actions, {action = parser._action, name = parser._name})
   end

   for _, option in ipairs(parser._options) do
      option = ElementState(self, option)
      table.insert(self.options, option)

      for _, alias in ipairs(option.element._aliases) do
         self.options[alias] = option
      end
   end

   for _, mutex in ipairs(parser._mutexes) do
      for _, element in ipairs(mutex) do
         if not self.element_to_mutexes[element] then
            self.element_to_mutexes[element] = {}
         end

         table.insert(self.element_to_mutexes[element], mutex)
      end
   end

   for _, argument in ipairs(parser._arguments) do
      argument = ElementState(self, argument)
      table.insert(self.arguments, argument)
      argument:set_name()
      argument:invoke()
   end

   self.handle_options = parser._handle_options
   self.argument = self.arguments[self.argument_i]
   self.commands = parser._commands

   for _, command in ipairs(self.commands) do
      for _, alias in ipairs(command._aliases) do
         self.commands[alias] = command
      end
   end
end

function ParseState:get_option(name)
   local option = self.options[name]

   if not option then
      self:error("unknown option '%s'%s", name, get_tip(self.options, name))
   else
      return option
   end
end

function ParseState:get_command(name)
   local command = self.commands[name]

   if not command then
      if #self.commands > 0 then
         self:error("unknown command '%s'%s", name, get_tip(self.commands, name))
      else
         self:error("too many arguments")
      end
   else
      return command
   end
end

function ParseState:check_mutexes(element_state)
   if self.element_to_mutexes[element_state.element] then
      for _, mutex in ipairs(self.element_to_mutexes[element_state.element]) do
         local used_element_state = self.mutex_to_element_state[mutex]

         if used_element_state and used_element_state ~= element_state then
            self:error("%s can not be used together with %s", element_state.name, used_element_state.name)
         else
            self.mutex_to_element_state[mutex] = element_state
         end
      end
   end
end

function ParseState:invoke(option, name)
   self:close()
   option:set_name(name)
   self:check_mutexes(option, name)

   if option:invoke() then
      self.option = option
   end
end

function ParseState:pass(arg)
   if self.option then
      if not self.option:pass(arg) then
         self.option = nil
      end
   elseif self.argument then
      self:check_mutexes(self.argument)

      if not self.argument:pass(arg) then
         self.argument_i = self.argument_i + 1
         self.argument = self.arguments[self.argument_i]
      end
   else
      local command = self:get_command(arg)
      self.result[command._target or command._name] = true

      if self.parser._command_target then
         self.result[self.parser._command_target] = command._name
      end

      self:switch(command)
   end
end

function ParseState:close()
   if self.option then
      self.option:close()
      self.option = nil
   end
end

function ParseState:finalize()
   self:close()

   for i = self.argument_i, #self.arguments do
      local argument = self.arguments[i]
      if #argument.args == 0 and argument:default("u") then
         argument:complete_invocation()
      else
         argument:close()
      end
   end

   if self.parser._require_command and #self.commands > 0 then
      self:error("a command is required")
   end

   for _, option in ipairs(self.options) do
      option.name = option.name or ("option '%s'"):format(option.element._name)

      if option.invocations == 0 then
         if option:default("u") then
            option:invoke()
            option:complete_invocation()
            option:close()
         end
      end

      local mincount = option.element._mincount

      if option.invocations < mincount then
         if option:default("a") then
            while option.invocations < mincount do
               option:invoke()
               option:close()
            end
         elseif option.invocations == 0 then
            self:error("missing %s", option.name)
         else
            self:error("%s must be used %s", option.name, bound("time", mincount, option.element._maxcount))
         end
      end
   end

   for i = #self.command_actions, 1, -1 do
      self.command_actions[i].action(self.result, self.command_actions[i].name)
   end
end

function ParseState:parse(args)
   for _, arg in ipairs(args) do
      local plain = true

      if self.handle_options then
         local first = arg:sub(1, 1)

         if self.charset[first] then
            if #arg > 1 then
               plain = false

               if arg:sub(2, 2) == first then
                  if #arg == 2 then
                     if self.options[arg] then
                        local option = self:get_option(arg)
                        self:invoke(option, arg)
                     else
                        self:close()
                     end

                     self.handle_options = false
                  else
                     local equals = arg:find "="
                     if equals then
                        local name = arg:sub(1, equals - 1)
                        local option = self:get_option(name)

                        if option.element._maxargs <= 0 then
                           self:error("option '%s' does not take arguments", name)
                        end

                        self:invoke(option, name)
                        self:pass(arg:sub(equals + 1))
                     else
                        local option = self:get_option(arg)
                        self:invoke(option, arg)
                     end
                  end
               else
                  for i = 2, #arg do
                     local name = first .. arg:sub(i, i)
                     local option = self:get_option(name)
                     self:invoke(option, name)

                     if i ~= #arg and option.element._maxargs > 0 then
                        self:pass(arg:sub(i + 1))
                        break
                     end
                  end
               end
            end
         end
      end

      if plain then
         self:pass(arg)
      end
   end

   self:finalize()
   return self.result
end

function Parser:error(msg)
   io.stderr:write(("%s\n\nError: %s\n"):format(self:get_usage(), msg))
   os.exit(1)
end

-- Compatibility with strict.lua and other checkers:
local default_cmdline = rawget(_G, "arg") or {}

function Parser:_parse(args, error_handler)
   return ParseState(self, error_handler):parse(args or default_cmdline)
end

function Parser:parse(args)
   return self:_parse(args, self.error)
end

local function xpcall_error_handler(err)
   return tostring(err) .. "\noriginal " .. debug.traceback("", 2):sub(2)
end

function Parser:pparse(args)
   local parse_error

   local ok, result = xpcall(function()
      return self:_parse(args, function(_, err)
         parse_error = err
         error(err, 0)
      end)
   end, xpcall_error_handler)

   if ok then
      return true, result
   elseif not parse_error then
      error(result, 0)
   else
      return false, parse_error
   end
end

local argparse = {}

argparse.version = "0.6.0"

setmetatable(argparse, {__call = function(_, ...)
   return Parser(default_cmdline[0]):add_help(true)(...)
end})

return argparse
end
end

do
local _ENV = _ENV
package.preload[ "gears" ] = function( ... ) local arg = _G.arg;


local M = {}

local F     = require "F"
local safer = require "safer"


-- Distable globals from hereon out
if not _GEARS_UNSAFE then safer.globals() end


--[[ function to retun the path of the current file --]]
function M.thisdir(level)
    level = level or 2
    local pth = debug.getinfo(level).source:match("@?(.*/)")
    -- if this program is called within the current directory then the path
    -- won't contain '/', returning (nil)
    if pth == nil then
        return io.popen("pwd"):read("*a"):gsub("\n", "")
    end
    -- remember to remove the traling slash
    return M.realdir(pth)
end


---@diagnostic disable-next-line: unused-local
function M.realdir(pth)
    return io.popen(F"cd '{pth}' && pwd"):read("*a"):gsub("\n", "")
end


function M.read_dir(dir)
    local directory = {}
    for s in io.popen(F"/bin/ls -1 '{dir}'"):lines() do
        directory[#directory+1] = {
            name = s,
            is_dir = M.isdir(dir .. "/" .. s)
        }
    end
    return directory
end


function M.parse_version(version_str)
    local t = {}
    for i in string.gmatch(version_str, '(%d+)') do
        t[#t+1] = i
    end
    return t
end


function M.file_exists(name)
   local f = io.open(name, "r")
   if f == nil then
       return false
   end
   io.close(f)
   return true
end


-- get all lines from a file, returns an empty list/table if the file does not
-- exist
function M.read_lines(file)
    if not M.file_exists(file) then return {} end

    local lines = {}
    for line in io.lines(file) do
        lines[#lines + 1] = line
    end

    return lines
end


---@diagnostic disable-next-line: unused-local
function M.isdir(name)
    return io.popen(
        F"test -d '{name}' && echo true || echo false"
    ):read("*a"):gsub("\n", "") == "true"
end


function M.dir_exists(name)
    return M.isdir(name)
end


-- 
-- Extract parent directiory, file name, and extension (order of returns) from a
-- path. Example usage:
--
-- > require("gears").basename([[/mnt/tmp/myfile.txt]])
-- "/mnt/tmp/" "myfile.txt"    "txt"
--
function M.basename(path)
    -- ChatGPT Explanation of the regex (seems legit...)
    --
    -- ### 1\. **`(.-)`**
    --  * `.` matches any character except a newline.
    --  * `-` makes it _lazy_ (matches the shortest possible sequence).
    --  * This part captures everything up to the last part of the path (i.e.,
    --    the directory portion).
    --
    -- ### 2\. **`([^\\/]-%.?([^%.\\/]*))`**
    -- * `[^\\/]` matches any character except `\` or `/` (to avoid matching
    --   directory separators).
    -- * `-` makes it _lazy_ again. * `%` is used to escape `.` because `.`
    --   normally matches any character.
    -- * `.?` means that the `.` (dot) is optional (i.e., to account for
    --   filenames that might not have an extension).
    -- * `([^%.\\/]*)` captures the file extension (anything after the last `.`
    --   in the filename).
    --
    -- ### 3\. **`$`**
    --  * Ensures the regex matches only at the end of the string.
    --
    return string.match(path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
end


---@diagnostic disable-next-line: unused-local
function M.mkdir(path)
    return io.popen(
        F"mkdir -p '{path}' && echo true || echo false"
    ):read("*a"):gsub("\n", "") == "true"
end


---@diagnostic disable-next-line: unused-local
function M.cp(src, dest)
    return io.popen(
        F"cp -r '{src}' '{dest}' && echo true || echo false"
    ):read("*a"):gsub("\n", "") == "true"
end

--------------------------------------------------------------------------------
-- product and zip iterators
--------------------------------------------------------------------------------

function M.iproduct(dims)
    -- initialize internal state
    local state = {}
    for i=1,#dims do state[i] = 1 end
    -- initialize state to be one less the first iteration => simpler
    -- implementation of the `next` function
    state[1] = 0

    local function _next_idx_rollover(pos, idx, max_idx)
        -- check if reached end of radixes => return `nil`
        if pos > #idx then return nil end
        -- advance the current radix
        idx[pos] = idx[pos] + 1
        -- if radix overflows, roll over to the next radix
        if idx[pos] > max_idx[pos] then
            idx[pos] = 1
            idx = _next_idx_rollover(pos+1, idx, max_idx)
        end
        return idx
    end

    local function next()
        state = _next_idx_rollover(1, state, dims)
        return state
    end

    return next
end


function M.product(lists)
    local dims = {}
    for i, tbl in ipairs(lists) do dims[i] = #tbl end

    local multi_index = M.iproduct(dims)

    local function next()
        local idx = multi_index()
        if nil == idx then return nil end

        local result = {}
        for i, j in ipairs(idx) do
            result[i] = lists[i][j]
        end

        return result
    end

    return next
end


function M.zip(lists)
    local _,  first = next(lists)
    local len       = #first

    for _, l in ipairs(lists) do
        assert(len == #l, "All inputs need to have the same length")
    end

    -- initialize internal state
    local state = 0

    local function next()
        state = state + 1
        if state > len then return nil end

        local result = {}
        for i, elt in ipairs(lists) do
            result[i] = elt[state]
        end

        return result
    end

    return next
end


return M
end
end

do
local _ENV = _ENV
package.preload[ "inspect" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local inspect = {Options = {}, }

















inspect._VERSION = 'inspect.lua 3.1.0'
inspect._URL = 'http://github.com/kikito/inspect.lua'
inspect._DESCRIPTION = 'human-readable representations of tables'
inspect._LICENSE = [[
  MIT LICENSE
  Copyright (c) 2022 Enrique García Cota
  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:
  The above copyright notice and this permission notice shall be included
  in all copies or substantial portions of the Software.
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
inspect.KEY = setmetatable({}, { __tostring = function() return 'inspect.KEY' end })
inspect.METATABLE = setmetatable({}, { __tostring = function() return 'inspect.METATABLE' end })

local tostring = tostring
local rep = string.rep
local match = string.match
local char = string.char
local gsub = string.gsub
local fmt = string.format

local function rawpairs(t)
   return next, t, nil
end



local function smartQuote(str)
   if match(str, '"') and not match(str, "'") then
      return "'" .. str .. "'"
   end
   return '"' .. gsub(str, '"', '\\"') .. '"'
end


local shortControlCharEscapes = {
   ["\a"] = "\\a", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
   ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\127"] = "\\127",
}
local longControlCharEscapes = { ["\127"] = "\127" }
for i = 0, 31 do
   local ch = char(i)
   if not shortControlCharEscapes[ch] then
      shortControlCharEscapes[ch] = "\\" .. i
      longControlCharEscapes[ch] = fmt("\\%03d", i)
   end
end

local function escape(str)
   return (gsub(gsub(gsub(str, "\\", "\\\\"),
   "(%c)%f[0-9]", longControlCharEscapes),
   "%c", shortControlCharEscapes))
end

local function isIdentifier(str)
   return type(str) == "string" and not not str:match("^[_%a][_%a%d]*$")
end

local flr = math.floor
local function isSequenceKey(k, sequenceLength)
   return type(k) == "number" and
   flr(k) == k and
   1 <= (k) and
   k <= sequenceLength
end

local defaultTypeOrders = {
   ['number'] = 1, ['boolean'] = 2, ['string'] = 3, ['table'] = 4,
   ['function'] = 5, ['userdata'] = 6, ['thread'] = 7,
}

local function sortKeys(a, b)
   local ta, tb = type(a), type(b)


   if ta == tb and (ta == 'string' or ta == 'number') then
      return (a) < (b)
   end

   local dta = defaultTypeOrders[ta] or 100
   local dtb = defaultTypeOrders[tb] or 100


   return dta == dtb and ta < tb or dta < dtb
end

local function getKeys(t)

   local seqLen = 1
   while rawget(t, seqLen) ~= nil do
      seqLen = seqLen + 1
   end
   seqLen = seqLen - 1

   local keys, keysLen = {}, 0
   for k in rawpairs(t) do
      if not isSequenceKey(k, seqLen) then
         keysLen = keysLen + 1
         keys[keysLen] = k
      end
   end
   table.sort(keys, sortKeys)
   return keys, keysLen, seqLen
end

local function countCycles(x, cycles)
   if type(x) == "table" then
      if cycles[x] then
         cycles[x] = cycles[x] + 1
      else
         cycles[x] = 1
         for k, v in rawpairs(x) do
            countCycles(k, cycles)
            countCycles(v, cycles)
         end
         countCycles(getmetatable(x), cycles)
      end
   end
end

local function makePath(path, a, b)
   local newPath = {}
   local len = #path
   for i = 1, len do newPath[i] = path[i] end

   newPath[len + 1] = a
   newPath[len + 2] = b

   return newPath
end


local function processRecursive(process,
   item,
   path,
   visited)
   if item == nil then return nil end
   if visited[item] then return visited[item] end

   local processed = process(item, path)
   if type(processed) == "table" then
      local processedCopy = {}
      visited[item] = processedCopy
      local processedKey

      for k, v in rawpairs(processed) do
         processedKey = processRecursive(process, k, makePath(path, k, inspect.KEY), visited)
         if processedKey ~= nil then
            processedCopy[processedKey] = processRecursive(process, v, makePath(path, processedKey), visited)
         end
      end

      local mt = processRecursive(process, getmetatable(processed), makePath(path, inspect.METATABLE), visited)
      if type(mt) ~= 'table' then mt = nil end
      setmetatable(processedCopy, mt)
      processed = processedCopy
   end
   return processed
end

local function puts(buf, str)
   buf.n = buf.n + 1
   buf[buf.n] = str
end



local Inspector = {}










local Inspector_mt = { __index = Inspector }

local function tabify(inspector)
   puts(inspector.buf, inspector.newline .. rep(inspector.indent, inspector.level))
end

function Inspector:getId(v)
   local id = self.ids[v]
   local ids = self.ids
   if not id then
      local tv = type(v)
      id = (ids[tv] or 0) + 1
      ids[v], ids[tv] = id, id
   end
   return tostring(id)
end

function Inspector:putValue(v)
   local buf = self.buf
   local tv = type(v)
   if tv == 'string' then
      puts(buf, smartQuote(escape(v)))
   elseif tv == 'number' or tv == 'boolean' or tv == 'nil' or
      tv == 'cdata' or tv == 'ctype' then
      puts(buf, tostring(v))
   elseif tv == 'table' and not self.ids[v] then
      local t = v

      if t == inspect.KEY or t == inspect.METATABLE then
         puts(buf, tostring(t))
      elseif self.level >= self.depth then
         puts(buf, '{...}')
      else
         if self.cycles[t] > 1 then puts(buf, fmt('<%d>', self:getId(t))) end

         local keys, keysLen, seqLen = getKeys(t)

         puts(buf, '{')
         self.level = self.level + 1

         for i = 1, seqLen + keysLen do
            if i > 1 then puts(buf, ',') end
            if i <= seqLen then
               puts(buf, ' ')
               self:putValue(t[i])
            else
               local k = keys[i - seqLen]
               tabify(self)
               if isIdentifier(k) then
                  puts(buf, k)
               else
                  puts(buf, "[")
                  self:putValue(k)
                  puts(buf, "]")
               end
               puts(buf, ' = ')
               self:putValue(t[k])
            end
         end

         local mt = getmetatable(t)
         if type(mt) == 'table' then
            if seqLen + keysLen > 0 then puts(buf, ',') end
            tabify(self)
            puts(buf, '<metatable> = ')
            self:putValue(mt)
         end

         self.level = self.level - 1

         if keysLen > 0 or type(mt) == 'table' then
            tabify(self)
         elseif seqLen > 0 then
            puts(buf, ' ')
         end

         puts(buf, '}')
      end

   else
      puts(buf, fmt('<%s %d>', tv, self:getId(v)))
   end
end




function inspect.inspect(root, options)
   options = options or {}

   local depth = options.depth or (math.huge)
   local newline = options.newline or '\n'
   local indent = options.indent or '  '
   local process = options.process

   if process then
      root = processRecursive(process, root, {}, {})
   end

   local cycles = {}
   countCycles(root, cycles)

   local inspector = setmetatable({
      buf = { n = 0 },
      ids = {},
      cycles = cycles,
      depth = depth,
      level = 0,
      newline = newline,
      indent = indent,
   }, Inspector_mt)

   inspector:putValue(root)

   return table.concat(inspector.buf)
end

setmetatable(inspect, {
   __call = function(_, root, options)
      return inspect.inspect(root, options)
   end,
})

return inspect
end
end

do
local _ENV = _ENV
package.preload[ "json" ] = function( ... ) local arg = _G.arg;
--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "\b" ] = "b",
  [ "\f" ] = "f",
  [ "\n" ] = "n",
  [ "\r" ] = "r",
  [ "\t" ] = "t",
}

local escape_char_map_inv = { [ "/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid table: sparse array")
    end
    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"

  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json.encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(1, 4),  16 )
  local n2 = tonumber( s:sub(7, 10), 16 )
   -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local res = ""
  local j = i + 1
  local k = j

  while j <= #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")

    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                 or str:match("^%x%x%x%x", j + 1)
                 or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1

    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
    end

    j = j + 1
  end

  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end


return json
end
end

do
local _ENV = _ENV
package.preload[ "log" ] = function( ... ) local arg = _G.arg;
--
-- log.lua
--
-- Copyright (c) 2016 rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--

local log = { _version = "0.1.0" }

log.usecolor = true
log.outfile = nil
log.level = "trace"


local modes = {
  { name = "trace", color = "\27[34m", },
  { name = "debug", color = "\27[36m", },
  { name = "info",  color = "\27[32m", },
  { name = "warn",  color = "\27[33m", },
  { name = "error", color = "\27[31m", },
  { name = "fatal", color = "\27[35m", },
}


local levels = {}
for i, v in ipairs(modes) do
  levels[v.name] = i
end


local round = function(x, increment)
  increment = increment or 1
  x = x / increment
  return (x > 0 and math.floor(x + .5) or math.ceil(x - .5)) * increment
end


local _tostring = tostring

local tostring = function(...)
  local t = {}
  for i = 1, select('#', ...) do
    local x = select(i, ...)
    if type(x) == "number" then
      x = round(x, .01)
    end
    t[#t + 1] = _tostring(x)
  end
  return table.concat(t, " ")
end


for i, x in ipairs(modes) do
  local nameupper = x.name:upper()
  log[x.name] = function(...)
    
    -- Return early if we're below the log level
    if i < levels[log.level] then
      return
    end

    local msg = tostring(...)
    local info = debug.getinfo(2, "Sl")
    local lineinfo = info.short_src .. ":" .. info.currentline

    -- Output to console
    print(string.format("%s[%-6s%s]%s %s: %s",
                        log.usecolor and x.color or "",
                        nameupper,
                        os.date("%H:%M:%S"),
                        log.usecolor and "\27[0m" or "",
                        lineinfo,
                        msg))

    -- Output to log file
    if log.outfile then
      local fp = io.open(log.outfile, "a")
      local str = string.format("[%-6s%s] %s: %s\n",
                                nameupper, os.date(), lineinfo, msg)
      fp:write(str)
      fp:close()
    end

  end
end


return log
end
end

do
local _ENV = _ENV
package.preload[ "lustache" ] = function( ... ) local arg = _G.arg;
-- lustache: Lua mustache template parsing.
-- Copyright 2013 Olivine Labs, LLC <projects@olivinelabs.com>
-- MIT Licensed.

local string_gmatch = string.gmatch

function string.split(str, sep)
  local out = {}
  for m in string_gmatch(str, "[^"..sep.."]+") do out[#out+1] = m end
  return out
end

local lustache = {
  name     = "lustache",
  version  = "1.3.1-0",
  renderer = require("lustache.renderer"):new(),
}

return setmetatable(lustache, {
  __index = function(self, idx)
    if self.renderer[idx] then return self.renderer[idx] end
  end,
  __newindex = function(self, idx, val)
    if idx == "partials" then self.renderer.partials = val end
    if idx == "tags" then self.renderer.tags = val end
  end
})
end
end

do
local _ENV = _ENV
package.preload[ "lustache.context" ] = function( ... ) local arg = _G.arg;
local string_find, string_split, tostring, type =
      string.find, string.split, tostring, type

local context = {}
context.__index = context

function context:clear_cache()
  self.cache = {}
end

function context:push(view)
  return self:new(view, self)
end

function context:lookup(name)
  local value = self.cache[name]

  if not value then
    if name == "." then
      value = self.view
    else
      local context = self

      while context do
        if string_find(name, ".") > 0 then
          local names = string_split(name, ".")
          local i = 0

          value = context.view

          if(type(value)) == "number" then
            value = tostring(value)
          end

          while value and i < #names do
            i = i + 1
            value = value[names[i]]
          end
        else
          value = context.view[name]
        end

        if value then
          break
        end

        context = context.parent
      end
    end

    self.cache[name] = value
  end

  return value
end

function context:new(view, parent)
  local out = {
    view   = view,
    parent = parent,
    cache  = {},
  }
  return setmetatable(out, context)
end

return context
end
end

do
local _ENV = _ENV
package.preload[ "lustache.renderer" ] = function( ... ) local arg = _G.arg;
local Scanner  = require "lustache.scanner"
local Context  = require "lustache.context"

local error, ipairs, pairs, setmetatable, tostring, type = 
      error, ipairs, pairs, setmetatable, tostring, type 
local math_floor, math_max, string_find, string_gsub, string_split, string_sub, table_concat, table_insert, table_remove =
      math.floor, math.max, string.find, string.gsub, string.split, string.sub, table.concat, table.insert, table.remove

local patterns = {
  white = "%s*",
  space = "%s+",
  nonSpace = "%S",
  eq = "%s*=",
  curly = "%s*}",
  tag = "[#\\^/>{&=!?]"
}

local html_escape_characters = {
  ["&"] = "&amp;",
  ["<"] = "&lt;",
  [">"] = "&gt;",
  ['"'] = "&quot;",
  ["'"] = "&#39;",
  ["/"] = "&#x2F;"
}

local block_tags = {
  ["#"] = true,
  ["^"] = true,
  ["?"] = true,
}

local function is_array(array)
  if type(array) ~= "table" then return false end
  local max, n = 0, 0
  for k, _ in pairs(array) do
    if not (type(k) == "number" and k > 0 and math_floor(k) == k) then
      return false 
    end
    max = math_max(max, k)
    n = n + 1
  end
  return n == max
end

-- Low-level function that compiles the given `tokens` into a
-- function that accepts two arguments: a Context and a
-- Renderer.

local function compile_tokens(tokens, originalTemplate)
  local subs = {}

  local function subrender(i, tokens)
    if not subs[i] then
      local fn = compile_tokens(tokens, originalTemplate)
      subs[i] = function(ctx, rnd) return fn(ctx, rnd) end
    end
    return subs[i]
  end

  local function render(ctx, rnd)
    local buf = {}
    local token, section
    for i, token in ipairs(tokens) do
      local t = token.type
      buf[#buf+1] = 
        t == "?" and rnd:_conditional(
          token, ctx, subrender(i, token.tokens)
        ) or
        t == "#" and rnd:_section(
          token, ctx, subrender(i, token.tokens), originalTemplate
        ) or
        t == "^" and rnd:_inverted(
          token.value, ctx, subrender(i, token.tokens)
        ) or
        t == ">" and rnd:_partial(token.value, ctx, originalTemplate) or
        (t == "{" or t == "&") and rnd:_name(token.value, ctx, false) or
        t == "name" and rnd:_name(token.value, ctx, true) or
        t == "text" and token.value or ""
    end
    return table_concat(buf)
  end
  return render
end

local function escape_tags(tags)

  return {
    string_gsub(tags[1], "%%", "%%%%").."%s*",
    "%s*"..string_gsub(tags[2], "%%", "%%%%"),
  }
end

local function nest_tokens(tokens)
  local tree = {}
  local collector = tree 
  local sections = {}
  local token, section

  for i,token in ipairs(tokens) do
    if block_tags[token.type] then
      token.tokens = {}
      sections[#sections+1] = token
      collector[#collector+1] = token
      collector = token.tokens
    elseif token.type == "/" then
      if #sections == 0 then
        error("Unopened section: "..token.value)
      end

      -- Make sure there are no open sections when we're done
      section = table_remove(sections, #sections)

      if not section.value == token.value then
        error("Unclosed section: "..section.value)
      end

      section.closingTagIndex = token.startIndex

      if #sections > 0 then
        collector = sections[#sections].tokens
      else
        collector = tree
      end
    else
      collector[#collector+1] = token
    end
  end

  section = table_remove(sections, #sections)

  if section then
    error("Unclosed section: "..section.value)
  end

  return tree
end

-- Combines the values of consecutive text tokens in the given `tokens` array
-- to a single token.
local function squash_tokens(tokens)
  local out, txt = {}, {}
  local txtStartIndex, txtEndIndex
  for _, v in ipairs(tokens) do
    if v.type == "text" then
      if #txt == 0 then
        txtStartIndex = v.startIndex
      end
      txt[#txt+1] = v.value
      txtEndIndex = v.endIndex
    else
      if #txt > 0 then
        out[#out+1] = { type = "text", value = table_concat(txt), startIndex = txtStartIndex, endIndex = txtEndIndex }
        txt = {}
      end
      out[#out+1] = v
    end
  end
  if #txt > 0 then
    out[#out+1] = { type = "text", value = table_concat(txt), startIndex = txtStartIndex, endIndex = txtEndIndex  }
  end
  return out
end

local function make_context(view)
  if not view then return view end
  return getmetatable(view) == Context and view or Context:new(view)
end

local renderer = { }

function renderer:clear_cache()
  self.cache = {}
  self.partial_cache = {}
end

function renderer:compile(tokens, tags, originalTemplate)
  tags = tags or self.tags
  if type(tokens) == "string" then
    tokens = self:parse(tokens, tags)
  end

  local fn = compile_tokens(tokens, originalTemplate)

  return function(view)
    return fn(make_context(view), self)
  end
end

function renderer:render(template, view, partials)
  if type(self) == "string" then
    error("Call mustache:render, not mustache.render!")
  end

  if partials then
    -- remember partial table
    -- used for runtime lookup & compile later on
    self.partials = partials
  end

  if not template then
    return ""
  end

  local fn = self.cache[template]

  if not fn then
    fn = self:compile(template, self.tags, template)
    self.cache[template] = fn
  end

  return fn(view)
end

function renderer:_conditional(token, context, callback)
  local value = context:lookup(token.value)

  if value then
    return callback(context, self)
  end

  return ""
end

function renderer:_section(token, context, callback, originalTemplate)
  local value = context:lookup(token.value)

  if type(value) == "table" then
    if is_array(value) then
      local buffer = ""

      for i,v in ipairs(value) do
        buffer = buffer .. callback(context:push(v), self)
      end

      return buffer
    end

    return callback(context:push(value), self)
  elseif type(value) == "function" then
    local section_text = string_sub(originalTemplate, token.endIndex+1, token.closingTagIndex - 1)

    local scoped_render = function(template)
      return self:render(template, context)
    end

    return value(section_text, scoped_render) or ""
  else
    if value then
      return callback(context, self)
    end
  end

  return ""
end

function renderer:_inverted(name, context, callback)
  local value = context:lookup(name)

  -- From the spec: inverted sections may render text once based on the
  -- inverse value of the key. That is, they will be rendered if the key
  -- doesn't exist, is false, or is an empty list.

  if value == nil or value == false or (type(value) == "table" and is_array(value) and #value == 0) then
    return callback(context, self)
  end

  return ""
end

function renderer:_partial(name, context, originalTemplate)
  local fn = self.partial_cache[name]

  -- check if partial cache exists
  if (not fn and self.partials) then

    local partial = self.partials[name]
    if (not partial) then
      return ""
    end
    
    -- compile partial and store result in cache
    fn = self:compile(partial, nil, partial)
    self.partial_cache[name] = fn
  end
  return fn and fn(context, self) or ""
end

function renderer:_name(name, context, escape)
  local value = context:lookup(name)

  if type(value) == "function" then
    value = value(context.view)
  end

  local str = value == nil and "" or value
  str = tostring(str)

  if escape then
    return string_gsub(str, '[&<>"\'/]', function(s) return html_escape_characters[s] end)
  end

  return str
end

-- Breaks up the given `template` string into a tree of token objects. If
-- `tags` is given here it must be an array with two string values: the
-- opening and closing tags used in the template (e.g. ["<%", "%>"]). Of
-- course, the default is to use mustaches (i.e. Mustache.tags).
function renderer:parse(template, tags)
  tags = tags or self.tags
  local tag_patterns = escape_tags(tags)
  local scanner = Scanner:new(template)
  local tokens = {} -- token buffer
  local spaces = {} -- indices of whitespace tokens on the current line
  local has_tag = false -- is there a {{tag} on the current line?
  local non_space = false -- is there a non-space char on the current line?

  -- Strips all whitespace tokens array for the current line if there was
  -- a {{#tag}} on it and otherwise only space
  local function strip_space()
    if has_tag and not non_space then
      while #spaces > 0 do
        table_remove(tokens, table_remove(spaces))
      end
    else
      spaces = {}
    end
    has_tag = false
    non_space = false
  end

  local type, value, chr

  while not scanner:eos() do
    local start = scanner.pos

    value = scanner:scan_until(tag_patterns[1])

    if value then
      for i = 1, #value do
        chr = string_sub(value,i,i)

        if string_find(chr, "%s+") then
          spaces[#spaces+1] = #tokens + 1
        else
          non_space = true
        end

        tokens[#tokens+1] = { type = "text", value = chr, startIndex = start, endIndex = start }
        start = start + 1
        if chr == "\n" then
          strip_space()
        end
      end
    end

    if not scanner:scan(tag_patterns[1]) then
      break
    end

    has_tag = true
    type = scanner:scan(patterns.tag) or "name"

    scanner:scan(patterns.white)

    if type == "=" then
      value = scanner:scan_until(patterns.eq)
      scanner:scan(patterns.eq)
      scanner:scan_until(tag_patterns[2])
    elseif type == "{" then
      local close_pattern = "%s*}"..tags[2]
      value = scanner:scan_until(close_pattern)
      scanner:scan(patterns.curly)
      scanner:scan_until(tag_patterns[2])
    else
      value = scanner:scan_until(tag_patterns[2])
    end

    if not scanner:scan(tag_patterns[2]) then
      error("Unclosed tag " .. value .. " of type " .. type .. " at position " .. scanner.pos)
    end

    tokens[#tokens+1] = { type = type, value = value, startIndex = start, endIndex = scanner.pos - 1 }
    if type == "name" or type == "{" or type == "&" then
      non_space = true --> what does this do?
    end

    if type == "=" then
      tags = string_split(value, patterns.space)
      tag_patterns = escape_tags(tags)
    end
  end

  return nest_tokens(squash_tokens(tokens))
end

function renderer:new()
  local out = { 
    cache         = {},
    partial_cache = {},
    tags          = {"{{", "}}"}
  }
  return setmetatable(out, { __index = self })
end

return renderer
end
end

do
local _ENV = _ENV
package.preload[ "lustache.scanner" ] = function( ... ) local arg = _G.arg;
local string_find, string_match, string_sub =
      string.find, string.match, string.sub

local scanner = {}

-- Returns `true` if the tail is empty (end of string).
function scanner:eos()
  return self.tail == ""
end

-- Tries to match the given regular expression at the current position.
-- Returns the matched text if it can match, `null` otherwise.
function scanner:scan(pattern)
  local match = string_match(self.tail, pattern)

  if match and string_find(self.tail, pattern) == 1 then
    self.tail = string_sub(self.tail, #match + 1)
    self.pos = self.pos + #match

    return match
  end

end

-- Skips all text until the given regular expression can be matched. Returns
-- the skipped string, which is the entire tail of this scanner if no match
-- can be made.
function scanner:scan_until(pattern)

  local match
  local pos = string_find(self.tail, pattern)

  if pos == nil then
    match = self.tail
    self.pos = self.pos + #self.tail
    self.tail = ""
  elseif pos == 1 then
    match = nil
  else
    match = string_sub(self.tail, 1, pos - 1)
    self.tail = string_sub(self.tail, pos)
    self.pos = self.pos + #match
  end

  return match
end

function scanner:new(str)
  local out = {
    str  = str,
    tail = str,
    pos  = 1
  }
  return setmetatable(out, { __index = self } )
end

return scanner
end
end

do
local _ENV = _ENV
package.preload[ "safer" ] = function( ... ) local arg = _G.arg;
local safer = {}

function safer.readonly(t)
   local st = {}
   setmetatable(st, {
      __index = t,
      __newindex = function(_, k, _)
         error("Attempting to set field '"..tostring(k).."' in read-only table.")
      end,
   })
   return st
end

function safer.table(t)
   local st = {}
   setmetatable(st, {
      __index = t,
      __newindex = function(_, k, v)
         if rawget(t,k) ~= nil then
            rawset(t,k,v)
         else
            error("Attempting to create field '"..tostring(k).."' in a safe table.")
         end
      end,
   })
   return st
end

function safer.globals(exception_globals, exception_nils)
   exception_globals = exception_globals or {}
   exception_nils = exception_nils or {}
   -- used in typical portability tests
   local allowed_nils = {
      module = true,
      loadstring = true,
      unpack = true,
      jit = true,
      PROXY = true, -- luasocket
   }
   -- legacy modules that set globals
   local allowed_globals = {
      lfs = true, -- luafilesystem
      copcall = true,
      coxpcall = true,
      logging = true, -- lualogging
      TIMEOUT = true, -- luasocket
   }
   setmetatable(_G, {
      __index = function(_, k)
         if allowed_nils[k] or exception_nils[k] then
            return nil
         end
         error("Attempting to access an undeclared global '"..k.."'\n"..debug.traceback())
      end,
      __newindex = function(t, k, v)
         if allowed_globals[k] or exception_globals[k] then
            rawset(t, k, v)
            return
         end
         error("Attempting to assign a new global '"..k.."'\n"..debug.traceback())
      end,
   })
end

return safer
end
end

do
local _ENV = _ENV
package.preload[ "toml" ] = function( ... ) local arg = _G.arg;
-- The MIT License (MIT)

-- Copyright (c) 2017 Jonathan Stoler
-- Copyright (c) 2025 Oleg Pustovit
-- Copyright (c) 2020-2025 Contributors (https://github.com/nexo-tech/toml2lua)

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local TOML = {
	-- denotes the current supported TOML version
	version = "1.0.0",

	-- sets whether the parser should follow the TOML spec strictly
	-- currently, no errors are thrown for the following rules if strictness is turned off:
	--   tables having mixed keys
	--   redefining a table
	--   redefining a key within a table
	strict = true,
}

-- Value type creators for toml-test compatible intermediate format
local function createTomlTestValue(tomlType, value)
	return { type = tomlType, value = tostring(value) }
end

-- Compatibility creators that maintain current behavior for now
local function createStringValue(str)
	return { value = str, type = "string" }
end

local function createIntegerValue(num)
	return { value = num, type = "integer" }
end

local function createFloatValue(num)
	return { value = num, type = "float" }
end

local function createBooleanValue(bool)
	return { value = bool, type = "boolean" }
end

local function createDateValue(dateObj)
	return { value = dateObj, type = "date" }
end

local function createArrayValue(arr)
	return { value = arr, type = "array" }
end

-- Helper function to determine the correct TOML type for dates
local function getDateTomlType(dateObj)
	if dateObj.year and dateObj.hour and dateObj.zone ~= nil then
		return "datetime"
	elseif dateObj.year and dateObj.hour and dateObj.zone == nil then
		return "datetime-local"
	elseif dateObj.year and not dateObj.hour then
		return "date-local"
	elseif not dateObj.year and dateObj.hour then
		return "time-local"
	else
		return "datetime" -- fallback
	end
end

-- Convert from internal format to toml-test format
local function toTomlTestFormat(internalValue)
	if internalValue.type == "string" then
		return createTomlTestValue("string", internalValue.value)
	elseif internalValue.type == "integer" then
		return createTomlTestValue("integer", internalValue.value)
	elseif internalValue.type == "float" then
		-- Handle special float values
		if internalValue.value == math.huge then
			return createTomlTestValue("float", "inf")
		elseif internalValue.value == -math.huge then
			return createTomlTestValue("float", "-inf")
		elseif internalValue.value ~= internalValue.value then -- NaN check
			return createTomlTestValue("float", "nan")
		else
			return createTomlTestValue("float", internalValue.value)
		end
	elseif internalValue.type == "boolean" then
		return createTomlTestValue("bool", internalValue.value)
	elseif internalValue.type == "date" then
		local dateType = getDateTomlType(internalValue.value)
		return createTomlTestValue(dateType, internalValue.value)
	elseif internalValue.type == "array" then
		-- Arrays are handled differently - they remain as Lua tables
		return internalValue
	else
		return internalValue -- fallback
	end
end

-- Convert from toml-test format back to Lua native types (for final output)
local function fromTomlTestFormat(tomlTestValue)
	if tomlTestValue.type == "string" then
		return tomlTestValue.value
	elseif tomlTestValue.type == "integer" then
		return tonumber(tomlTestValue.value)
	elseif tomlTestValue.type == "float" then
		local val = tomlTestValue.value
		if val == "inf" then
			return math.huge
		elseif val == "-inf" then
			return -math.huge
		elseif val == "nan" then
			return 0 / 0
		else
			return tonumber(val)
		end
	elseif tomlTestValue.type == "bool" then
		return tomlTestValue.value == "true"
	elseif tomlTestValue.type:match("^date") or tomlTestValue.type:match("^time") then
		return tomlTestValue.value -- date objects remain as-is
	else
		return tomlTestValue.value -- fallback
	end
end

local date_metatable = {
	__tostring = function(t)
		local rep = ''
		if t.year then
			rep = rep .. string.format("%04d-%02d-%02d", t.year, t.month, t.day)
		end
		if t.hour then
			if t.year then
				rep = rep .. ' '
			end
			rep = rep .. string.format("%02d:%02d:", t.hour, t.min)
			local sec, frac = math.modf(t.sec)
			rep = rep .. string.format("%02d", sec)
			if frac > 0 then
				rep = rep .. tostring(frac):gsub("0(.-)0*$", "%1")
			end
		end
		if t.zone then
			if t.zone >= 0 then
				rep = rep .. '+' .. string.format("%02d:00", t.zone)
			elseif t.zone < 0 then
				rep = rep .. '-' .. string.format("%02d:00", -t.zone)
			end
		end
		return rep
	end,
}

local setmetatable, getmetatable = setmetatable, getmetatable

TOML.datefy = function(tab)
	-- Validate date/time components
	if tab.year and (tab.year < 0 or tab.year > 9999) then
		return nil, "Invalid year"
	end
	if tab.month and (tab.month < 1 or tab.month > 12) then
		return nil, "Invalid month"
	end
	if tab.day and (tab.day < 1 or tab.day > 31) then
		return nil, "Invalid day"
	end
	if tab.hour and (tab.hour < 0 or tab.hour > 23) then
		return nil, "Invalid hour"
	end
	if tab.min and (tab.min < 0 or tab.min > 59) then
		return nil, "Invalid minute"
	end
	if tab.sec and (tab.sec < 0 or tab.sec > 60) then -- Allow leap seconds
		return nil, "Invalid second"
	end
	if tab.zone and (tab.zone < -23 or tab.zone > 23) then
		return nil, "Invalid timezone"
	end

	-- Additional validation for day based on month/year
	if tab.year and tab.month and tab.day then
		local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

		-- Check for leap year
		if tab.month == 2 and ((tab.year % 4 == 0 and tab.year % 100 ~= 0) or (tab.year % 400 == 0)) then
			days_in_month[2] = 29
		end

		if tab.day > days_in_month[tab.month] then
			return nil, "Invalid day for month"
		end
	end

	return setmetatable(tab, date_metatable)
end

TOML.isdate = function(tab)
	return getmetatable(tab) == date_metatable
end

-- converts TOML data into a lua table
TOML.multistep_parser = function(options)
	options = options or {}
	local strict = (options.strict ~= nil and options.strict or TOML.strict)
	local toml = ''

	-- the output table
	local out = {}
	local ERR = {}

	-- the current table to write to
	local obj = out

	-- stores text data
	local buffer = ""

	-- the current location within the string to parse
	local cursor = 1

	-- remember that the last chunk was already read
	local stream_ended = false

	local nl_count = 1

	local function result_or_error()
		if #ERR > 0 then return nil, ERR[1] end
		return out
	end

	-- produce a parsing error message
	-- the error contains the line number of the current position
	local function err(message, strictOnly)
		if not strictOnly or (strictOnly and strict) then
			local line = 1
			local c = 0
			local msg = "At TOML line " .. nl_count .. ': ' .. message .. "."
			if not ERR[msg] then
				ERR[1 + #ERR] = msg
				ERR[msg] = true
			end
		end
	end

	-- read n characters (at least) or chunk terminator (nil)
	local function getNewData(n)
		while not stream_ended do
			if cursor + (n or 0) < #toml then break end
			local new_data = coroutine.yield(result_or_error())
			if new_data == nil then
				stream_ended = true
				break
			end
			toml = toml:sub(cursor)
			cursor = 1
			toml = toml .. new_data
		end
	end

	-- TODO : use 1-based indexing ?
	-- returns the next n characters from the current position
	local function getData(a, b)
		getNewData(b)
		a = a or 0
		b = b or (toml:len() - cursor)
		return toml:sub(cursor + a, cursor + b)
	end

	-- returns the next n characters from the current position
	local function char(n)
		n = n or 0
		return getData(n, n)
	end

	-- count how many new lines are in the next n chars
	local function count_source_line(n)
		local count = 0
		for _ in getData(0, n - 1):gmatch('\n') do
			count = count + 1
		end
		return count
	end

	-- function to check if current position is at a newline (LF or CRLF)
	local function isNewline()
		if char() == "\10" then                    -- LF
			return true
		elseif char() == "\13" and char(1) == "\10" then -- CRLF
			return true
		end
		return false
	end

	-- moves the current position forward n (default: 1) characters
	local function step(n)
		n = n or 1
		nl_count = nl_count + count_source_line(n)
		cursor = cursor + n
	end

	-- prevent infinite loops by checking whether the cursor is
	-- at the end of the document or not
	local function bounds()
		if cursor <= toml:len() then return true end
		getNewData(1)
		return cursor <= toml:len()
	end

	-- Check if we are at end of the data
	local function dataEnd()
		return cursor >= toml:len()
	end

	-- Match official TOML definition of whitespace
	local function matchWs(n)
		n = n or 0
		return getData(n, n):match("[\009\032]")
	end

	-- Match the official TOML definition of newline
	local function matchnl(n)
		n = n or 0
		local c = getData(n, n)
		if c == '\10' then return '\10' end
		return getData(n, n + 1):match("^\13\10")
	end

	-- move forward until the next non-whitespace character
	local function skipWhitespace()
		while (matchWs()) do
			step()
		end
	end

	-- remove the (Lua) whitespace at the beginning and end of a string
	local function trim(str)
		return str:gsub("^%s*(.-)%s*$", "%1")
	end

	-- divide a string into a table around a delimiter
	local function split(str, delim)
		if str == "" then return {} end
		local result = {}
		local append = delim
		if delim:match("%%") then
			append = delim:gsub("%%", "")
		end
		for match in (str .. append):gmatch("(.-)" .. delim) do
			table.insert(result, match)
		end
		return result
	end

	local function parseString()
		local quoteType = char() -- should be single or double quote

		-- this is a multiline string if the next 2 characters match
		local multiline = (char(1) == char(2) and char(1) == char())

		-- buffer to hold the string
		local str = ""

		-- skip the quotes
		step(multiline and 3 or 1)

		local foundClosingQuote = false

		while (bounds()) do
			if multiline and matchnl() and str == "" then
				-- skip line break line at the beginning of multiline string
				if char() == "\13" and char(1) == "\10" then
					step(2) -- skip CRLF
				else
					step() -- skip LF
				end
			end

			-- keep going until we encounter the quote character again
			if char() == quoteType then
				if multiline then
					if char(1) == char(2) and char(1) == quoteType then
						step(3)
						foundClosingQuote = true
						break
					end
				else
					step()
					foundClosingQuote = true
					break
				end
			end

			if matchnl() and not multiline then
				err("Single-line string cannot contain line break")
			end

			-- if we're in a double-quoted string, watch for escape characters!
			if quoteType == '"' and char() == "\\" then
				if multiline and matchnl(1) then
					-- skip until first non-whitespace character
					step(1) -- go past the line break
					while (bounds()) do
						if not matchWs() and not matchnl() then
							break
						end
						if isNewline() then
							if char() == "\13" and char(1) == "\10" then
								step(2) -- skip CRLF
							else
								step() -- skip LF
							end
						else
							step()
						end
					end
				else
					-- all available escape characters
					local escape = {
						b = "\b",
						t = "\t",
						n = "\n",
						f = "\f",
						r = "\r",
						['"'] = '"',
						["\\"] = "\\",
					}
					-- utf function from http://stackoverflow.com/a/26071044
					-- converts \uXXX into actual unicode
					local function utf(char)
						local bytemarkers = { { 0x7ff, 192 }, { 0xffff, 224 }, { 0x1fffff, 240 } }
						if char < 128 then return string.char(char) end
						local charbytes = {}
						for bytes, vals in pairs(bytemarkers) do
							if char <= vals[1] then
								for b = bytes + 1, 2, -1 do
									local mod = char % 64
									char = (char - mod) / 64
									charbytes[b] = string.char(128 + mod)
								end
								charbytes[1] = string.char(vals[2] + char)
								break
							end
						end
						return table.concat(charbytes)
					end

					if escape[char(1)] then
						-- normal escape
						str = str .. escape[char(1)]
						step(2) -- go past backslash and the character
					elseif char(1) == "u" then
						-- utf-16
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4)
						step(5)
						local uniNum = tonumber(uni, 16)
						if not uniNum then
							err("Unicode escape is not a Unicode scalar")
						elseif (uniNum >= 0 and uniNum <= 0xd7ff) and not (uniNum >= 0xe000 and uniNum <= 0x10ffff) then
							str = str .. utf(uniNum)
						else
							err("Unicode escape is not a Unicode scalar")
						end
					elseif char(1) == "U" then
						-- utf-32
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4) .. char(5) .. char(6) .. char(7) .. char(8)
						step(9)
						local uniNum = tonumber(uni, 16)
						if (uniNum >= 0 and uniNum <= 0xd7ff) and not (uniNum >= 0xe000 and uniNum <= 0x10ffff) then
							str = str .. utf(uniNum)
						else
							err("Unicode escape is not a Unicode scalar")
						end
					else
						err("Invalid escape")
						step()
					end
				end
			else
				-- if we're not in a double-quoted string, just append it to our buffer raw and keep going
				str = str .. char()
				step()
			end
		end

		-- If we get here without finding the closing quote, it's an error
		if not foundClosingQuote then
			err("Unterminated string")
		end

		return createStringValue(str)
	end

	-- Unified date/time component matchers
	local function matchDate()
		local year, month, day, n =
			getData(0, 10):match('^(%d%d%d%d)%-([0-1][0-9])%-([0-3][0-9])()')

		if not year then return nil end
		step(n - 1)

		return tonumber(year), tonumber(month), tonumber(day)
	end

	local function matchTime()
		local hour, minute, second, n =
			getData(0, 19):match('^([0-2][0-9])%:([0-6][0-9])%:(%d+%.?%d*)()')

		if not hour then return nil end
		step(n - 1)

		return tonumber(hour), tonumber(minute), tonumber(second)
	end

	local function matchTimezone()
		local eastwest, offset, zero, n =
			getData(0, 6):match('^([%+%-])([0-9][0-9])%:([0-9][0-9])()')

		if not eastwest then return nil end
		step(n - 1)

		return tonumber(eastwest .. offset)
	end

	-- Helper function to create and validate date objects
	local function createValidatedDateValue(components)
		local value, e = TOML.datefy(components)
		if not value then
			err(e)
			return nil
		end
		return createDateValue(value)
	end

	local function parseDate()
		local year, month, day = matchDate()
		if not year then
			err("Invalid date")
			return nil
		end

		local hour, minute, second = nil, nil, nil
		local zone = nil

		-- Check for date-time separator
		if char():match('[T ]') then
			step(1)
			hour, minute, second = matchTime()
			if not hour then
				err("Invalid date")
				return nil
			end

			-- Check for timezone
			if char():match('Z') then
				step(1)
				zone = 0
			else
				zone = matchTimezone()
			end
		end

		local components = {
			year = year,
			month = month,
			day = day,
			hour = hour,
			min = minute,
			sec = second,
			zone = zone,
		}

		return createValidatedDateValue(components)
	end

	local function parseTime()
		local hour, minute, second = matchTime()
		if not hour then
			err("Invalid time")
			return nil
		end

		local components = {
			hour = hour,
			min = minute,
			sec = second,
		}

		return createValidatedDateValue(components)
	end

	-- Helper functions for number parsing
	local function isNumberTerminator()
		return matchWs() or char() == "#" or matchnl() or char() == "," or char() == "]" or char() == "}"
	end

	local function validateUnderscore(currentChar, nextChar, numberStr, prevUnderscore)
		if currentChar == "_" then
			if prevUnderscore then
				err("Double underscore in number")
				return false
			end
			if numberStr == "" then
				err("Underscore cannot be at beginning of number")
				return false
			end
			if numberStr:sub(#numberStr) == "." then
				err("Underscore after decimal point")
				return false
			end
			if nextChar == "." then
				err("Underscore before decimal point")
				return false
			end
			return true
		end
		return false
	end

	local function parseSpecialBaseNumber()
		local prefixes = { ["0x"] = 16, ["0o"] = 8, ["0b"] = 2 }
		local prefix = char() .. char(1)
		local base = prefixes[prefix]
		if not base then return nil end

		step(2)
		local digits = ({ [2] = "[01]", [8] = "[0-7]", [16] = "%x" })[base]
		local num = ""
		local prevUnderscore = false

		while bounds() do
			if char():match(digits) then
				num = num .. char()
				prevUnderscore = false
			elseif isNumberTerminator() then
				break
			elseif char() == "_" then
				if prevUnderscore then
					err("Double underscore in number")
					return false -- Return false to indicate error
				end
				if num == "" then
					err("Underscore cannot be at beginning of number")
					return false
				end
				prevUnderscore = true
			else
				err("Invalid number")
				return false
			end
			step()
		end

		if prevUnderscore then
			err("Invalid underscore at end of number")
			return false
		end
		if num == "" then
			err("Invalid number")
			return false
		end

		return createIntegerValue(tonumber(num, base))
	end

	local function parseNumber()
		-- Try parsing special base numbers first
		local specialResult = parseSpecialBaseNumber()
		if specialResult == false then
			return nil  -- Error in special base parsing
		elseif specialResult then
			return specialResult -- Valid special base number
		end
		-- specialResult is nil, so not a special base number - continue with decimal parsing

		-- Parse decimal numbers
		local num = ""
		local exp = nil
		local dotfound = false
		local prev_underscore = false

		while bounds() do
			if char():match("[%+%-%.eE_0-9]") then
				if char():match '%.' then dotfound = true end

				-- Handle underscore validation
				if validateUnderscore(char(), char(1), num, prev_underscore) then
					prev_underscore = true
				else
					-- Handle exponent
					if not exp then
						if char():lower() == "e" then
							exp = ""
						elseif char() ~= "_" then
							num = num .. char()
						end
					elseif char():match("[%+%-_0-9]") then
						if char() ~= "_" then
							exp = exp .. char()
						end
					else
						err("Invalid exponent")
					end

					prev_underscore = false
				end
			elseif isNumberTerminator() then
				break
			else
				err("Invalid number")
			end
			step()
		end

		if prev_underscore then
			err("Invalid underscore at end of number")
			return nil
		end

		-- Validate number format
		if num:match('^[%+%-]?0[0-9]') then
			err('Leading zero found in number')
		end
		if dotfound and num:match('%.$') then
			err('No trailing zero found in float')
		end

		-- Apply exponent
		local exp_val = exp and tonumber(exp) or 0
		local multiplier = 1
		if exp_val > 0 then
			multiplier = math.floor(10 ^ exp_val)
		elseif exp_val < 0 then
			multiplier = 10 ^ exp_val
		end
		local finalNum = tonumber(num) * multiplier

		-- Return appropriate type
		if exp_val < 0 or dotfound then
			return createFloatValue(finalNum)
		end
		return createIntegerValue(finalNum)
	end

	local parseArray, getValue

	function parseArray()
		step() -- skip [
		skipWhitespace()

		local arrayType
		local array = {}

		while (bounds()) do
			if char() == "]" then
				break
			elseif matchnl() then
				-- skip
				step()
				skipWhitespace()
			elseif char() == "#" then
				while (bounds() and not matchnl()) do
					step()
				end
			else
				-- get the next object in the array
				local v = getValue()
				if not v then break end

				-- v1.0.0 allows mixed types in arrays
				if arrayType == nil then
					arrayType = v.type
				elseif arrayType ~= v.type then
					-- Mixed types are allowed in v1.0.0, so just update arrayType to indicate mixed
					arrayType = "mixed"
				end

				array = array or {}
				table.insert(array, v.value)

				if char() == "," then
					step()
				end
				skipWhitespace()
			end
		end

		-- Check if we found the closing bracket
		if not bounds() or char() ~= "]" then
			err("Missing closing bracket in array")
		end
		step()

		return createArrayValue(array)
	end

	local function parseInlineTable()
		step() -- skip opening brace

		local buffer = ""
		local quoted = false
		local tbl = {}

		while bounds() do
			if char() == "}" then
				break
			elseif char() == "'" or char() == '"' then
				buffer = parseString().value
				quoted = true
				skipWhitespace()
			elseif char() == "=" then
				if not quoted then
					buffer = trim(buffer)
				end

				step() -- skip =
				skipWhitespace()

				if matchnl() then
					err("Newline in inline table")
				end

				local v = getValue().value
				tbl[buffer] = v

				skipWhitespace()

				if char() == "," then
					step()
					skipWhitespace()
					if matchnl() then
						err("Newline in inline table")
					end
				elseif matchnl() then
					err("Newline in inline table")
				end

				quoted = false
				buffer = ""
			else
				if quoted then
					if not matchWs() then
						err("Unexpected character after the key")
					end
				else
					if matchnl() then
						err("Newline in inline table")
					end
					buffer = buffer .. char()
				end
				step()
			end
		end

		-- Check if we found the closing brace
		if not bounds() or char() ~= "}" then
			err("Missing closing brace in inline table")
		end
		step() -- skip closing brace

		return createArrayValue(tbl)
	end

	local function parseBoolean()
		local v
		if getData(0, 3) == "true" then
			step(4)
			v = createBooleanValue(true)
		elseif getData(0, 4) == "false" then
			step(5)
			v = createBooleanValue(false)
		elseif getData(0, 2) == "inf" then
			step(3)
			v = createFloatValue(math.huge)
		elseif getData(0, 3) == "+inf" then
			step(4)
			v = createFloatValue(math.huge)
		elseif getData(0, 3) == "-inf" then
			step(4)
			v = createFloatValue(-math.huge)
		elseif getData(0, 2) == "nan" then
			step(3)
			v = createFloatValue(0 / 0)
		elseif getData(0, 3) == "+nan" then
			step(4)
			v = createFloatValue(0 / 0)
		elseif getData(0, 3) == "-nan" then
			step(4)
			v = createFloatValue(0 / 0)
		else
			err("Invalid primitive")
		end

		skipWhitespace()
		if char() == "#" then
			while (bounds() and not matchnl()) do
				step()
			end
		end

		return v
	end

	-- Value type detection helpers
	local function isStringStart()
		return char() == '"' or char() == "'"
	end

	local function isDateStart()
		return getData(0, 5):match("^%d%d%d%d%-%d")
	end

	local function isTimeStart()
		return getData(0, 3):match("^%d%d%:%d")
	end

	local function isSpecialFloat()
		local data2 = getData(0, 2)
		local data3 = getData(0, 3)
		return data2 == "inf" or data3 == "+inf" or data3 == "-inf" or
			data2 == "nan" or data3 == "+nan" or data3 == "-nan"
	end

	local function isNumberStart()
		return char():match("[%+%-0-9]")
	end

	local function isArrayStart()
		return char() == "["
	end

	local function isInlineTableStart()
		return char() == "{"
	end

	-- figure out the type and get the next value in the document
	function getValue()
		if isStringStart() then
			return parseString()
		elseif isDateStart() then
			return parseDate()
		elseif isTimeStart() then
			return parseTime()
		elseif isSpecialFloat() then
			return parseBoolean() -- Special float values handled in parseBoolean
		elseif isNumberStart() then
			return parseNumber()
		elseif isArrayStart() then
			return parseArray()
		elseif isInlineTableStart() then
			return parseInlineTable()
		else
			return parseBoolean()
		end
	end

	local function parse()
		-- track whether the current key was quoted or not
		local quotedKey = false

		local function check_key()
			if buffer == "" then
				err("Empty key")
			end
			if buffer:match("[%s%c%%%(%)%*%+%.%?%[%]!\"#$&',/:;<=>@`\\^{|}~]") and not quotedKey then
				err('Invalid character in key')
			end
		end

		-- avoid double table definition
		local defined_table = setmetatable({}, { __mode = 'kv' })

		-- keep track of container type i.e. table vs array
		local container_type = setmetatable({}, { __mode = 'kv' })

		local function processKey(isLast, tableArray, quotedKey)
			if isLast and obj[buffer] and not tableArray and #obj[buffer] > 0 then
				err("Cannot redefine table", true)
			end

			-- set obj to the appropriate table so we can start
			-- filling it with values!
			if tableArray then
				-- push onto cache
				local current = obj[buffer]

				-- crete as needed + identify table vs array
				local isArray = false
				if current then
					isArray = (container_type[current] == 'array')
				else
					current = {}
					obj[buffer] = current
					if isLast then
						isArray = true
						container_type[current] = 'array'
					else
						isArray = false
						container_type[current] = 'hash'
					end
				end

				if isLast and not isArray then
					err('The selected key contains a table, not an array', true)
				end

				-- update current object
				if not isLast then obj = current end
				if isArray then
					if isLast then table.insert(current, {}) end
					obj = current[#current]
				end
			else
				local newObj = obj[buffer] or {}
				obj[buffer] = newObj
				if #newObj > 0 then
					if type(newObj) ~= 'table' then
						err('Duplicate field')
					else
						-- an array is already in progress for this key, so modify its
						-- last element, instead of the array itself
						obj = newObj[#newObj]
					end
				else
					obj = newObj
				end
			end
			if isLast then
				if defined_table[obj] then
					err('Duplicated table definition')
				end
				defined_table[obj] = true
			end
		end

		-- track dotted key parsing state
		local dottedKeyParts = {}
		local inDottedKey = false

		-- parse the document!
		while (bounds()) do
			-- skip comments and whitespace
			-- Only treat # as comment if we're not in the middle of parsing a key
			if char() == "#" and (trim(buffer) == "" or quotedKey) then
				while (bounds() and not matchnl()) do
					step()
				end
			end

			if matchnl() then
				if trim(buffer) ~= '' then
					err('Invalid key')
				end
				buffer = ""
				dottedKeyParts = {}
				inDottedKey = false
				step()
			elseif char() == "=" then
				step()
				skipWhitespace()

				-- Add current buffer to dotted key parts if we're in a dotted key
				if inDottedKey then
					if not quotedKey then
						buffer = trim(buffer)
					end
					if buffer ~= "" then
						table.insert(dottedKeyParts, buffer)
					end
				end

				-- Handle dotted keys vs regular keys
				if inDottedKey and #dottedKeyParts > 1 then
					-- This is a dotted key - create nested structure
					local currentObj = obj
					local conflictDetected = false

					for i = 1, #dottedKeyParts - 1 do
						local key = dottedKeyParts[i]
						local numericKey = key
						if key:match("^[0-9]+$") then
							numericKey = tonumber(key)
						end
						if numericKey and not currentObj[numericKey] then
							currentObj[numericKey] = {}
						elseif type(currentObj[numericKey]) ~= "table" then
							err('Cannot create table: key "' .. key .. '" already has a non-table value')
							conflictDetected = true
							break
						end
						currentObj = currentObj[numericKey]
					end

					if not conflictDetected then
						local finalKey = dottedKeyParts[#dottedKeyParts]
						local finalNumericKey = finalKey
						if finalKey:match("^[0-9]+$") then
							finalNumericKey = tonumber(finalKey)
						end

						local v = getValue()
						if v then
							if currentObj[finalNumericKey] ~= nil then
								err('Cannot redefine key "' .. finalKey .. '"', true)
							end
							if finalNumericKey then
								currentObj[finalNumericKey] = v.value
							end
						end
					else
						-- Still need to consume the value even if there was a conflict
						getValue()
					end
				elseif not quotedKey and buffer:find("%.") then
					-- Handle simple dotted keys (backward compatibility)
					local keys = {}
					for key in buffer:gmatch("[^%.]+") do
						table.insert(keys, key)
					end

					-- Validate each key segment
					for _, key in ipairs(keys) do
						local tempBuffer = key
						if tempBuffer:match("[%s%c%%%(%)%*%+%.%?%[%]!\"#$&',/:;<=>@`\\^{|}~]") then
							err('Invalid character in key')
						end
					end

					-- Navigate/create the nested structure
					local currentObj = obj
					local conflictDetected = false
					for i = 1, #keys - 1 do
						local key = keys[i]
						local numericKey = key
						if key:match("^[0-9]+$") then
							numericKey = tonumber(key)
						end
						if numericKey and not currentObj[numericKey] then
							currentObj[numericKey] = {}
						elseif type(currentObj[numericKey]) ~= "table" then
							err('Cannot create table: key "' .. key .. '" already has a non-table value')
							conflictDetected = true
							break
						end
						currentObj = currentObj[numericKey]
					end

					-- Set the final key only if no conflict was detected
					if not conflictDetected then
						local finalKey = keys[#keys]
						local finalNumericKey = finalKey
						if finalKey:match("^[0-9]+$") then
							finalNumericKey = tonumber(finalKey)
						end

						local v = getValue()
						if v and finalNumericKey then
							if currentObj[finalNumericKey] ~= nil then
								err('Cannot redefine key "' .. finalKey .. '"', true)
							end
							currentObj[finalNumericKey] = v.value
						end
					else
						-- Still need to consume the value even if there was a conflict
						getValue()
					end
				else
					-- Regular key handling
					if not quotedKey then
						buffer = trim(buffer)
						check_key()
					end

					local keyForAccess = buffer
					if buffer:match("^[0-9]+$") and not quotedKey then
						local numericBuffer = tonumber(buffer)
						if numericBuffer then
							keyForAccess = numericBuffer
						end
					end

					if buffer == "" and not quotedKey then
						err("Empty key name")
					end
					local v = getValue()
					if v then
						-- if the key already exists in the current object, throw an error
						if obj[keyForAccess] ~= nil then
							err('Cannot redefine key "' .. buffer .. '"', true)
						end
						obj[keyForAccess] = v.value
					end
				end

				-- clear the buffer and reset dotted key state
				buffer = ""
				dottedKeyParts = {}
				inDottedKey = false
				quotedKey = false

				-- skip whitespace and comments
				skipWhitespace()
				if char() == "#" then
					while (bounds() and not matchnl()) do
						step()
					end
				end

				-- if there is anything left on this line after parsing a key and its value,
				-- throw an error
				if not dataEnd() and not matchnl() then
					err("Invalid primitive")
				end
			elseif char() == "[" then
				if trim(buffer) ~= '' then
					err("Invalid key")
				end

				buffer = ""
				step()
				local tableArray = false

				-- if there are two brackets in a row, it's a table array!
				if char() == "[" then
					tableArray = true
					step()
				end

				obj = out

				while (bounds()) do
					if char() == "]" then
						break
					elseif char() == '"' or char() == "'" then
						buffer = parseString().value
						quotedKey = true
					elseif char() == "." then
						step() -- skip period
						if not quotedKey then
							buffer = trim(buffer)
						end
						if not quotedKey then check_key() end
						processKey(false, tableArray, quotedKey)
						buffer = ""
					elseif char() == "[" then
						err('Invalid character in key')
						step()
					else
						buffer = buffer .. char()
						step()
					end
				end
				if tableArray then
					if char(1) ~= "]" then
						err("Mismatching brackets")
					else
						step() -- skip inside bracket
					end
				end
				step() -- skip outside bracket
				if not quotedKey then
					buffer = trim(buffer)
				end
				if not quotedKey then check_key() end
				processKey(true, tableArray, quotedKey)
				buffer = ""
				buffer = ""
				quotedKey = false
				skipWhitespace()
				if bounds() and (not char():match('#') and not matchnl()) then
					err("Something found on the same line of a table definition")
				end
			elseif char() == "." then
				-- Handle dot in dotted key
				if buffer == "" then
					err("Empty key segment before dot")
				end

				-- Add current buffer content to dotted key parts
				if not quotedKey then
					buffer = trim(buffer)
				end
				if buffer == "" then
					err("Empty key segment")
				end
				table.insert(dottedKeyParts, buffer)
				inDottedKey = true
				buffer = ""
				quotedKey = false
				step()
			elseif (char() == '"' or char() == "'") then
				-- quoted key
				buffer = parseString().value
				quotedKey = true
			else
				if not quotedKey then
					buffer = buffer .. (matchnl() and "" or char())
				end
				step()
			end
		end

		-- Check for incomplete line at end of file
		if trim(buffer) ~= '' then
			err('Invalid key')
		end

		return result_or_error()
	end

	local coparse = coroutine.wrap(parse)
	coparse()
	return coparse
end

TOML.parse = function(data, options)
	local cp = TOML.multistep_parser(options)
	cp(data)
	return cp()
end

-- Parse TOML and return values in toml-test intermediate format
-- This can be useful for debugging or when you need explicit type information
TOML.parseToTestFormat = function(data, options)
	options = options or {}
	local originalParser = TOML.multistep_parser(options)

	-- Create a modified parser that returns toml-test format
	local function convertToTestFormat(result)
		if type(result) ~= "table" then
			return result
		end

		local converted = {}
		for key, value in pairs(result) do
			if type(value) == "table" and value.type and value.value ~= nil then
				-- This looks like an intermediate format value, convert it
				converted[key] = toTomlTestFormat(value)
			elseif type(value) == "table" then
				-- Recursively convert nested tables
				converted[key] = convertToTestFormat(value)
			else
				-- Native Lua value, wrap it appropriately
				local valueType = type(value)
				if valueType == "string" then
					converted[key] = createTomlTestValue("string", value)
				elseif valueType == "number" then
					if value == math.floor(value) then
						converted[key] = createTomlTestValue("integer", value)
					else
						converted[key] = createTomlTestValue("float", value)
					end
				elseif valueType == "boolean" then
					converted[key] = createTomlTestValue("bool", value)
				else
					converted[key] = value
				end
			end
		end
		return converted
	end

	originalParser(data)
	local result = originalParser()
	if result then
		return convertToTestFormat(result)
	end
	return result
end

TOML.encode = function(tbl)
	local toml = ""

	local cache = {}

	-- Helper function to encode keys properly according to TOML v1.0.0 spec
	local function encodeKey(key)
		local keyStr = tostring(key)

		-- Empty keys must be quoted
		if keyStr == "" then
			return '""'
		end

		-- Check if the key needs quoting (contains special characters)
		-- Bare keys may only contain ASCII letters, ASCII digits, underscores, and dashes (A-Za-z0-9_-)
		if keyStr:match("^[A-Za-z0-9_%-]+$") then
			return keyStr
		else
			-- Key needs to be quoted, escape quotes and backslashes
			local escapedKey = keyStr:gsub("\\", "\\\\"):gsub('"', '\\"')
			return '"' .. escapedKey .. '"'
		end
	end

	-- Helper function to encode dotted table names
	local function encodeDottedName(keyList)
		local encodedKeys = {}
		for i, key in ipairs(keyList) do
			table.insert(encodedKeys, encodeKey(key))
		end
		return table.concat(encodedKeys, ".")
	end

	-- Helper function to get sorted keys for consistent output order
	local function getSortedKeys(t)
		local keys = {}
		for k in pairs(t) do
			table.insert(keys, k)
		end
		-- Sort keys, handling mixed types gracefully
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta == tb then
				return tostring(a) > tostring(b) -- Reverse alphabetical order
			else
				return ta < tb       -- type names sorted alphabetically
			end
		end)
		return keys
	end

	local function parse(tbl)
		local keys = getSortedKeys(tbl)

		-- First pass: handle all non-table values
		for _, k in ipairs(keys) do
			local v = tbl[k]
			if type(v) == "boolean" then
				toml = toml .. encodeKey(k) .. " = " .. tostring(v) .. "\n"
			elseif type(v) == "number" then
				-- Handle special float values for v1.0.0 compatibility
				if v == math.huge then
					toml = toml .. encodeKey(k) .. " = inf\n"
				elseif v == -math.huge then
					toml = toml .. encodeKey(k) .. " = -inf\n"
				elseif v ~= v then -- NaN check (NaN != NaN)
					toml = toml .. encodeKey(k) .. " = nan\n"
				else
					toml = toml .. encodeKey(k) .. " = " .. tostring(v) .. "\n"
				end
			elseif type(v) == "string" then
				local quote = '"'
				v = v:gsub("\\", "\\\\")

				-- if the string has any line breaks, make it multiline
				if v:match("^\n(.*)$") then
					quote = quote:rep(3)
					v = "\\n" .. v
				elseif v:match("\n") then
					quote = quote:rep(3)
				end

				v = v:gsub("\b", "\\b")
				v = v:gsub("\t", "\\t")
				v = v:gsub("\f", "\\f")
				v = v:gsub("\r", "\\r")
				v = v:gsub('"', '\\"')
				toml = toml .. encodeKey(k) .. " = " .. quote .. v .. quote .. "\n"
			elseif type(v) == "table" and getmetatable(v) == date_metatable then
				toml = toml .. encodeKey(k) .. " = " .. tostring(v) .. "\n"
			end
		end

		-- Second pass: handle simple array values (arrays of non-tables)
		for _, k in ipairs(keys) do
			local v = tbl[k]
			if type(v) == "table" and getmetatable(v) ~= date_metatable then
				-- Check if this is an array (all numeric keys)
				local isArray = true
				local isArrayOfHashTables = true
				for kk, vv in pairs(v) do
					if type(kk) ~= "number" then
						isArray = false
						break
					end
					if type(vv) ~= "table" then
						isArrayOfHashTables = false
					else
						-- Check if the inner table is a hash table (has non-numeric keys)
						local isHashTable = false
						local hasKeys = false
						for kkk, vvv in pairs(vv) do
							hasKeys = true
							if type(kkk) ~= "number" then
								isHashTable = true
								break
							end
						end
						-- Empty tables are considered hash tables for array of tables syntax
						if hasKeys and not isHashTable then
							isArrayOfHashTables = false
						end
					end
				end

				if isArray and not isArrayOfHashTables then
					-- Check if this is an array of arrays (all elements are arrays)
					local isArrayOfArrays = true
					for kk, vv in pairs(v) do
						if type(vv) ~= "table" then
							isArrayOfArrays = false
							break
						end
						-- Check if the inner table is also an array
						for kkk, vvv in pairs(vv) do
							if type(kkk) ~= "number" then
								isArrayOfArrays = false
								break
							end
						end
						if not isArrayOfArrays then break end
					end

					if isArrayOfArrays then
						-- This is an array of arrays, encode as nested arrays
						toml = toml .. encodeKey(k) .. " = ["
						local first_outer = true
						for kk, vv in pairs(v) do
							if not first_outer then
								toml = toml .. ", "
							end
							toml = toml .. "["
							local first_inner = true
							for kkk, vvv in pairs(vv) do
								if not first_inner then
									toml = toml .. ", "
								end
								if type(vvv) == "number" then
									-- Check if any number in any array is a float
									local hasFloat = false
									for _, arr in pairs(v) do
										for _, val in pairs(arr) do
											if type(val) == "number" and val ~= math.floor(val) then
												hasFloat = true
												break
											end
										end
										if hasFloat then break end
									end
									if hasFloat then
										toml = toml .. string.format("%.1f", vvv)
									else
										toml = toml .. tostring(vvv)
									end
								else
									toml = toml .. tostring(vvv)
								end
								first_inner = false
							end
							toml = toml .. "]"
							first_outer = false
						end
						toml = toml .. "]\n"
					else
						-- This is a simple array, use multi-line format
						toml = toml .. encodeKey(k) .. " = [\n"
						for kk, vv in pairs(v) do
							if type(vv) == "string" then
								local escaped_string = vv
								escaped_string = escaped_string:gsub("\\", "\\\\")
								escaped_string = escaped_string:gsub("\b", "\\b")
								escaped_string = escaped_string:gsub("\t", "\\t")
								escaped_string = escaped_string:gsub("\f", "\\f")
								escaped_string = escaped_string:gsub("\r", "\\r")
								escaped_string = escaped_string:gsub("\n", "\\n")
								escaped_string = escaped_string:gsub('"', '\\"')
								toml = toml .. '"' .. escaped_string .. '",\n'
							else
								toml = toml .. tostring(vv) .. ",\n"
							end
						end
						toml = toml .. "]\n"
					end
				end
			end
		end

		-- Third pass: handle hash table values and arrays of tables
		for _, k in ipairs(keys) do
			local v = tbl[k]
			if type(v) == "table" and getmetatable(v) ~= date_metatable then
				-- Check if this is an array (all numeric keys)
				local isArray = true
				local isArrayOfHashTables = true
				for kk, vv in pairs(v) do
					if type(kk) ~= "number" then
						isArray = false
						break
					end
					if type(vv) ~= "table" then
						isArrayOfHashTables = false
					else
						-- Check if the inner table is a hash table (has non-numeric keys)
						local isHashTable = false
						local hasKeys = false
						for kkk, vvv in pairs(vv) do
							hasKeys = true
							if type(kkk) ~= "number" then
								isHashTable = true
								break
							end
						end
						-- Empty tables are considered hash tables for array of tables syntax
						if hasKeys and not isHashTable then
							isArrayOfHashTables = false
						end
					end
				end

				if isArray and isArrayOfHashTables then
					-- This is an array of hash tables, use [[table]] syntax
					for kk, vv in pairs(v) do
						toml = toml .. "[[" .. encodeKey(k) .. "]]\n"
						if type(vv) == "table" then
							parse(vv)
						end
					end
				elseif not isArray then
					local array, arrayTable = true, true
					local first = {}
					local tableCopy = {}
					for kk, vv in pairs(v) do
						if type(kk) ~= "number" then array = false end
						if type(vv) ~= "table" then
							first[kk] = vv
							arrayTable = false
						else
							tableCopy[kk] = vv
						end
					end

					if array then
						if arrayTable then
							-- Check if inner tables are arrays (all numeric keys) or hash tables
							local innerTablesAreArrays = true
							for kk, vv in pairs(tableCopy) do
								for k3, v3 in pairs(vv) do
									if type(k3) ~= "number" then
										innerTablesAreArrays = false
										break
									end
								end
								if not innerTablesAreArrays then
									break
								end
							end

							if innerTablesAreArrays then
								-- This is an array of arrays, encode as nested array
								toml = toml .. encodeKey(k) .. " = ["

								-- Check if any element in any array is a float to determine formatting
								local hasFloat = false
								for kk, vv in pairs(tableCopy) do
									for k3, v3 in pairs(vv) do
										if type(v3) == "number" and v3 ~= math.floor(v3) then
											hasFloat = true
											break
										end
									end
									if hasFloat then break end
								end

								local first_element = true
								for kk, vv in pairs(tableCopy) do
									if not first_element then
										toml = toml .. ", "
									end
									toml = toml .. "["
									local first_inner = true

									for k3, v3 in pairs(vv) do
										if not first_inner then
											toml = toml .. ", "
										end
										if type(v3) == "string" then
											toml = toml .. '"' .. v3 .. '"'
										elseif type(v3) == "number" then
											if hasFloat then
												-- Format all numbers as floats for consistency
												toml = toml .. string.format("%.1f", v3)
											else
												toml = toml .. tostring(v3)
											end
										else
											toml = toml .. tostring(v3)
										end
										first_inner = false
									end
									toml = toml .. "]"
									first_element = false
								end
								toml = toml .. "]\n"
							else
								-- double bracket syntax go!
								table.insert(cache, k)
								for kk, vv in pairs(tableCopy) do
									toml = toml .. "[[" .. encodeDottedName(cache) .. "]]\n"
									local tableCopyInner = {}
									local firstInner = {}
									local sortedKeys = getSortedKeys(vv)
									for _, k3 in ipairs(sortedKeys) do
										local v3 = vv[k3]
										if type(v3) ~= "table" then
											firstInner[k3] = v3
										else
											tableCopyInner[k3] = v3
										end
									end
									parse(firstInner)
									parse(tableCopyInner)
								end
								table.remove(cache)
							end
						else
							-- plain ol boring array
							toml = toml .. encodeKey(k) .. " = [\n"
							local quote = '"'
							for kk, vv in pairs(first) do
								if type(vv) == "string" then
									local escaped_string = vv
									escaped_string = escaped_string:gsub("\\", "\\\\")
									escaped_string = escaped_string:gsub("\b", "\\b")
									escaped_string = escaped_string:gsub("\t", "\\t")
									escaped_string = escaped_string:gsub("\f", "\\f")
									escaped_string = escaped_string:gsub("\r", "\\r")
									escaped_string = escaped_string:gsub("\n", "\\n")
									escaped_string = escaped_string:gsub('"', '\\"')
									toml = toml .. quote .. escaped_string .. quote .. ",\n"
								else
									toml = toml .. tostring(vv) .. ",\n"
								end
							end
							toml = toml .. "]\n"
						end
					else
						-- just a key/value table, folks
						table.insert(cache, k)
						toml = toml .. "[" .. encodeDottedName(cache) .. "]\n"
						parse(first)
						parse(tableCopy)
						table.remove(cache)
					end
				end
			end
		end
	end

	parse(tbl)

	return toml:sub(1, -2)
end

return TOML
end
end

--------------------------------------------------------------------------------
-- sets up environment and defines common helper functions
--------------------------------------------------------------------------------
local gears = require "gears"

-- dependencies
local argparse = require "argparse"
local lustache = require "lustache"
local json     = require "json"
local f        = require "F"
local log      = require "log"
local toml     = require "toml"


--------------------------------------------------------------------------------
-- helper functions
--------------------------------------------------------------------------------

local function ensure_table(parent, child_name)
    if nil == parent[child_name] then parent[child_name] = {} end
end

--------------------------------------------------------------------------------
-- handle template state data
--------------------------------------------------------------------------------

local function walk_path(pth, name)
    local function incr_path(fname, root)
        if nil == root then
            return fname
        end
        return root .. "/" .. fname
    end

    local paths = {}
    log.debug(f"Scanning: Path = {pth}, Module = {name}")
    for _, d in pairs(gears.read_dir(pth)) do
        log.debug(f"Found: {d.name}, is_dir={d.is_dir}")
        if d.is_dir then
            log.trace(f"Entering: {d.name}")
            local s_libs = walk_path(
                pth .. "/" .. d.name, incr_path(d.name, name)
            )
            for _, v in pairs(s_libs) do paths[#paths+1] = v end
        else
            paths[#paths+1] = {
                src  = pth .. "/" .. d.name,
                dest = incr_path(d.name, name)
            }
        end
    end

    return paths
end


local function list_to_dict(keys, vals)
    local len_keys = #keys
    local len_vals = #vals
    assert(
        len_keys == len_vals,
        f"len_keys != len_vals ({len_keys} != {len_vals})"
    )

    local tbl = {}
    for z in gears.zip({keys, vals}) do tbl[z[1]] = z[2] end

    return tbl
end


local function save_template(dest_spec, data, tmpl_params, stdout_mode)
    -- short-circuit: if stdout mode, print data instead
    if stdout_mode then
        print(data)
        return
    end

    log.debug(f"Saving to path spec: {dest_spec}")

    local tmpl_dest         = lustache:render(dest_spec, tmpl_params)
    local folder_dest, _, _ = gears.basename(tmpl_dest)
    if not gears.dir_exists(folder_dest) then
        log.info(f"Folder {folder_dest} does not exist, creating")
        gears.mkdir(folder_dest)
    end

    log.debug(f"Saving to concrete path: {tmpl_dest} (parent folder exists)")

    local output_file = io.open(tmpl_dest, "w")
    if nil == output_file then
        log.fatal(f"File creation: {output_file} failed")
        error(f"File creation: {output_file} failed")
    end

    output_file:write(data)
    output_file:close()

    return tmpl_dest
end


local function copy_resource(dest_spec, src, dst, tmpl_params)
    log.debug(f"Copying resource using path spec: {dest_spec}")

    local tmpl_dest = lustache:render(dest_spec, tmpl_params) .. "/" .. dst
    local folder_dest, _, _ = gears.basename(tmpl_dest)
    if not gears.dir_exists(folder_dest) then
        log.info(f"Folder {folder_dest} does not exist, creating")
        gears.mkdir(folder_dest)
    end

    log.debug(f"Copying {src} to {tmpl_dest}")
    gears.cp(src, tmpl_dest)

    return tmpl_dest
end

--------------------------------------------------------------------------------
-- helper functions for parsing templates
-- NOTE: this are using an unofficial lustache API, so this can break whenever
-- lustache is upgraded
--------------------------------------------------------------------------------

local function collect_vars(tokens, vars)
    for _, token in ipairs(tokens) do
        local ttype = token.type
        local tvalue = token.value

        -- Capture variable names from normal tags and unescaped tags
        if ttype == "name" or ttype == "&" or ttype == "{" then
            vars[tvalue] = true

        -- Capture section and inverted section names
        elseif ttype == "#" or ttype == "^" then
            vars[tvalue] = true
            if token.tokens then
                collect_vars(token.tokens, vars) -- recurse into section body
            end

        -- Capture partials
        elseif ttype == ">" then
            vars[tvalue] = true
        end

        -- "text" and "comment" types are ignored
    end
end


local function list_variables(template)
    local tokens = lustache:parse(template)
    local vars = {}
    collect_vars(tokens, vars)
    return vars
end

--------------------------------------------------------------------------------
-- helper functions for manipulating string and lists
--------------------------------------------------------------------------------

local function split(inputstr, sep)
    -- default delimitor is space ("%s")
    if nil == sep then sep = "%s" end

    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end

    return t
end

--------------------------------------------------------------------------------
-- helper functions for manipulating maps
--------------------------------------------------------------------------------

local function check_map(map, var_name, var_val)
    for name, rule in pairs(map) do
        if var_val == rule.trigger[tostring(var_name)] then
            return {name=name, rule=rule.apply}
        end
    end
    return {}
end

local function apply_map(map, params)
    for k, v in pairs(params) do
        local rule = check_map(map, k, v)
        if nil ~= rule.name then
            log.debug("Applying map rule "..rule.name.." to: " .. k)
            for var, val in pairs(rule.rule) do
                local new_val = tonumber(val)
                if nil == new_val then new_val = val end
                log.trace(" + "..params[var].." => "..new_val)
                params[var] = new_val
            end
        end
    end
end

local function ensure_no_placeholders(settings, params)
    local placeholder = settings.placeholder
    if nil == placeholder then
        return
    end

    log.debug("Checking no placeholder strings are present: "..placeholder)
    for k, v in pairs(params) do
        if v == placeholder then
            log.fatal(
                "Variable '"..k.."' contains placeholder string: '"..v.."'"
            )
            error("Placeholder strings still present in template parameters")
        end
    end
end

--------------------------------------------------------------------------------
-- metadata storage for the run
--------------------------------------------------------------------------------

local RUN_DATA = {
    template_files = {},
    resource_files = {},
    settings_file  = {}
}

-- search for resource, template, and settings files

local function walk_template_dir(data, dir, skip)
    -- identify all files in dir
    local files = walk_path(dir)
    -- log files to output
    ---@diagnostic disable-next-line: unused-local
    local files_st = json.encode(files)
    log.info(f"Running in DIR mode, on the following files: {files_st}")
    -- iterate over files, check if they are a template or resource
    for _, v in ipairs(files) do
        -- skip can be either nil, or a regex string, when there is a match, it
        -- is skipped (i.e. identified as a resource)
        if (nil ~= skip) and (string.match(v.src, skip)) then
            log.debug(f"Skipping {v.src} => identified as a resource")
            data.resource_files[v.dest] = v.src
        else
            data.template_files[v.dest] = table.concat(
                gears.read_lines(v.src), "\n"
            )
        end
    end
end


local function identify_files(data, args)
    if args.dir then
        walk_template_dir(data, args.template, args.resource)
    else
        data.template_files["__main__"] = table.concat(
            gears.read_lines(args.template), "\n"
        )
    end

    data.settings_file = table.concat(gears.read_lines(args.settings), "\n")
end


--------------------------------------------------------------------------------
-- parse settings
--------------------------------------------------------------------------------

-- set up CLI parser
local parser = argparse(
    "simple-templates", [[
Fill out templates using Mustache: https://mustache.github.io/.
`simple-templates` uses a settings file (toml) to fill out a template file (any
type, formatted as Mustache). `simple-templates` invokes the template renderer
based on one of three rules -- the template parameter can be either a:
  * constant, which can be overwritten if the parameter is also a `product` or
    `zip` parameter
  * product, which iterates over every combination of inputs
  * zip, which iterates over inputs of the same lenght, combining elements of
    the same index (more details below)

For example:

1. Template: `template.sh`
```
#!/usr/bin/env bash
echo "c1={{c1}}, c2={{c2}}, x={{x}}, y={{y}}"
```

2. Settings: `settings.toml`
```
[constant]
c1 = 10
t = "hi there"

[product]
t = "product"
x = [1, 2, 3]
y = ["a", "b"]

[zip]
t = "zip"
x = [11, 12, 13]
y = [21, 22, 23]
```

3. Invocation: `/simple-templates.ex template.sh settings.toml
"out_{{t}}/{{x}}_{{y}}.sh"`

This will geneterate 9 `.sh` files: 6 from the product iterator (in the
`out_product` folder), and 3 fromt he zip iterator (in the `out_zip` folder).
Note that if no `[product]` or `[zip]` sections are specified, the template
renderer is invoked only once using the values in the `[constant]` section. See
the `test` folder for examples.
]])
parser:argument(
    "template",[[
Template to fill out. The template uses the Mustache
(https://mustache.github.io/) template languate. Notably, this lanuage fills in
all parameters desginated within double curly braces (e.g. `{{x}}`). Every
variable needs to have a corresponding key in the `settings` file, or it must
have a corresponding value in the --overwrite dict. If it doesn't (i.e. it is
undefined), then an error is thrown and the template is not rendered.
]])
parser:argument(
    "settings", [[
Settings file (toml formatted) defining template inputs. Settings are stored in
one of three sections: `[constant]`, `[product]`, and `[zip]`:

* Values in `[constant]` are reused among the other sections (they are constant
accross every invocation). Note that keys in `[product]` and `[zip]` will
overwrite the same key in `[constant]` -- so values in `[constant]` can also be
thought of as defaults.

* Values in `[product]` must be vectors. The template is then involked for
every element of the product space accross all keys in `[product]`. For example
`x=[1,2]` and `y=[11,12,13]` results in the the product space `[(1,11), (1,12),
(1,13), (2,11), (2,12), (2,13)]`. Any non-vector values are automatically
promoted to single-element vectors of that value. Eg. `z="a"` is promoted to
`z=["a"]`.

* Values in `[zip]` must be vectors. The template is then involked for every
element of the inner-product (or zip) space accross all keys in `[zip]`. For
example `x=[1,2]` and `y=[11,12]` results in the the product space `[(1,11),
(2,12)]`. All vectors must have the same length. Any non-vector values are
automatically prmoted to n-element constant vectors of that value where `n` is
the number of elements in each zip vector. E.g. `z="a"` is
promoted to `z=["a", "a"]` (since `x` and `y` both have 2 elements).
]])
parser:argument(
    "output", [[
Path of output file. This can contain mustache placeholders. For example if
given the output path `out_{{x}}/put_{{y}}.txt`, where `x=1` and `y=2` are
parameters in the settings, then the output will be written to:
`out_1/put_2.txt`.
]])
parser:option(
    "--overwrite", [[
JSON-formatted overwrite table, eg: '{\"key\": \"new value\"}'. If `key`
matches a variable defined in the settings file, and if it is present in the
template, then `key` is overwritten by `new value`. NOTE: sometimes the
settings file deliberately might leave a value undefined. If this is the case
then it MUST be defined using `--overwrite` or `--var` (see below).
]]):args(1)
parser:option(
    "--var", [[
Key-value formatted overwrite list. Repeat the vars keyword to populate muliple
key-value pairs. Eg: '--var "X=1" --var "Y=2"'.
]]):count("*")
parser:option(
    "--chmod-overwrite", [[
JSON-formatted overwrite table for chmod, eg: '{\"criterion\": \"new chmod
string\"}'. The <criterion> string is a Lua regex that will be tested against
all path strings being chmod'ed by simple-templates. If there is a postive
match, then the <new chmod string> is applied to that path.
]]):args(1)
parser:option(
    "--dir", [[
Directory mode: <template> must be a directory tree, every contained within is
treated as a template file.
]]):args(0):default(false)
parser:option(
    "--resource", [[
Regex used to check if path should not be rendered. This is only used in
directory module.
]]):args(1)
parser:option(
    "--chmod", [[
Comma-separated list of chmod operations applied to rendered templates.
]]):args(1)
parser:option(
   "--chmod-basename", "Apply `--chmod` operation to basename of path also."
):args(0):default(false)
parser:option(
   "--stdout", "Output written to stdout (turns logging off)."
):args(0):default(false)

parser:help_vertical_space(1)

local args = parser:parse()


-------------------------------------------------------------------------------
-- validate inputs
--------------------------------------------------------------------------------

if args.chmod_basename and (nil == args.chmod) then
    log.fatal("Cannot chmod basename without chmod inputs")
    error("Inconsistent inputs")
end

-------------------------------------------------------------------------------
-- initialize the run
--------------------------------------------------------------------------------

identify_files(RUN_DATA, args)

-- turn logs off if outputting to stdout
if true == args.stdout then log.level = "fatal" end

-- print the settings file (for debug purposes)
if not args.dir then
    log.info("Template:\n" .. RUN_DATA.template_files["__main__"])
end
log.info("Settings:\n" .. RUN_DATA.settings_file)
if nil ~= args.overwrite then
    log.info(f"Overwrite:\n".. args.overwrite)
end

-------------------------------------------------------------------------------
-- process settings
--------------------------------------------------------------------------------

-- load settings from file
local settings  = toml.parse(RUN_DATA.settings_file)
-- ensure that the resulting settings table contains all sections
ensure_table(settings, "settings")
ensure_table(settings, "constant")
ensure_table(settings, "map")
ensure_table(settings, "product")
ensure_table(settings, "zip")
ensure_table(settings, "overwrite")
ensure_table(settings, "chmod_overwrite")
-- decode overwrite table (if given), these will be applied to constaints later
if nil ~= args.overwrite then
    settings.overwrite = json.decode(args.overwrite)
end
if nil ~= args.chmod_overwrite then
    settings.chmod_overwrite = json.decode(args.chmod_overwrite)
end

if nil ~= args.var then
    for k,v in pairs(args.var) do
        local key, val = table.unpack(split(v, "="))
        if nil ~= settings.overwrite[key] then
            log.warn(
                "--var is overwriting existing overwrite: " .. key ..
                " with: " .. val
            )
        end
        settings.overwrite[key] = val
    end
end

-- populate dictionaries of key/vals and (if in debug mode) print how the
-- inputs are interpreted
local ct -- count used to represent the loaded data
local var_assinged = {} -- dictionary used to track which var has been assinged

log.debug("Constants:")
ct = 1

-- vars and vals have same order
local const_vars = {}
local const_vals = {}

---@diagnostic disable-next-line: unused-local
for k, v in pairs(settings.constant) do
    -- check if should overwrite
    if nil ~= settings.overwrite[k] then
        log.warn(f"Overwriting constant: {k}")
        v = settings.overwrite[k]
    end
    -- check if the variable already has a definition
    if nil ~= var_assinged[k] then
        log.warn(f"Variable 'k' has already been defined in an earlier line")
    end

    ---@diagnostic disable-next-line: unused-local
    local tbl_st = json.encode(v)
    log.debug(f" {ct}. {k} = {tbl_st}")

    const_vars[#const_vars+1] = k
    const_vals[#const_vals+1] = v

    ct = ct + 1
    var_assinged[k] = true
end

log.debug("Product Space:")
ct = 1

-- vars and vals have same order
local prod_vars = {}
local prod_vals = {}

---@diagnostic disable-next-line: unused-local
for k, v in pairs(settings.product) do
    -- check if should overwrite
    if nil ~= settings.overwrite[k] then
        log.warn(f"Overwriting product: {k}")
        v = settings.overwrite[k]
    end
    -- check if the variable already has a definition
    if nil ~= var_assinged[k] then
        log.warn(f"Variable 'k' has already been defined in an earlier line")
    end

    if "table" ~= type(v) then
        log.warn(
            f"Constant input detected for {k} = {v}, promoting to table"
        )
        v = {v}
    end

    ---@diagnostic disable-next-line: unused-local
    local tbl_st = json.encode(v)
    log.debug(f" {ct}. {k} = {tbl_st}")

    prod_vars[#prod_vars+1] = k
    prod_vals[#prod_vals+1] = v

    ct = ct + 1
    var_assinged[k] = true
end

log.debug("Zip Space:")
ct = 1

-- vars and vals have same order
local zip_vars = {}
local zip_vals = {}

-- compute the number of elements for any list data; and check if any vector
-- data has the same length
local n_elt = 0
---@diagnostic disable-next-line: unused-local
for k, v in pairs(settings.zip) do
    if "table" == type(v) then
        if 0 == n_elt then
            n_elt = #v
        else
            if #v ~= n_elt then
                log.fatal(f"Key: {k} has an unexpect number of elements")
                error("Inputs contain a ragged array")
            end
        end
    end
end

if (nil ~= settings.zip) and (0 == n_elt) then
    log.warn(
        "No vectors found in zip iterator => assuming single-element vectors only"
    )
    n_elt = 1
end

---@diagnostic disable-next-line: unused-local
for k, v in pairs(settings.zip) do
    -- check if should overwrite
    if nil ~= settings.overwrite[k] then
        log.warn(f"Overwriting zip: {k}")
        v = settings.overwrite[k]
    end
    -- check if the variable already has a definition
    if nil ~= var_assinged[k] then
        log.warn(f"Variable 'k' has already been defined in an earlier line")
    end

    if "table" ~= type(v) then
        log.warn(
            f"Constant input detected for {k} = {v}, promoting to table"
        )
        local val = v
        v = {}
        for _ = 1, n_elt do v[#v+1] = val end
    end
    ---@diagnostic disable-next-line: unused-local
    local tbl_st = json.encode(v)
    log.debug(f" {ct}. {k} = {tbl_st}")

    zip_vars[#zip_vars+1] = k
    zip_vals[#zip_vals+1] = v

    ct = ct + 1
    var_assinged[k] = true
end

--------------------------------------------------------------------------------
-- validate templates
--------------------------------------------------------------------------------

log.info("Validating templates and inputs")

---@diagnostic disable-next-line: unused-local
for path, template_file in pairs(RUN_DATA.template_files) do
    log.debug(f"Validating template: {path}")
    local vars = list_variables(template_file)

    for k, _ in pairs(vars) do
        log.trace(f"Checking if '{k}' has a definition")
        if nil~=var_assinged[k] then
            log.trace("  + it has a regular definition")
            goto continue
        elseif nil~= settings.overwrite[k] then
            log.trace("  + it only exists as an overwrite")
            log.trace("  => setting as constant")

            -- adding overwrite to the list of constants. Didn't do this
            -- earlier (when the constants where being parsed) because it
            -- wasn't clear at that time if this variable is needed. Now that
            -- we know that we _do_ need it, we're adding the overwrite to this
            -- list which will be used below to inantiate the template.
            const_vars[#const_vars+1] = k
            const_vals[#const_vals+1] = settings.overwrite[k]

            goto continue
        else
            log.fatal(f"Variable '{k}' needed but not defined. Stopping!")
            error(f"Could not instantiate template '{path}': '{k}' not defined.")
        end

        ::continue::
    end

    log.debug(f"Template {path} is OK")
end

log.info("All templates and inputs OK")

--------------------------------------------------------------------------------
-- render templates
--------------------------------------------------------------------------------

-- track which output files have been rendered
local output_files = {}

if (nil == next(settings.product)) and (nil == next(settings.zip)) then
    log.warn("No product or zip specified, populating only constants")

    local tmpl = list_to_dict(const_vars, const_vals)
    -- apply maps
    apply_map(settings.map, tmpl)
    ensure_no_placeholders(settings.settings, tmpl)

    ---@diagnostic disable-next-line: unused-local
    local tmpl_st = json.encode(tmpl)
    log.debug(f"Begin generating: Template [ {tmpl_st} ]")

    ---@diagnostic disable-next-line: unused-local
    for path, template_file in pairs(RUN_DATA.template_files) do
        local tmpl_inst = lustache:render(template_file, tmpl)
        local output = args.output
        if args.dir then
            ---@diagnostic disable-next-line: unused-local
            output = f"{output}/{path}"
            log.debug(f"DIR mode detected => appending {path}")
        end
        ---@diagnostic disable-next-line: unused-local
        local tmpl_dest = save_template(output, tmpl_inst, tmpl, args.stdout)
        table.insert(output_files, tmpl_dest)
        log.info(f"Template generated at: {tmpl_dest}")
    end

    for dst, src in pairs(RUN_DATA.resource_files) do
        log.info(f"Copying resource file {src} => {dst}")
        ---@diagnostic disable-next-line: unused-local
        local resource_dst = copy_resource(args.output, src, dst, tmpl)
        table.insert(output_files, tmpl_dest)
        log.info(f"Copied resource to: {resource_dst}")
    end
end

if nil ~= next(settings.product) then
    log.info("Generating product space templates ...")
    for prod_inst in gears.product(prod_vals) do
        local tmpl = list_to_dict(const_vars, const_vals)
        for k, v in pairs(list_to_dict(prod_vars, prod_inst)) do tmpl[k] = v end
        -- apply maps
        apply_map(settings.map, tmpl)
        ensure_no_placeholders(settings.settings, tmpl)

        ---@diagnostic disable-next-line: unused-local
        local tmpl_st = json.encode(tmpl)
        log.debug(f"Begin generating: Template [ {tmpl_st} ]")

        ---@diagnostic disable-next-line: unused-local
        for path, template_file in pairs(RUN_DATA.template_files) do
            local tmpl_inst = lustache:render(template_file, tmpl)
            local output = args.output
            if args.dir then
                ---@diagnostic disable-next-line: unused-local
                output = f"{output}/{path}"
                log.debug(f"DIR mode detected => appending {path}")
            end
            ---@diagnostic disable-next-line: unused-local
            local tmpl_dest = save_template(output, tmpl_inst, tmpl, args.stdout)
            table.insert(output_files, tmpl_dest)
            log.info(f"Template generated at: {tmpl_dest}")
        end

        for dst, src in pairs(RUN_DATA.resource_files) do
            log.info(f"Copying resource file {src} => {dst}")
            ---@diagnostic disable-next-line: unused-local
            local resource_dst = copy_resource(args.output, src, dst, tmpl)
            table.insert(output_files, resource_dst)
            log.info(f"Copied resource to: {resource_dst}")
        end
    end
end

if nil ~= next(settings.zip) then
    log.info("Generating zip space templates ...")
    for zip_inst in gears.zip(zip_vals) do
        local tmpl = list_to_dict(const_vars, const_vals)
        for k, v in pairs(list_to_dict(zip_vars, zip_inst)) do tmpl[k] = v end
        -- apply maps
        apply_map(settings.map, tmpl)
        ensure_no_placeholders(settings.settings, tmpl)

        ---@diagnostic disable-next-line: unused-local
        for path, template_file in pairs(RUN_DATA.template_files) do
            local tmpl_inst = lustache:render(template_file, tmpl)
            local output = args.output
            if args.dir then
                ---@diagnostic disable-next-line: unused-local
                output = f"{output}/{path}"
                log.debug(f"DIR mode detected => appending {path}")
            end
            ---@diagnostic disable-next-line: unused-local
            local tmpl_dest = save_template(output, tmpl_inst, tmpl, args.stdout)
            table.insert(output_files, tmpl_dest)
            log.info(f"Template generated at: {tmpl_dest}")
        end

        for dst, src in pairs(RUN_DATA.resource_files) do
            log.info(f"Copying resource file {src} => {dst}")
            ---@diagnostic disable-next-line: unused-local
            local resource_dst = copy_resource(args.output, src, dst, tmpl)
            table.insert(output_files, resource_dst)
            log.info(f"Copied resource to: {resource_dst}")
        end
    end
end

--------------------------------------------------------------------------------
-- set the correct permission bits
--------------------------------------------------------------------------------

if nil ~= args.chmod then
    local basenames = {}
    log.info("chmod'ing rendered files")
    for _, v in pairs(split(args.chmod, ",")) do
        log.debug("Applying chmod perm: " .. v)
        for _, out_file in pairs(output_files) do
            -- chmod file
            local chmod_str = "chmod -R " .. v .. " " .. out_file
            log.trace("Running: " .. chmod_str)
            os.execute(chmod_str)
            -- check if file is tartet of chmod-overwrite
            for chmod_ow_target, chmod_ow in pairs(settings.chmod_overwrite) do
                if string.match(out_file, chmod_ow_target) then
                    chmod_str = "chmod -R " .. chmod_ow .. " " .. out_file
                    log.trace("Overwriting with extra chmod: " .. chmod_str)
                    os.execute(chmod_str)
                end
            end
            -- in basename mode, chmod the basename of the file also, in order
            -- to avoid duplicating operations, we'll collect a dict of paths
            -- first, and chmod later
            if args.chmod_basename then
                local bn, _, _ = gears.basename(out_file)
                basenames[bn] = false
            end
        end
        -- now chmod all collected basenames
        log.debug("chmod'ing basenames of randered files")
        for k, _ in pairs(basenames) do
            -- don't do '-R' => we're already one dir up due to basename
            local chmod_str = "chmod " .. v .. " " .. k
            log.trace("Running: " .. chmod_str)
            os.execute(chmod_str)
        end
    end
end

--------------------------------------------------------------------------------
-- DONE! (the end)
--------------------------------------------------------------------------------

log.info(">>> DONE DONE DONE DONE DONE DONE <<<")
