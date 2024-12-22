local api = vim.api

local state = {
  prev_input = nil,
  last = {
    pattern = nil,
    backward = false,
    offset = 0,
  }
}

-- Reinvent The Wheel #1
-- Custom targets callback, ~90% of it replicating what Leap does by default.

local function get_targets_callback (backward, use_no_labels, multiline, repeat_last)

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
    local next_target = require('leap').opts.special_keys.next_target
    local repeat_key = type(next_target) == 'table' and next_target[1] or next_target

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

  -- Construct search pattern from input
  local get_pattern = function (input)
    -- See `expand-to-equivalence-class` in `leap`.
    -- Gotcha! 'leap'.opts redirects to 'leap.opts'.default - we want .current_call!
    local chars = require('leap.opts').eq_class_of[input]
    -- Sanitize input and produce pattern out of each char
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
    -- Construct final search query
    -- \V – disable any magic character(all magic happens explicitly)
    -- \\%.l – search only on current line
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

	-- Will be invoked inside `leap()`.
	return function()
		local pattern
		if require("leap").state.args.dot_repeat or repeat_last then
			pattern = state.last.pattern
      if not state.last.pattern then
        return {}
      end
		else
			local input = get_input()
			if not input then
				return
			end
			pattern = get_pattern(input)
			state.last.pattern = pattern
			state.last.backward = not not backward
		end
		return get_matches_for(pattern)
	end
end


local function flit (args)
  local leap_args = args.leap_args
  local initial_backward = leap_args.backward

  if not args.last then
    state.last.offset = leap_args.offset
  else
    -- Without deep copy, deciding whether search should go backward will
    -- influence parent table of the keymaps
    leap_args = vim.deepcopy(leap_args)
    if state.last.offset then
      if leap_args.backward then
        leap_args.offset = -state.last.offset
      else
        leap_args.offset = state.last.offset
      end
    end
    -- Mimic how vim's default f/F repetition with ;/, works
    --
    -- Cases:
    -- want to go forward(;),  last search went forward  => go forward
    -- want to go forward(;),  last search went backward => go backward
    -- want to go backward(,), last search went forward  => go backward
    -- want to go backward(,), last search went backward => go forward
    --
    -- XOR on booleans, see <https://gist.github.com/gilzoide/6d7c435e4585f8ba96592f89f2442845?permalink_comment_id=4795151#gistcomment-4795151>
    leap_args.backward = (not leap_args.backward) ~= (not state.last.backward)
  end

  leap_args.targets = get_targets_callback(
    leap_args.backward,
    args.use_no_labels,
    args.multiline,
    args.last
  )
  leap_args.opts.labels = {}
  if args.use_no_labels then
    leap_args.opts.safe_labels = {}
  end

  -- Add `;`/`,` as next/prev keys.
  leap_args.opts.special_keys =
    vim.deepcopy(require('leap.opts').default.special_keys)
  local sk = leap_args.opts.special_keys
  if type(sk.next_target) == 'string' then
    sk.next_target = { sk.next_target }
  end
  if type(sk.prev_target) == 'string' then
    sk.prev_target = { sk.prev_target }
  end

	if args.last then
		if initial_backward then
			table.insert(sk.prev_target, ";")
			table.insert(sk.next_target, ",")
		else
			table.insert(sk.next_target, ";")
			table.insert(sk.prev_target, ",")
		end
  else
		table.insert(sk.next_target, ";")
		table.insert(sk.prev_target, ",")
  end

  require('leap').leap(leap_args)
end


local function set_clever_repeat (f, F, t, T)
  api.nvim_create_augroup('FlitCleverF', {})
  api.nvim_create_autocmd('User', {
    pattern = 'LeapEnter',
    group = 'FlitCleverF',
    callback = function ()
      local args = require('leap').state.args
      if not args.ft then
        return
      end

      local cc_opts = require('leap.opts').current_call

      -- Remove labels conflicting with the next/prev keys.
      -- (Note: the t/f flags in `leap_args` have been set in `setup`.)
      local safe_labels = require('leap').opts.safe_labels
      if #safe_labels > 0 then
        local filtered_labels = {}
        -- Note: this is executed on `LeapEnter`, so the label lists
        -- have already been converted to tables.
        for _, label in ipairs(safe_labels) do
          if label ~= (args.t and t or f) and label ~= (args.t and T or F) then
            table.insert(filtered_labels, label)
          end
        end
        cc_opts.safe_labels = filtered_labels
      end

      -- Set next/prev keys.
      -- (Note: `flit()` already forced them into tables.)
      local cc_sk = cc_opts.special_keys
      table.insert(cc_sk.next_target, args.t and t or f)
      table.insert(cc_sk.prev_target, args.t and T or F)
    end
  })
end


-- Reinvent The Wheel #2
-- Ridiculous hack to prevent having to expose a `multiline` flag in
-- the core: switch Leap's backdrop function to our special one here.

local function limit_backdrop_scope_to_current_line ()
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


local function setup (args)
  local args = args or {}

  -- Argument table for `flit()`.
  local flit_args = {}
  flit_args.multiline = args.multiline

  -- Argument table for the `leap()` call inside `flit()`.
  flit_args.leap_args = {}
  flit_args.leap_args.opts = args.opts or {} --> would-be `opts.current_call`
  -- Flag for autocommands (see `set_clever_repeat` & non-multiline hack).
  flit_args.leap_args.ft = true
  flit_args.leap_args.inclusive_op = true

  -- Set keymappings.
  local labeled_modes =
    args.labeled_modes and args.labeled_modes:gsub('v', 'x') or 'x'

  local keys = args.keys or args.keymaps or { f = 'f', F = 'F', t = 't', T = 'T', semicolon = ';', comma = ','}

	local key_specific_flit_args = {
		[keys.f] = { leap_args = {} },
		[keys.F] = { leap_args = { backward = true } },
		[keys.t] = { leap_args = { offset = -1, t = true } },
		[keys.T] = { leap_args = { backward = true, offset = 1, t = true } },
		[keys.semicolon] = { last = true },
		[keys.comma] = { last = true, leap_args = { backward = true } },
	}

  for _, mode in ipairs({'n', 'x', 'o'}) do
    for _, key in pairs(keys) do
      -- NOTE: Make sure to create a new table for each mode (and not
      -- pass the outer one by reference here inside the loop).
      local flit_args = vim.deepcopy(flit_args)
      flit_args.use_no_labels = not labeled_modes:match(mode)
      flit_args = vim.tbl_deep_extend("force", flit_args, key_specific_flit_args[key])

      vim.keymap.set(mode, key, function () flit(flit_args) end)
    end
  end

  if args.clever_repeat ~= false then
    set_clever_repeat(keys.f, keys.F, keys.t, keys.T)
  end

  if args.multiline == false then
    limit_backdrop_scope_to_current_line()
  end
end


return { setup = setup }
