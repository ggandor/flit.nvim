# flit.nvim

`f`/`F`/`t`/`T` motions on steroids, extending the
[Leap](https://github.com/ggandor/leap.nvim) interface.

![showcase](../media/showcase.gif?raw=true)

## Features

* labeled targets, as usual (opt-out for operations)
* [clever-f](https://github.com/rhysd/clever-f.vim) style repeat, with the
  trigger key itself
* multiline scope (opt-out)
* follow `ignorecase`/`smartcase`

## Status

WIP

## Requirements

* [leap.nvim](https://github.com/ggandor/leap.nvim)

## Setup

`setup` is mandatory to call, but no arguments are necessary, if the defaults
are okay:

```lua
require('flit').setup {
  multiline = true,
  eager_ops = true,  -- jump right to the ([count]th) target (no labels)
  keymaps = { f = 'f', F = 'F', t = 't', T = 'T' }
}
```
