local api = vim.api

local state = { prev_input = nil }


local function flit(f_args)
  local l_args = f_args.l_args

  -- Reinvent The Wheel #1
  -- Custom targets callback, ~90% of it replicating what Leap does by default.

  local function get_input()
    vim.cmd('echo ""')
    local hl = require('leap.highlight')
    if vim.v.count == 0 and not (f_args.unlabeled and vim.fn.mode(1):match('o')) then
      hl['apply-backdrop'](hl, l_args.backward)
    end
    hl['highlight-cursor'](hl)
    vim.cmd('redraw')
    local ch = require('leap.util')['get-input-by-keymap']({str = ">"})
    hl['cleanup'](hl, { vim.fn.win_getid() })
    if not ch then
      return
    end
    -- Repeat with the previous input?
    local repeat_key = require('leap.opts').special_keys.next_target[1]
    if ch == api.nvim_replace_termcodes(repeat_key, true, true, true) then
      if state.prev_input then
        ch = state.prev_input
      else
        vim.cmd('echo "no previous search"')
        return
      end
    else
      state.prev_input = ch
    end
    return ch
  end

  local function get_pattern(input)
    -- See `expand-to-equivalence-class` in `leap`.
    -- Gotcha! 'leap'.opts redirects to 'leap.opts'.default - we want .current_call!
    local chars = require('leap.opts').eq_class_of[input]
    if chars then
      chars = vim.tbl_map(function (ch)
        if ch == '\n' then
          return '\\n'
        elseif ch == '\\' then
          return '\\\\'
        else return ch end
      end, chars or {})
      input = '\\(' .. table.concat(chars, '\\|') .. '\\)'  -- "\(a\|b\|c\)"
    end
    return '\\V' .. (f_args.multiline == false and '\\%.l' or '') .. input
  end

  local function get_targets(pattern)
    local search = require('leap.search')
    local bounds = search['get-horizontal-bounds']()
    local match_positions = search['get-match-positions'](
        pattern, bounds, { ['backward?'] = l_args.backward }
    )
    local targets = {}
    local skipcc = vim.fn.has('nvim-0.10') == 1
    local line_str
    local prev_line
    for _, pos in ipairs(match_positions) do
      local line, col = unpack(pos)
      if line ~= prev_line then
        line_str = vim.fn.getline(line)
        prev_line = line
      end
      local start = vim.fn.charidx(line_str, col - 1)
      local ch
      if skipcc then
        ch = vim.fn.strcharpart(line_str, start, 1, 1)
      else
        ch = vim.fn.strcharpart(line_str, start, 1)
      end
      table.insert(targets, { pos = pos, chars = { ch } })
    end
    return targets
  end

  l_args.targets = function()
    local state = require('leap').state
    local pattern
    if state.args.dot_repeat then
      pattern = state.dot_repeat_pattern
    else
      local input = get_input()
      if not input then
        return
      end
      pattern = get_pattern(input)
      local mode = api.nvim_get_mode().mode
      local dot_repeatable_op = mode:match("o") and vim.v.operator ~= "y"
      -- Do not save into `state.dot_repeat`, because that will be
      -- replaced by `leap` completely when setting dot-repeat.
      if dot_repeatable_op then
        state.dot_repeat_pattern = pattern
      end
    end
    return get_targets(pattern)
  end

  -- In any case, keep only safe labels.
  l_args.opts.labels = {}

  if f_args.unlabeled then
    l_args.opts.safe_labels = {}
  else
    -- Remove labels conflicting with the next/prev keys.
    -- The first label will be the repeat key itself.
    -- (Note: this doesn't work well for non-alphabetic characters.)
    -- Note: the t/f flags in `l_args` have been set in `setup`.
    local filtered_labels = {}
    local safe_labels = (l_args.opts.safe_labels or
                         require('leap').opts.safe_labels)
    local to_ignore = (l_args.t and { f_args.keys.t, f_args.keys.T } or
                                    { f_args.keys.f, f_args.keys.F })
    for _, label in ipairs(safe_labels) do
      if not vim.tbl_contains(to_ignore, label) then
        table.insert(filtered_labels, label)
      end
    end
    l_args.opts.safe_labels = filtered_labels
  end

  -- Set the next/prev ("clever-f") keys.
  l_args.opts.special_keys = vim.deepcopy(require('leap').opts.special_keys)
  if type(l_args.opts.special_keys.next_target) == 'string' then
    l_args.opts.special_keys.next_target = { l_args.opts.special_keys.next_target }
  end
  if type(l_args.opts.special_keys.prev_target) == 'string' then
    l_args.opts.special_keys.prev_target = { l_args.opts.special_keys.prev_target }
  end
  table.insert(l_args.opts.special_keys.next_target,
               l_args.t and f_args.keys.t or f_args.keys.f)
  table.insert(l_args.opts.special_keys.prev_target,
               l_args.t and f_args.keys.T or f_args.keys.F)
  -- Add ; and , too.
  table.insert(l_args.opts.special_keys.next_target, ';')
  table.insert(l_args.opts.special_keys.prev_target, ',')

  require('leap').leap(l_args)
end


local function setup(args)
  local setup_args = args or {}
  -- f_args -> argument table for `flit()`
  -- l_args -> argument table for the `leap()` call inside `flit()`
  local f_args = {}
  f_args.multiline = setup_args.multiline
  f_args.l_args = {}
  f_args.l_args.opts = setup_args.opts or {} --> would-be `opts.current_call`
  f_args.l_args.ft = true  -- flag for the autocommands below (non-multiline hack)
  f_args.l_args.inclusive_op = true

  -- Set keymappings.
  f_args.keys = (setup_args.keys or
                 setup_args.keymaps or
                 { f = 'f', F = 'F', t = 't', T = 'T' })
  local key_specific_leap_args = {
    [f_args.keys.f] = {},
    [f_args.keys.F] = { backward = true },
    [f_args.keys.t] = { offset = -1, t = true },
    [f_args.keys.T] = { backward = true, offset = 1, t = true }
  }
  local labeled_modes = setup_args.labeled_modes and setup_args.labeled_modes:gsub('v', 'x') or 'x'
  for _, mode in ipairs({'n', 'x', 'o'}) do
    for _, flit_key in pairs(f_args.keys) do
      -- NOTE: Make sure to create a new table for each mode (and not
      -- pass the outer one by reference here inside the loop).
      local f_args = vim.deepcopy(f_args)
      f_args.unlabeled = not labeled_modes:match(mode)
      for k, v in pairs(key_specific_leap_args[flit_key]) do
        f_args.l_args[k] = v
      end
      vim.keymap.set(mode, flit_key, function ()
        flit(f_args)
      end)
    end
  end

  -- Reinvent The Wheel #2
  -- Ridiculous hack to prevent having to expose a `multiline` flag in
  -- the core: switch Leap's backdrop function to our special one here.
  if setup_args.multiline == false then
    local state = require('leap').state
    local function backdrop_current_line()
      local hl = require('leap.highlight')
      if pcall(api.nvim_get_hl_by_name, hl.group.backdrop, false) then
          local curline = vim.fn.line(".") - 1  -- API indexing
          local curcol = vim.fn.col(".")
          local startcol = state.args.backward and 0 or (curcol + 1)
          local endcol = state.args.backward and (curcol - 1) or -1
          vim.highlight.range(0, hl.ns, hl.group.backdrop,
            { curline, startcol }, { curline, endcol },
            { priority = hl.priority.backdrop }
          )
      end
    end
    api.nvim_create_augroup('Flit', {})
    api.nvim_create_autocmd('User', { pattern = 'LeapEnter', group = 'Flit',
      callback = function ()
        if state.args.ft then
          state.saved_backdrop_fn = require('leap.highlight')['apply-backdrop']
          require('leap.highlight')['apply-backdrop'] = backdrop_current_line
        end
      end
    })
    api.nvim_create_autocmd('User', { pattern = 'LeapLeave', group = 'Flit',
      callback = function ()
        if state.args.ft then
          require('leap.highlight')['apply-backdrop'] = state.saved_backdrop_fn
          state.saved_backdrop_fn = nil
        end
      end
    })
  end
end


return { setup = setup }
