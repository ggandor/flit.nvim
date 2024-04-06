local api = vim.api

local state = { prev_input = nil }


-- Reinvent The Wheel #1
-- Custom targets callback, ~90% of it replicating what Leap does by default.

local function get_targets_callback (backward, use_no_labels, multiline)
  local is_op_mode = vim.fn.mode(1):match('o')

  local with_highlight_chores = function (f)
    local should_apply_backdrop =
      (vim.v.count == 0) and not (is_op_mode and use_no_labels)

    local hl = require('leap.highlight')
    if should_apply_backdrop then
      hl['apply-backdrop'](hl, backward)
    end
    if vim.fn.has('nvim-0.10') == 0 then  -- leap#70
      hl['highlight-cursor'](hl)
    end
    vim.cmd('redraw')
    local res = f()
    hl['cleanup'](hl, { vim.fn.win_getid() })
    return res
  end

  local handle_repeat = function (ch)
    local repeat_key = require('leap.opts').special_keys.next_target[1]
    if ch == api.nvim_replace_termcodes(repeat_key, true, true, true) then
      if state.prev_input then
        return state.prev_input
      else
        vim.cmd('echo "no previous search"')
        return nil
      end
    else
      state.prev_input = ch
      return ch
    end
  end

  local get_input = function ()
    local ch = with_highlight_chores(function ()
      return require('leap.util')['get-input-by-keymap']({str = '>'})
    end)
    if ch then return handle_repeat(ch) end
  end

  local get_pattern = function (input)
    -- See `expand-to-equivalence-class` in `leap`.
    -- Gotcha! 'leap'.opts redirects to 'leap.opts'.default - we want .current_call!
    local chars = require('leap.opts').eq_class_of[input]
    if chars then
      chars = vim.tbl_map(
        function (ch)
          if ch == '\n' then return '\\n'
          elseif ch == '\\' then return '\\\\'
          else return ch
          end
        end,
        chars or {}
      )
      input = '\\(' .. table.concat(chars, '\\|') .. '\\)'  -- '\(a\|b\|c\)'
    end
    return '\\V' .. (multiline == false and '\\%.l' or '') .. input
  end

  local get_matches_for = function (pattern)
    local search = require('leap.search')
    local bounds = search['get-horizontal-bounds']()
    local match_positions = search['get-match-positions'](
        pattern, bounds, { ['backward?'] = backward }
    )
    local targets = {}
    local line_str
    local prev_line
    for _, pos in ipairs(match_positions) do
      local line, col = unpack(pos)
      if line ~= prev_line then
        line_str = vim.fn.getline(line)
        prev_line = line
      end
      local ch = vim.fn.strpart(line_str, col - 1, 1, true)
      table.insert(targets, { pos = pos, chars = { ch } })
    end
    return targets
  end

  return function ()
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
      local dot_repeatable_op = is_op_mode and vim.v.operator ~= 'y'
      -- Do not save into `state.dot_repeat`, because that will be
      -- replaced by `leap` completely when setting dot-repeat.
      if dot_repeatable_op then
        state.dot_repeat_pattern = pattern
      end
    end
    return get_matches_for(pattern)
  end
end


