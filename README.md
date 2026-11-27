# VimProject

A small Vim/Neovim plugin for switching between projects with fzf.

A directory counts as a project if it contains a `.git` folder or an empty `.project` file. Any project you visit is saved to a list, so you can jump back to it later.

## Requirements

- Vim with `+terminal` and `+job`, or Neovim
- [fzf](https://github.com/junegunn/fzf) on your `PATH`

## Commands

| Command | What it does |
| --- | --- |
| `:VimProjectOpen` | Pick a saved project. Changes into it and opens its directory. |
| `:VimProjectTerm` | Open a shell in the current project (or pick one first). Reuses the project's shell if it is already running. |
| `:VimProjectTermNew` | Open another shell in the current project (or pick one first), named `<project>-shell-2`, `<project>-shell-3`, and so on. |
| `:VimProjectCd {dir}` | Change into any directory and open it. Projects are saved automatically. |
| `:VimProjectRemove` | Pick a saved project and forget it. Asks first, then deletes its `.project` marker (never the directory or `.git`). |
| `VimProjectCreate({cmd})` | Run `{cmd}` to list directories, pick one with fzf, and turn it into a project by adding a `.project` marker (skipped if it has `.git`). |

## How projects are saved

- Each time Vim starts or the working directory changes, the current directory is saved if it is a project.
- The list is stored in `~/.vim/.projects` (Vim) or `stdpath('config')/.projects` (Neovim). The plugin adds `/.projects` to a `.gitignore` in that folder.

## Installation

With a plugin manager, add this repo, for example with vim-plug:

```vim
Plug 'path/or/url/to/VimProject'
```

Or copy the `plugin/` and `autoload/` folders into your Vim config.

## Tests

```sh
tests/run.sh
```

Runs the test suite in both Vim and Neovim.
