# flit.nvim

`f`/`F`/`t`/`T` motions on steroids, building on the
[Leap](https://github.com/ggandor/leap.nvim) interface.

![showcase](../media/showcase.gif?raw=true)

## Features

* labeled targets (opt-in for all modes)
* [clever-f](https://github.com/rhysd/clever-f.vim) style repeat, with the
  trigger key itself
* multiline scope (opt-out)
* follow `ignorecase`/`smartcase`

## Status

WIP

## Requirements

* [leap.nvim](https://github.com/ggandor/leap.nvim)
* [repeat.vim](https://github.com/tpope/vim-repeat) (transitive)

## Setup

`setup` is mandatory to call, but no arguments are necessary, if the defaults
are okay:

```lua
require('flit').setup {
  keys = { f = 'f', F = 'F', t = 't', T = 'T' },
  -- A string like "nv", "nvo", "o", etc.
  labeled_modes = "v",
  multiline = true,
  -- Like `leap`s similar argument (call-specific overrides).
  -- E.g.: opts = { equivalence_classes = {} }
  opts = {}
}
```
