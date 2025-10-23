# json2nix
> Very simple JSON to Nix converter.

## Features
* Reads from standard input
* Writes to standard output
* Generates the shortest possible literal representation of its input, including:
  * Avoids quoting identifiers unless needed
  * Collapses nested single-key attribute sets to use shorthand syntax

Further formatting is out of scope and better left to a tool like `nixfmt`.

## Why?
Because `nix-instantiate` requires a Nix installation to function, making it unusable in
environments such as those used in sandboxed builds.

The fact that this also uses shorthand syntax for nested single-key attribute sets was just a bonus,
but probably could have justified it existing as well.
