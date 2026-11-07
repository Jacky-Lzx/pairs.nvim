# pairs.nvim

Quote and bracket pairing, surround editing and rainbow brackets.

## Features

- Skip existing closers and handle paired Backspace and Enter.
- Opt into padding, multi-character rules, surround and fast wrap.
- Inspect pairing decisions and customize language-specific behavior.

## Requirements

Neovim **0.11+**. No runtime dependencies. Disable competing automatic pairing engines. Tree-sitter support is optional.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/pairs.nvim",
  main = "pairs",
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("pairs").setup({})
```

## Usage

```vim
:PairsInfo
```

In Insert mode, type an opening bracket or quote. Matching closers can be skipped;
Backspace removes an empty pair and Enter handles indentation. Optional surround
and fast-wrap mappings are described in the reference.

## Documentation

- [Complete reference](doc/pairs.txt) — `:help pairs`.
- [Workflow and integration guide](doc/guide.md).
- Diagnose availability with `:checkhealth pairs`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
