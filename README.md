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

## Workflow

1. Press one of `f/F/t/T`
2. Press the character you are searching for - `y` in the example above
3. To move to the first match and exit flit press `Esc`
4. To move to the second match and exit flit press the original search trigger key (`f` or `t`) then press `Esc`
5. To move to any other match press the label

* The first label is always `f` or `t` lowercase
* You can move to the first match and perform an action there by triggering an operation e.g. `i`, `a`, `ciw`, `yiw`
  * So `f y ciw` will change the word that contains the first `y`
* You can move to the second match and perform an action there by pressing (`f` or `t`) followed by any operation
  * So `ff y ciw` will change the word that contains the second `y` 
* You can move forward by repeatedly pressing `f` (or `t` for a `t` invocation) - [entering traversal mode](https://github.com/ggandor/leap.nvim/#repeat-and-traversal)
* The quickest way to work with the first and second matches is to perfom operations on them instead of pressing `Esc`

## Requirements

* [leap.nvim](https://github.com/ggandor/leap.nvim)

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