local function flit (kwargs)
  local leap_kwargs = kwargs.leap_kwargs

  local function set_safe_labels (leap_kwargs)
    if kwargs.use_no_labels then
      leap_kwargs.opts.safe_labels = {}
    else
      -- Remove labels conflicting with the next/prev keys.
      -- The first label will be the repeat key itself.
      -- (Note: this doesn't work well for non-alphabetic characters.)
      -- Note: the t/f flags in `leap_kwargs` have been set in `setup`.
      local filtered_labels = {}
      local safe_labels =
        leap_kwargs.opts.safe_labels or require('leap').opts.safe_labels

      if type(safe_labels) == 'string' then
        safe_labels = vim.fn.split(safe_labels, '\\zs')
      end
      local to_ignore =
        leap_kwargs.t and { kwargs.keys.t, kwargs.keys.T } or
                          { kwargs.keys.f, kwargs.keys.F }

      for _, label in ipairs(safe_labels) do
        if not vim.tbl_contains(to_ignore, label) then
          table.insert(filtered_labels, label)
        end
      end
      leap_kwargs.opts.safe_labels = filtered_labels
    end
  end

  local function set_special_keys (leap_kwargs)
    -- Set the next/prev ('clever-f') keys.
    leap_kwargs.opts.special_keys =
      vim.deepcopy(require('leap').opts.special_keys)

    if type(leap_kwargs.opts.special_keys.next_target) == 'string' then
      leap_kwargs.opts.special_keys.next_target =
        { leap_kwargs.opts.special_keys.next_target }
    end
    if type(leap_kwargs.opts.special_keys.prev_target) == 'string' then
      leap_kwargs.opts.special_keys.prev_target =
        { leap_kwargs.opts.special_keys.prev_target }
    end
    table.insert(leap_kwargs.opts.special_keys.next_target,
                 leap_kwargs.t and kwargs.keys.t or kwargs.keys.f)

    table.insert(leap_kwargs.opts.special_keys.prev_target,
                 leap_kwargs.t and kwargs.keys.T or kwargs.keys.F)
    -- Add ; and , too.
    table.insert(leap_kwargs.opts.special_keys.next_target, ';')
    table.insert(leap_kwargs.opts.special_keys.prev_target, ',')
  end

  leap_kwargs.targets = get_targets_callback(
    leap_kwargs.backward, kwargs.use_no_labels, kwargs.multiline
  )
  -- In any case, keep only safe labels.
  leap_kwargs.opts.labels = {}
  set_safe_labels(leap_kwargs)
  set_special_keys(leap_kwargs)

  require('leap').leap(leap_kwargs)
end


local function setup (kwargs)
  local kwargs = kwargs or {}

  -- Argument table for `flit()`.
  local flit_kwargs = {}
  flit_kwargs.multiline = kwargs.multiline

  -- Argument table for the `leap()` call inside `flit()`.
  flit_kwargs.leap_kwargs = {}
  flit_kwargs.leap_kwargs.opts = kwargs.opts or {} --> would-be `opts.current_call`
  flit_kwargs.leap_kwargs.ft = true  -- flag for the autocommands below (non-multiline hack)
  flit_kwargs.leap_kwargs.inclusive_op = true

  -- Set keymappings.
  flit_kwargs.keys = kwargs.keys or
                     kwargs.keymaps or
                     { f = 'f', F = 'F', t = 't', T = 'T' }

  local key_specific_leap_kwargs = {
    [flit_kwargs.keys.f] = {},
    [flit_kwargs.keys.F] = { backward = true },
    [flit_kwargs.keys.t] = { offset = -1, t = true },
    [flit_kwargs.keys.T] = { backward = true, offset = 1, t = true }
  }

  local labeled_modes =
    kwargs.labeled_modes and kwargs.labeled_modes:gsub('v', 'x') or 'x'

  for _, mode in ipairs({'n', 'x', 'o'}) do
    for _, flit_key in pairs(flit_kwargs.keys) do
      -- NOTE: Make sure to create a new table for each mode (and not
      -- pass the outer one by reference here inside the loop).
      local flit_kwargs = vim.deepcopy(flit_kwargs)
      flit_kwargs.use_no_labels = not labeled_modes:match(mode)
      for k, v in pairs(key_specific_leap_kwargs[flit_key]) do
        flit_kwargs.leap_kwargs[k] = v
      end
      vim.keymap.set(mode, flit_key, function () flit(flit_kwargs) end)
    end
  end

  -- Reinvent The Wheel #2
  -- Ridiculous hack to prevent having to expose a `multiline` flag in
  -- the core: switch Leap's backdrop function to our special one here.
  if kwargs.multiline == false then
    local state = require('leap').state

    local function backdrop_current_line ()
      local hl = require('leap.highlight')
      if pcall(api.nvim_get_hl_by_name, hl.group.backdrop, false) then
          local curline = vim.fn.line('.') - 1  -- API indexing
          local curcol = vim.fn.col('.')
          local startcol = state.args.backward and 0 or (curcol + 1)
          local endcol = state.args.backward and (curcol - 1) or (vim.fn.col('$') - 1)
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
