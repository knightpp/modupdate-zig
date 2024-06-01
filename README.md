# modupdate-zig

## Why?

I wanted to rewrite <https://github.com/knightpp/modupdate> in Zig and bored.

## What does it do?

It uses the `gomod.zig` parser to parse `go.mod` files and then executes <https://github.com/charmbracelet/gum#filter>
to filter and select dependency names, which will be passed to `go get` to update the deps.

## How is it compared to Go?

Decent. I caught only one segfault during development. 35K.

```shell
$ zig build --release=small
$ ls -l ./zig-out/bin/
.rwxrwxr-x 35k user 21 тра 15:46 -I modupdate
```

## What can be improved?

Replace gum with some native zig TUI lib, there are a few, but it's not enough.

## Install

```shell
nix profile install github:knightpp/modupdate-zig
```
