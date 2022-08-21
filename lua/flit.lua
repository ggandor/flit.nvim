local api = vim.api

local state = { prev_input = nil }

local opts = {
  multiline = true,
  eager_ops = true,
}


local function flit(kwargs)
  local ch = require('leap.util')['get-input-by-keymap']({ str = ">" })
  if not ch then
    return
  end
  -- Repeat with the previous input?
  local repeat_key = require('leap.opts').special_keys.repeat_search
  if ch == api.nvim_replace_termcodes(repeat_key, true, true, true) then
    if state.prev_input then
      ch = state.prev_input
    else
      require('leap.util').echo('no previous search')
      return
    end
  else
    state.prev_input = ch
  end
  -- Get targets.
  local pattern = opts.multiline and ch or ('\\%.l' .. ch)
  local pattern = '\\V' .. pattern
  kwargs.targets = require('leap.search')['get-targets'](pattern, {
    ['backward?'] = kwargs.backward,
  })
  if not kwargs.targets then
    return
  end
  -- Additional arguments.
  -- UGLY HACK (using an undocumented leap parameter)! I don't know how to feed
  -- a count value cleanly from the outside.
  if opts.eager_ops and
     string.match(vim.fn.mode(1), 'o') and
     vim.v.count == 0
  then
    kwargs.count = 1
  end
  kwargs.inclusive_op = true
  kwargs.ft = true
  -- Call Leap and sit back while it's doing the heavy lifting.
  require('leap').leap(kwargs)
end


local function setup(kwargs)
  local kwargs = kwargs or {}
  for _, k in ipairs({'eager_ops', 'multiline'}) do
    if not (kwargs[k] == nil) then opts[k] = kwargs[k] end
  end

  -- Provide (the obvious) defaults.
  local key = kwargs.keymaps or { f = 'f', F = 'F', t = 't', T = 'T' }
  -- Set keymaps.
  vim.keymap.set({'n', 'x', 'o'}, key.f, function()
    flit {}
  end, {})
  vim.keymap.set({'n', 'x', 'o'}, key.F, function()
    flit { backward = true }
  end, {})
  vim.keymap.set({'n', 'x', 'o'}, key.t, function()
    flit { offset = -1, t = true }
  end, {})
  vim.keymap.set({'n', 'x', 'o'}, key.T, function()
    flit { backward = true, offset = 1, t = true }
  end, {})

  api.nvim_create_augroup('LeapFt', {})

  -- Set our custom settings on entering Leap.
  api.nvim_create_autocmd('User', { pattern = 'LeapEnter', group = 'LeapFt',
    callback = function ()
      local leap = require('leap')
      if not leap.state.args.ft then
        return
      end
      local is_t = leap.state.args.t
      -- Save the original settings.
      leap.state.saved_opts = {
        labels = vim.deepcopy(leap.opts.labels),
        safe_labels = vim.deepcopy(leap.opts.safe_labels),
        special_keys = vim.deepcopy(leap.opts.special_keys),
      }
      -- Keep only safe labels.
      leap.opts.labels = {}
      -- Remove labels conflicting with the next/prev keys.
      -- The first label will be the repeat key itself.
      -- Note: this doesn't work well for non-alphabetic characters.
      local filtered = { is_t and key.t or key.f }
      local to_ignore = is_t and { key.t, key.T } or { key.f, key.F }
      for _, label in ipairs(leap.opts.safe_labels) do
        if not vim.tbl_contains(to_ignore, label) then
          table.insert(filtered, label)
        end
      end
      leap.opts.safe_labels = filtered
      -- Set the next/prev ("clever-f") keys.
      leap.opts.special_keys.next_match = is_t and key.t or key.f
      leap.opts.special_keys.prev_match = is_t and key.T or key.F
    end
  })

  -- Restore the original settings on exit.
  api.nvim_create_autocmd('User', { pattern = 'LeapLeave', group = 'LeapFt',
    callback = function ()
      local leap = require('leap')
      if leap.state.args.ft then
        for k, v in pairs(leap.state.saved_opts) do
          leap.opts[k] = v
        end
      end
    end,
  })
end


return { setup = setup }
