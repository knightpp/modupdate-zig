# modupdate-zig

## Why?

I wanted to rewrite <https://github.com/knightpp/modupdate> in Zig and I was bored.

## What does it do?

It uses the `gomod.zig` parser to parse `go.mod` files and then shows TUI to select/filter
dependency names, which will be passed to `go get` to update the deps.

## How is it compared to Go?

Decent. I caught only one segfault during development. And another while adding TUI.

```shell
$ zig build --release=small
$ ls -l ./zig-out/bin/
.rwxrwxr-x 128k user 18 жов 16:55 -I modupdate
```

## What can be improved?

- [x] Replace gum with some native zig TUI lib, there are a few, but it's not enough.
- [ ] Add fuzzy search

## Install

```shell
nix profile install github:knightpp/modupdate-zig
```
