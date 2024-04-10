# TODO:
# - create readme
# - package and publish to hex
# - try to implement differ and htmldiffer etc?

defmodule Difflib.SequenceMatcher do
  import While
  import Counter

  counter([:besti, :bestj, :bestsize])

  @moduledoc """
  SequenceMatcher is a flexible module for comparing pairs of sequences of
  any type, so long as the sequence elements are hashable.

  ## The algorithm
  The basic algorithm predates, and is a little fancier than, an algorithm
  published in the late 1980's by Ratcliff and Obershelp under the
  hyperbolic name "gestalt pattern matching".  The basic idea is to find
  the longest contiguous matching subsequence that contains no "junk"
  elements (R-O doesn't address junk).  The same idea is then applied
  recursively to the pieces of the sequences to the left and to the right
  of the matching subsequence.  This does not yield minimal edit
  sequences, but does tend to yield matches that "look right" to people
  SequenceMatcher tries to compute a "human-friendly diff" between two
  sequences.  Unlike e.g. UNIX(tm) diff, the fundamental notion is the
  longest *contiguous* & junk-free matching subsequence.  That's what
  catches peoples' eyes.  The Windows(tm) windiff has another interesting
  notion, pairing up elements that appear uniquely in each sequence.
  That, and the method here, appear to yield more intuitive difference
  reports than does diff.  This method appears to be the least vulnerable
  to synching up on blocks of "junk lines", though (like blank lines in
  ordinary text files, or maybe "<P>" lines in HTML files).  That may be
  because this is the only method of the 3 that has a *concept* of
  "junk" <wink>.

  ## Examples
  Example, comparing two strings, and considering blanks to be "junk"

    iex> is_junk = fn c -> c == " " end
    iex> a = "private Thread currentThread;"
    iex> b = "private volatile Thread currentThread;"
    iex> SequenceMatcher.ratio(a, b, is_junk: is_junk)
    0.8656716417910447

  `ratio/3` returns a float in [0, 1], measuring the "similarity" of the
  sequences.  As a rule of thumb, a `ratio/3` value over 0.6 means the
  sequences are close matches.

  If you're only interested in where the sequences match,
  `get_matching_blocks/3` is handy:

    iex> for {a, b, size} <- SequenceMatcher.get_matching_blocks(a, b, is_junk: is_junk) do
    iex>   IO.puts("a[\#{a}] and b[\#{b}] match for \#{size} elements")
    iex> end
    a[0] and b[0] match for 8 elements
    a[8] and b[17] match for 21 elements
    a[29] and b[38] match for 0 elements

  Note that the last tuple returned by `get_matching_blocks/3` is always a
  dummy, {length(a), length(b), 0}, and this is the only case in which the last
  tuple element (number of elements matched) is 0.

  If you want to know how to change the first sequence into the second,
  use `get_opcodes/3`

    iex> for {op, a1, a2, b1, b2} <- SequenceMatcher.get_opcodes(a, b, is_junk: is_junk) do
    iex>   IO.puts("\#{op} a[\#{a1}:\#{a2}] b[\#{b1}:\#{b2}]")
    iex> end
    equal a[0:8] b[0:8]
    insert a[8:8] b[8:17]
    equal a[8:29] b[17:38]

  See also function `get_close_matches/3` in this module, which shows how
  simple code building on SequenceMatcher can be used to do useful work.

  Timing:  Basic R-O is cubic time worst case and quadratic time expected
  case.  SequenceMatcher is quadratic time for the worst case and has
  expected-case behavior dependent in a complicated way on how many
  elements the sequences have in common; best case time is linear.
  """

  @doc """
  Analyzes an input for junk elements.

  ## Background
  Because is_junk is a user-defined function, and we test
  for junk a LOT, it's important to minimize the number of calls.
  Before the tricks described here, chain_b was by far the most
  time-consuming routine in the whole module!  If anyone sees
  Jim Roskind, thank him again for profile.py -- I never would
  have guessed that.

  The first trick is to build b2j ignoring the possibility
  of junk.  I.e., we don't call is_junk at all yet.  Throwing
  out the junk later is much cheaper than building b2j "right"
  from the start.

  ## Parameters

    - a: The first of two sequences to be compared. The elements of a must be hashable.
    - b: The second of two sequences to be compared. The elements of a must be hashable.
    - opts: Keyword list of options.
      - is_junk: Optional parameter is_junk is a one-argument
    function that takes a sequence element and returns true if the
    element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
    no elements are considered to be junk.  For example, pass
        `fn x -> x == " "`
    if you're comparing lines as sequences of characters, and don't
    want to synch up on blanks or hard tabs.
      - auto_junk: Optional parameter autojunk should be set to false to disable the
    "automatic junk heuristic" that treats popular elements as junk. Default is true.

  ## Example

    iex> is_junk = fn x -> x == " " end
    iex> b = "abcd abcd"
    iex> SequenceMatcher.chain_b(b, is_junk: is_junk)
    %{
      b2j: %{
        "a" => [0, 5],
        "b" => [1, 6],
        "c" => [2, 7],
        "d" => [3, 8]
      },
      isbjunk: #Function<1.118419402/1>,
      isbpopular: #Function<1.118419402/1>,
      bjunk: %{" " => true},
      bpopular: %{}
    }
  """
  def chain_b(b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true])
    is_junk = Keyword.get(validated_opts, :is_junk)
    auto_junk = Keyword.get(validated_opts, :auto_junk)

    vals = get_vals(b)

    b2j =
      Enum.with_index(vals)
      |> Enum.reduce(%{}, fn {elt, i}, acc ->
        indices = Map.get(acc, elt, [])
        Map.put(acc, elt, indices ++ [i])
      end)

    # Purge junk elements
    result =
      if is_nil(is_junk) do
        %{
          junk: %{},
          b2j: b2j
        }
      else
        Map.keys(b2j)
        |> Enum.reduce(%{junk: %{}, b2j: b2j}, fn elt, acc ->
          if is_junk.(elt) do
            %{
              junk: Map.put(acc.junk, elt, true),
              b2j: Map.delete(acc.b2j, elt)
            }
          else
            acc
          end
        end)
      end

    # Purge popular elements that are not junk
    popular = %{}
    n = length(vals)

    next_result =
      if auto_junk and n >= 200 do
        ntest = Float.floor(n / 100) + 1

        Map.to_list(result.b2j)
        |> Enum.reduce(%{popular: popular, b2j: result.b2j}, fn {elt, idxs}, acc ->
          if length(idxs) > ntest do
            %{
              popular: Map.put(acc.popular, elt, true),
              b2j: Map.delete(acc.b2j, elt)
            }
          else
            acc
          end
        end)
      else
        %{
          popular: popular,
          b2j: result.b2j
        }
      end

    # Now for x in b, isjunk.(x) == x in junk, but the latter is much faster.
    # Since the number of *unique* junk elements is probably small, the
    # memory burden of keeping this set alive is likely trivial compared to
    # the size of b2j.
    isbjunk = fn b -> Map.has_key?(result.junk, b) end
    isbpopular = fn b -> Map.has_key?(next_result.popular, b) end

    %{
      b2j: next_result.b2j,
      isbjunk: isbjunk,
      isbpopular: isbpopular,
      bjunk: result.junk,
      bpopular: next_result.popular
    }
  end

  @doc """
  Find longest matching block in a[alo...ahi] and b[blo...bhi].

  ## Description
  If is_junk is not defined:

  Return {i,j,k} such that a[i...i+k] is equal to b[j...j+k], where
      alo <= i <= i+k <= ahi
      blo <= j <= j+k <= bhi
  and for all {i',j',k'} meeting those conditions,
      k >= k'
      i <= i'
      and if i == i', j <= j'

  In other words, of all maximal matching blocks, return one that
  starts earliest in a, and of all those maximal matching blocks that
  start earliest in a, return the one that starts earliest in b.

  ## Parameters

    - a: The first of two sequences to be compared. The elements of a must be hashable.
    - b: The second of two sequences to be compared. The elements of a must be hashable.
    - opts: Keyword list of options.
      - alo: Optional parameter alo is the lower bound of the range in a to consider. Default is 0.
      - ahi: Optional parameter ahi is the upper bound of the range in a to consider. Default is length of a.
      - blo: Optional parameter blo is the lower bound of the range in b to consider. Default is 0.
      - bhi: Optional parameter bhi is the upper bound of the range in b to consider. Default is length of b.
      - is_junk: Optional parameter is_junk is a one-argument
    function that takes a sequence element and returns true if the
    element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
    no elements are considered to be junk.  For example, pass
        `fn x -> x == " "`
    if you're comparing lines as sequences of characters, and don't
    want to synch up on blanks or hard tabs.
      - auto_junk: Optional parameter autojunk should be set to false to disable the
    "automatic junk heuristic" that treats popular elements as junk. Default is true.

  ## Examples

    iex> is_junk = fn x -> x == " " end
    iex> a = " abcd"
    iex> b = "abcd abcd"
    iex> SequenceMatcher.find_longest_match(a, b, alo: 0, ahi: 5, blo: 0, bhi: 9, is_junk: is_junk)
    {1, 0, 4}
    iex> a = "ab"
    iex> b = "c"
    iex> SequenceMatcher.find_longest_match(a, b, alo: 0, ahi: 2, blo: 0, bhi: 1)
    {0, 0, 0}

  ## CAUTION

  CAUTION:  stripping common prefix or suffix would be incorrect.
  E.g.,
     ab
     acab
  Longest matching block is "ab", but if common prefix is
  stripped, it's "a" (tied with "b").  UNIX(tm) diff does so
  strip, so ends up claiming that ab is changed to acab by
  inserting "ca" in the middle.  That's minimal but unintuitive:
  "it's obvious" that someone inserted "ac" at the front.
  Windiff ends up at the same place as diff, but by pairing up
  the unique 'b's and then matching the first two 'a's.
  """
  def find_longest_match(a, b, opts \\ []) do
    validated_opts =
      Keyword.validate!(opts, [:ahi, :bhi, :is_junk, alo: 0, blo: 0, auto_junk: true])

    alo = Keyword.get(validated_opts, :alo)
    blo = Keyword.get(validated_opts, :blo)
    ahi = Keyword.get(validated_opts, :ahi)
    bhi = Keyword.get(validated_opts, :bhi)

    %{b2j: b2j, isbjunk: isbjunk} =
      chain_b(b, Keyword.drop(validated_opts, [:alo, :ahi, :blo, :bhi]))

    ref = :counters.new(3, [:atomics])
    set_besti(ref, alo)
    set_bestj(ref, blo)
    set_bestsize(ref, 0)

    ahi = if is_nil(ahi), do: String.length(a), else: ahi
    bhi = if is_nil(bhi), do: String.length(b), else: bhi

    a_at = if is_binary(a), do: &String.at(a, &1), else: &Enum.at(a, &1)
    b_at = if is_binary(b), do: &String.at(b, &1), else: &Enum.at(b, &1)

    # find longest junk-free match
    # during an iteration of the loop, j2len[j] = length of longest
    # junk-free match ending with a[i-1] and b[j]
    Enum.reduce(alo..(ahi - 1), %{}, fn i, j2len ->
      # look at all instances of a[i] in b; note that because
      # b2j has no junk keys, the loop is skipped if a[i] is junk
      Map.get(b2j, a_at.(i), [])
      |> Enum.reduce_while(%{}, fn j, newj2len ->
        cond do
          j < blo ->
            {:cont, newj2len}

          j >= bhi ->
            {:halt, newj2len}

          true ->
            k = Map.get(j2len, j - 1, 0) + 1

            if k > bestsize(ref) do
              set_besti(ref, i - k + 1)
              set_bestj(ref, j - k + 1)
              set_bestsize(ref, k)
            end

            {:cont, Map.put(newj2len, j, k)}
        end
      end)
    end)

    # Extend the best by non-junk elements on each end.  In particular,
    # "popular" non-junk elements aren't in b2j, which greatly speeds
    # the inner loop above, but also means "the best" match so far
    # doesn't contain any junk *or* popular non-junk elements.
    # max_iterations = min(results.besti - alo, results.bestj - blo)
    while besti(ref) > alo and bestj(ref) > blo and
            not isbjunk.(b_at.(bestj(ref) - 1)) and
            a_at.(besti(ref) - 1) == b_at.(bestj(ref) - 1) do
      dec_besti(ref)
      dec_bestj(ref)
      inc_bestsize(ref)
    end

    while besti(ref) + bestsize(ref) < ahi and bestj(ref) + bestsize(ref) < bhi and
            not isbjunk.(b_at.(bestj(ref) + bestsize(ref))) and
            a_at.(besti(ref) + bestsize(ref)) == b_at.(bestj(ref) + bestsize(ref)) do
      inc_bestsize(ref)
    end

    # Now that we have a wholly interesting match (albeit possibly
    # empty!), we may as well suck up the matching junk on each
    # side of it too.  Can't think of a good reason not to, and it
    # saves post-processing the (possibly considerable) expense of
    # figuring out what to do with it.  In the case of an empty
    # interesting match, this is clearly the right thing to do,
    # because no other kind of match is possible in the regions.
    while besti(ref) > alo and bestj(ref) > blo and
            isbjunk.(b_at.(bestj(ref) - 1)) and
            a_at.(besti(ref) - 1) == b_at.(bestj(ref) - 1) do
      dec_besti(ref)
      dec_bestj(ref)
      inc_bestsize(ref)
    end

    while besti(ref) + bestsize(ref) < ahi and bestj(ref) + bestsize(ref) < bhi and
            isbjunk.(b_at.(bestj(ref) + bestsize(ref))) and
            a_at.(besti(ref) + bestsize(ref)) == b_at.(bestj(ref) + bestsize(ref)) do
      inc_bestsize(ref)
    end

    {besti(ref), bestj(ref), bestsize(ref)}
  end

  @doc """
  Return list of triples describing matching subsequences.

  ## Description
  Each triple is of the form {i, j, n}, and means that
  a[i...i+n] == b[j...j+n].  The triples are monotonically increasing in
  i and in j.  it's also guaranteed that if
  {i, j, n} and {i', j', n'} are adjacent triples in the list, and
  the second is not the last triple in the list, then i+n != i' or
  j+n != j'.  IOW, adjacent triples never describe adjacent equal
  blocks.

  The last triple is a dummy, {a.length, b.length, 0}, and is the only
  triple with n==0.

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.
  - opts: Keyword list of options.
    - is_junk: Optional parameter is_junk is a one-argument
  function that takes a sequence element and returns true if the
  element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
  no elements are considered to be junk.  For example, pass
      `fn x -> x == " "`
  if you're comparing lines as sequences of characters, and don't
  want to synch up on blanks or hard tabs.
    - auto_junk: Optional parameter autojunk should be set to false to disable the
  "automatic junk heuristic" that treats popular elements as junk. Default is true.


  ## Example

    iex> a = "abxcd"
    iex> b = "abcd"
    iex> SequenceMatcher.get_matching_blocks(a, b)
    [{0, 0, 2}, {3, 2, 2}, {5, 4, 0}]
  """
  def get_matching_blocks(a, b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true])
    is_junk = Keyword.get(validated_opts, :is_junk)
    auto_junk = Keyword.get(validated_opts, :auto_junk)

    la = get_length(a)
    lb = get_length(b)

    # This is most naturally expressed as a recursive algorithm, but
    # at least one user bumped into extreme use cases that exceeded
    # the recursion limit on their box.  So, now we maintain a list
    # ('queue`) of blocks we still need to look at, and append partial
    # results to `matching_blocks` in a loop; the matches are sorted
    # at the end. Loop an aribtrary number of times
    matching_blocks =
      reduce_while(%{queue: [{0, la, 0, lb}], mb: []}, fn %{queue: queue, mb: mb} ->
        if queue == [] do
          {:halt, mb}
        else
          [{alo, ahi, blo, bhi} | next_queue] = queue

          {i, j, k} =
            find_longest_match(a, b,
              alo: alo,
              ahi: ahi,
              blo: blo,
              bhi: bhi,
              is_junk: is_junk,
              auto_junk: auto_junk
            )

          x = {i, j, k}

          if k != 0 do
            next_queue =
              if alo < i and blo < j do
                [{alo, i, blo, j}] ++ next_queue
              else
                next_queue
              end

            next_queue =
              if i + k < ahi and j + k < bhi do
                [{i + k, ahi, j + k, bhi}] ++ next_queue
              else
                next_queue
              end

            {:cont, %{queue: next_queue, mb: [x] ++ mb}}
          else
            {:cont, %{queue: next_queue, mb: mb}}
          end
        end
      end)
      |> Enum.sort()

    # It's possible that we have adjacent equal blocks in the
    # matching_blocks list now.
    %{non_adjacent: non_adjacent, i1: i1, j1: j1, k1: k1} =
      matching_blocks
      |> Enum.reduce(%{non_adjacent: [], i1: 0, j1: 0, k1: 0}, fn {i2, j2, k2}, acc ->
        # Is this block adjacent to i1, j1, k1?
        if acc.i1 + acc.k1 == i2 and acc.j1 + acc.k1 == j2 do
          # Yes, so collapse them -- this just increases the length of
          # the first block by the length of the second, and the first
          # block so lengthened remains the block to compare against.
          Map.put(acc, :k1, acc.k1 + k2)
        else
          # Not adjacent.  Remember the first block (k1==0 means it's
          # the dummy we started with), and make the second block the
          # new block to compare against.
          next_non_adjacent =
            if acc.k1 > 0 do
              acc.non_adjacent ++ [{acc.i1, acc.j1, acc.k1}]
            else
              acc.non_adjacent
            end

          %{
            i1: i2,
            j1: j2,
            k1: k2,
            non_adjacent: next_non_adjacent
          }
        end
      end)

    final_non_adjacent = non_adjacent ++ if k1 > 0, do: [{i1, j1, k1}], else: []
    final_non_adjacent ++ [{la, lb, 0}]
  end

  @doc """
  Return list of 5-tuples describing how to turn a into b.

  ## Description

  Each tuple is of the form {tag, i1, i2, j1, j2}.  The first tuple
  has i1 == j1 == 0, and remaining tuples have i1 == the i2 from the
  tuple preceding it, and likewise for j1 == the previous j2.

  The tags are strings, with these meanings:

  'replace':  a[i1...i2] should be replaced by b[j1...j2]
  'delete':   a[i1...i2] should be deleted.
              Note that j1==j2 in this case.
  'insert':   b[j1...j2] should be inserted at a[i1...i1].
              Note that i1==i2 in this case.
  'equal':    a[i1...i2] == b[j1...j2]

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.
  - opts: Keyword list of options.
    - is_junk: Optional parameter is_junk is a one-argument
  function that takes a sequence element and returns true if the
  element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
  no elements are considered to be junk.  For example, pass
      `fn x -> x == " "`
  if you're comparing lines as sequences of characters, and don't
  want to synch up on blanks or hard tabs.
    - auto_junk: Optional parameter autojunk should be set to false to disable the
  "automatic junk heuristic" that treats popular elements as junk. Default is true.


  ## Example

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
  """
  def get_opcodes(a, b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true])

    get_matching_blocks(a, b, validated_opts)
    |> Enum.reduce(%{answer: [], i: 0, j: 0}, fn {ai, bj, size}, acc ->
      # invariant:  we've pumped out correct diffs to change
      # a[0...i] into b[0...j], and the next matching block is
      # a[ai...ai+size] == b[bj...bj+size].  So we need to pump
      # out a diff to change a[i:ai] into b[j...bj], pump out
      # the matching block, and move [i,j] beyond the match
      tag =
        cond do
          acc.i < ai and acc.j < bj -> :replace
          acc.i < ai -> :delete
          acc.j < bj -> :insert
          true -> nil
        end

      next_answer = acc.answer ++ if is_nil(tag), do: [], else: [{tag, acc.i, ai, acc.j, bj}]

      # the list of matching blocks is terminated by a
      # sentinel with size 0
      final_answer =
        next_answer ++ if size > 0, do: [{:equal, ai, ai + size, bj, bj + size}], else: []

      %{answer: final_answer, i: ai + size, j: bj + size}
    end)
    |> Map.get(:answer)
  end

  @doc """
  Isolate change clusters by eliminating ranges with no changes.

  ## Description
  Return a list groups with upto n lines of context.
  Each group is in the same format as returned by `get_opcodes/3`.

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.
  - opts: Keyword list of options.
    - n: Optional parameter n is the number of lines of context to include in each group. Default is 3.
    - is_junk: Optional parameter is_junk is a one-argument
  function that takes a sequence element and returns true if the
  element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
  no elements are considered to be junk.  For example, pass
      `fn x -> x == " "`
  if you're comparing lines as sequences of characters, and don't
  want to synch up on blanks or hard tabs.
    - auto_junk: Optional parameter autojunk should be set to false to disable the
  "automatic junk heuristic" that treats popular elements as junk. Default is true.


  ## Example

    iex> a = Enum.map(1..39, &Integer.to_string/1)
    iex> b = Enum.slice(a, 0..-1)
    iex> b = Enum.slice(b, 0..7) ++ ["i"] ++ Enum.slice(b, 8..-1)
    iex> b = Enum.slice(b, 0..19) ++ ["20x"] ++ Enum.slice(b, 21..-1)
    iex> b = Enum.slice(b, 0..22) ++ Enum.slice(b, 28..-1)
    iex> b = Enum.slice(b, 0..29) ++ ["35y"] ++ Enum.slice(b, 31..-1)
    iex> SequenceMatcher.get_grouped_opcodes(a, b)
    [
      [
        {:equal, 5, 8, 5, 8},
        {:insert, 8, 8, 8, 9},
        {:equal, 8, 11, 9, 12}],
      [
        {:equal, 16, 19, 17, 20},
        {:replace, 19, 20, 20, 21},
        {:equal, 20, 22, 21, 23},
        {:delete, 22, 27, 23, 23},
        {:equal, 27, 30, 23, 26}
      ],
      [
        {:equal, 31, 34, 27, 30},
        {:replace, 34, 35, 30, 31},
        {:equal, 35, 38, 31, 34}
      ]
    ]
  """
  def get_grouped_opcodes(a, b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true, n: 3])
    n = Keyword.get(validated_opts, :n)

    opcodes = get_opcodes(a, b, Keyword.drop(validated_opts, [:n]))
    codes = if(length(opcodes) > 0, do: opcodes, else: [{:equal, 0, 1, 0, 1}])

    # Fixup leading and trailing groups if they show no changes.
    tag_val = codes |> Enum.at(0) |> elem(0)

    codes =
      if tag_val == :equal do
        {tag, i1, i2, j1, j2} = Enum.at(codes, 0)
        List.replace_at(codes, 0, {tag, max(i1, i2 - n), i2, max(j1, j2 - n), j2})
      else
        codes
      end

    tag_val = codes |> Enum.at(-1) |> elem(0)

    codes =
      if tag_val == :equal do
        {tag, i1, i2, j1, j2} = Enum.at(codes, -1)
        List.replace_at(codes, -1, {tag, i1, min(i2, i1 + n), j1, min(j2, j1 + n)})
      else
        codes
      end

    nn = n + n

    %{groups: final_groups, group: final_group} =
      Enum.reduce(codes, %{groups: [], group: []}, fn {tag, i1, i2, j1, j2},
                                                      %{groups: groups, group: group} ->
        # End the current group and start a new one whenever
        # there is a large range with no changes.
        {next_acc, nextij} =
          if tag == :equal and i2 - i1 > nn do
            group = group ++ [{tag, i1, min(i2, i1 + n), j1, min(j2, j1 + n)}]
            groups = groups ++ [group]
            {%{groups: groups, group: []}, %{i1: max(i1, i2 - n), j1: max(j1, j2 - n)}}
          else
            {%{groups: groups, group: group}, %{i1: i1, j1: j1}}
          end

        updated_group = next_acc.group ++ [{tag, nextij.i1, i2, nextij.j1, j2}]

        %{
          groups: next_acc.groups,
          group: updated_group
        }
      end)

    if length(final_group) > 0 and
         not (length(final_group) == 1 and
                final_group |> Enum.at(0) |> elem(0) == :equal) do
      final_groups ++ [final_group]
    else
      final_groups
    end
  end

  @doc """
  Return a measure of the sequences' similarity (float between 0 and 1).

  ## Description

  Where T is the total number of elements in both sequences, and
  M is the number of matches, this is 2.0*M / T.
  Note that this is 1 if the sequences are identical, and 0 if
  they have nothing in common.

  `ratio/3` is expensive to compute if you haven't already computed
  `get_matching_blocks/3` or `get_opcodes/3`, in which case you may
  want to try `quick_ratio/3` or `real_quick_ratio/3` first to get an
  upper bound.

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.
  - opts: Keyword list of options.
    - is_junk: Optional parameter is_junk is a one-argument
  function that takes a sequence element and returns true if the
  element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
  no elements are considered to be junk.  For example, pass
      `fn x -> x == " "`
  if you're comparing lines as sequences of characters, and don't
  want to synch up on blanks or hard tabs.
    - auto_junk: Optional parameter autojunk should be set to false to disable the
  "automatic junk heuristic" that treats popular elements as junk. Default is true.


  ## Example

    iex> a = "abcd"
    iex> b = "bcde"
    iex> SequenceMatcher.ratio(a, b)
    0.75
  """
  def ratio(a, b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true])
    matching_blocks = get_matching_blocks(a, b, validated_opts)

    matches =
      Enum.reduce(matching_blocks, 0, fn {_, _, size}, acc ->
        acc + size
      end)

    la = get_length(a)
    lb = get_length(b)

    calculate_ratio(matches, la + lb)
  end

  @doc """
  Return an upper bound on `ratio/3` relatively quickly.

  ## Description

  This isn't defined beyond that it is an upper bound on `ratio/3`, and is faster to compute.

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.
  - opts: Keyword list of options.
    - fullbcount: Optional parameter fullbcount is a map of the counts of each element in b.
  It will be constructed if it does not exist. Default is nil.

  ## Example

    iex> a = "abcd"
    iex> b = "bcde"
    iex> SequenceMatcher.quick_ratio(a, b)
    0.75
  """
  def quick_ratio(a, b, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:fullbcount])
    fullbcount = Keyword.get(validated_opts, :fullbcount)

    # viewing a and b as multisets, set matches to the cardinality
    # of their intersection; this counts the number of matches
    # without regard to order, so is clearly an upper bound
    a_vals = get_vals(a)
    b_vals = get_vals(b)

    fullbcount =
      if is_nil(fullbcount) do
        Enum.reduce(b_vals, %{}, fn elt, acc ->
          Map.put(acc, elt, Map.get(acc, elt, 0) + 1)
        end)
      else
        fullbcount
      end

    # avail[x] is the number of times x appears in 'b' less the
    # number of times we've seen it in 'a' so far ... kinda
    %{avail: avail, matches: matches} =
      Enum.reduce(a_vals, %{matches: 0, avail: %{}}, fn elt, acc ->
        numb =
          if Map.has_key?(acc.avail, elt) do
            Map.get(acc.avail, elt)
          else
            Map.get(fullbcount, elt, 0)
          end

        next_avail = Map.put(acc.avail, elt, numb - 1)
        next_matches = if numb > 0, do: acc.matches + 1, else: acc.matches

        %{
          avail: next_avail,
          matches: next_matches
        }
      end)

    calculate_ratio(matches, length(a_vals) + length(b_vals))
  end

  @doc """
  Return an upper bound on `ratio/3` very quickly.

  ## Description
  This isn't defined beyond that it is an upper bound on `ratio/3`, and
  is faster to compute than either `ratio/3` or `quick_ratio/3`.

  ## Parameters

  - a: The first of two sequences to be compared. The elements of a must be hashable.
  - b: The second of two sequences to be compared. The elements of a must be hashable.

  ## Example

    iex> a = "abcd"
    iex> b = "bcde"
    iex> SequenceMatcher.real_quick_ratio(a, b)
    1.0
  """
  def real_quick_ratio(a, b) do
    la = get_length(a)
    lb = get_length(b)

    # can't have more matches than the number of elements in the
    # shorter sequence
    calculate_ratio(min(la, lb), la + lb)
  end

  @doc """
  Use SequenceMatcher to return list of the best "good enough" matches.

  ## Description
  The best (no more than n) matches among the possibilities are returned
  in a list, sorted by similarity score, most similar first.

  ## Parameters

  - word: The sequence for which close matches are desired. Typically a string.
  - possibilities: A list of sequences against which to match word. Typically a list of strings.
  - opts: Keyword list of options.
    - n: Optional parameter n is the maximum number of close matches to return. Default is 3 and n must be > 0.
    - cutoff: Optional parameter cutoff is a float between 0 and 1. Possibilities that don't score at least that similar to word are ignored. Default is 0.6.
    - is_junk: Optional parameter is_junk is a one-argument
    function that takes a sequence element and returns true if the
    element is junk. The default is nil which is equivalent to passing `fn _ -> false end", i.e.
    no elements are considered to be junk.  For example, pass
        `fn x -> x == " "`
    if you're comparing lines as sequences of characters, and don't
    want to synch up on blanks or hard tabs.
      - auto_junk: Optional parameter autojunk should be set to false to disable the
    "automatic junk heuristic" that treats popular elements as junk. Default is true.

  ## Example

    iex> SequenceMatcher.get_close_matches("appel", ["ape", "apple", "peach", "puppy"])
    ["apple", "ape"]
  """
  def get_close_matches(word, possibilities, opts \\ []) do
    validated_opts = Keyword.validate!(opts, [:is_junk, auto_junk: true, n: 3, cutoff: 0.6])
    n = Keyword.get(validated_opts, :n)
    cutoff = Keyword.get(validated_opts, :cutoff)
    ratio_opts = Keyword.drop(validated_opts, [:n, :cutoff])

    if n <= 0 do
      raise "n must be > 0: (#{n})"
    end

    if cutoff < 0.0 or cutoff > 1.0 do
      raise "cutoff must be in [0.0, 1.0]: (#{cutoff})"
    end

    a = word

    possibilities
    |> Enum.reduce([], fn x, acc ->
      if real_quick_ratio(a, x) >= cutoff and
           quick_ratio(a, x) >= cutoff and
           ratio(a, x, ratio_opts) >= cutoff do
        acc ++ [{ratio(a, x, ratio_opts), x}]
      else
        acc
      end
    end)
    # Move the best scorers to head of list
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.take(n)
    # Strip scores for the best n matches
    |> Enum.map(&elem(&1, 1))
  end

  defp calculate_ratio(_matches, 0), do: 1.0

  defp calculate_ratio(matches, length) do
    2.0 * matches / length
  end

  defp get_length(val) when is_binary(val), do: String.length(val)
  defp get_length(val), do: length(val)

  defp get_vals(val) when is_binary(val), do: String.graphemes(val)
  defp get_vals(val), do: val
end
