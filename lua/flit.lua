local api = vim.api

local state = { prev_input = nil }


local function flit(kwargs)
  -- Reinvent The Wheel #1
  -- Custom targets callback, ~90% of it replicating what Leap does by default.

  local function get_input()
    vim.cmd('echo ""')
    local hl = require('leap.highlight')
    if vim.v.count == 0 and not (kwargs.unlabeled and vim.fn.mode(1):match('o')) then
      hl['apply-backdrop'](hl, kwargs.cc.backward)
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
    return '\\V' .. (kwargs.multiline == false and '\\%.l' or '') .. input
  end

  local function get_targets(pattern)
    local search = require('leap.search')
    local bounds = search['get-horizontal-bounds']()
    local match_positions = search['get-match-positions'](
        pattern, bounds, { ['backward?'] = kwargs.cc.backward }
    )
    local targets = {}
    for _, pos in ipairs(match_positions) do
      local line_str = vim.fn.getline(pos[1])
      local start = vim.fn.charidx(line_str, pos[2] - 1)
      local ch = vim.fn.strcharpart(line_str, start, 1, 1)
      table.insert(targets, { pos = pos, chars = { ch } })
    end
    return targets
  end

  -- The actual arguments for `leap` (would-be `opts.current_call`).
  local cc = kwargs.cc or {}

  cc.targets = function()
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
      -- Do not save into `state.dot_repeat`, because that will be
      -- replaced by `leap` completely when setting dot-repeat.
      state.dot_repeat_pattern = pattern
    end
    return get_targets(pattern)
  end

  cc.opts = kwargs.opts or {}
  local key = kwargs.keys
  -- In any case, keep only safe labels.
  cc.opts.labels = {}
  if kwargs.unlabeled then
    cc.opts.safe_labels = {}
  else
    -- Remove labels conflicting with the next/prev keys.
    -- The first label will be the repeat key itself.
    -- Note: this doesn't work well for non-alphabetic characters.
    local filtered = { cc.t and key.t or key.f }
    local to_ignore = cc.t and { key.t, key.T } or { key.f, key.F }
    for _, label in ipairs(require('leap').opts.safe_labels) do
      if not vim.tbl_contains(to_ignore, label) then
        table.insert(filtered, label)
      end
    end
    cc.opts.safe_labels = filtered
  end
  -- Set the next/prev ("clever-f") keys.
  cc.opts.special_keys = vim.deepcopy(require('leap').opts.special_keys)
  if type(cc.opts.special_keys.next_target) == 'string' then
    cc.opts.special_keys.next_target = { cc.opts.special_keys.next_target }
  end
  if type(cc.opts.special_keys.prev_target) == 'string' then
    cc.opts.special_keys.prev_target = { cc.opts.special_keys.prev_target }
  end
  table.insert(cc.opts.special_keys.next_target, cc.t and key.t or key.f)
  table.insert(cc.opts.special_keys.prev_target, cc.t and key.T or key.F)
  -- Add ; and , too.
  table.insert(cc.opts.special_keys.next_target, ';')
  table.insert(cc.opts.special_keys.prev_target, ',')

  require('leap').leap(cc)
end


local function setup(kwargs)
  local kwargs = kwargs or {}
  kwargs.cc = {}  --> would-be `opts.current_call`
  kwargs.cc.ft = true
  kwargs.cc.inclusive_op = true

  -- Set keymappings.
  kwargs.keys = kwargs.keys or kwargs.keymaps or { f = 'f', F = 'F', t = 't', T = 'T' }
  local key = kwargs.keys
  local motion_specific_args = {
    [key.f] = {},
    [key.F] = { backward = true },
    [key.t] = { offset = -1, t = true },
    [key.T] = { backward = true, offset = 1, t = true }
  }
  local labeled_modes = kwargs.labeled_modes and kwargs.labeled_modes:gsub('v', 'x') or "x"
  for _, key in pairs(kwargs.keys) do
    for _, mode in ipairs({'n', 'x', 'o'}) do
      -- Make sure to create a new table for each mode (and not pass the
      -- outer one by reference here inside the loop).
      local kwargs = vim.deepcopy(kwargs)
      kwargs.cc = vim.tbl_extend('force', kwargs.cc, motion_specific_args[key])
      kwargs.unlabeled = not labeled_modes:match(mode)
      vim.keymap.set(mode, key, function () flit(kwargs) end)
    end
  end

  -- Reinvent The Wheel #2
  -- Ridiculous hack to prevent having to expose a `multiline` flag in
  -- the core: switch Leap's backdrop function to our special one here :)
  if kwargs.multiline == false then
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
