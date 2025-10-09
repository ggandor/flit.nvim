local function setup (kwargs)
  local kwargs = kwargs or {}
  kwargs.opts = kwargs.opts or {}
  local keys = kwargs.keys or { f = 'f', F = 'F', t = 't', T = 'T' }
  local labeled_modes = kwargs.labeled_modes or 'v'

  local function as_ft (key_specific_args)
    local mode = vim.fn.mode(1)
    local safe_labels = nil
    if
      mode:match('n') and not labeled_modes:match('n')
      or mode:match('^[vV]$') and not labeled_modes:match('[vx]')
      or mode:match('o') and not labeled_modes:match('o')
    then
      safe_labels = ''
    end

    local common_args = {
      inputlen = 1,
      inclusive = true,
      pattern = (kwargs.multiline == false)
                  and (function (pat) return '\\%.l'..pat end)
                  or nil,
      opts = vim.tbl_deep_extend('keep', kwargs.opts, {
        labels = '',
        safe_labels = safe_labels,
        case_sensitive = true,
      }),
    }

    return vim.tbl_deep_extend('keep', common_args, key_specific_args)
  end

  local clever = require('leap.user').with_traversal_keys
  local clever_f = kwargs.clever_repeat and clever(keys.f, keys.F) or {}
  local clever_t = kwargs.clever_repeat and clever(keys.t, keys.T) or {}

  for key, args in pairs {
    [keys.f] = { opts = clever_f, },
    [keys.F] = { backward = true, opts = clever_f },
    [keys.t] = { offset = -1, opts = clever_t },
    [keys.T] = { backward = true, offset = 1, opts = clever_t },
  } do
    vim.keymap.set({'n', 'x', 'o'}, key, function ()
      require('leap').leap(as_ft(args))
    end)
  end
end

return { setup = setup }
