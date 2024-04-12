# Difflib

A set of helpers for computing deltas between objects.

Difflib is a partial port of python 3's [difflib](https://github.com/python/cpython/blob/main/Lib/difflib.py).

The port is meant to closely resemble the code, docs, and tests from the python implementation for easy reference between the two.

## Status of the classes and functions to be ported from python 

Completed:
- Class `SequenceMatcher`: A flexible class for comparing pairs of sequences of any type.
  - implemented as the module `Difflib.SequenceMatcher`
- Function `get_close_matches(word, possibilities, n=3, cutoff=0.6)`: Use SequenceMatcher to return list of the best "good enough" matches.
  - implemented in the `Difflib.SequenceMatcher` module

Not Started: 
- Function `context_diff(a, b)`: For two lists of strings, return a delta in context diff format.
- Function `ndiff(a, b)`: Return a delta: the difference between `a` and `b` (lists of strings).
- Function `restore(delta, which)`: Return one of the two sequences that generated an ndiff delta.
- Function `unified_diff(a, b)`: For two lists of strings, return a delta in unified diff format.
- Class `Differ`: For producing human-readable deltas from sequences of lines of text.
- Class `HtmlDiff`: For producing HTML side by side comparison with change highlights.

## Installation

The package can be installed by adding `difflib` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:difflib, "~> 0.1.0"}
  ]
end
```

## Documentation

Complete documentation can be found at [https://hexdocs.pm/difflib](https://hexdocs.pm/difflib)

## Basic Usage

``` elixir
iex> SequenceMatcher.get_close_matches("appel", ["ape", "apple", "peach", "puppy"])
["apple", "ape"]

iex> a = "qabxcd"
iex> b = "abycdf"
iex> SequenceMatcher.get_opcodes(a, b)
[
  {:delete, 0, 1, 0, 0},
  {:equal, 1, 3, 0, 2},
  {:replace, 3, 4, 2, 3},
  {:equal, 4, 6, 3, 5},
  {:insert, 6, 6, 5, 6}
]

iex> a = "abcd"
iex> b = "bcde"
iex> SequenceMatcher.ratio(a, b)
0.75
```
