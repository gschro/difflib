defmodule Difflib.SequenceMatcherTest do
  use ExUnit.Case

  alias Difflib.SequenceMatcher

  describe "Difflib.SequenceMatcher" do
    test "get_close_matches/2" do
      assert SequenceMatcher.get_close_matches("appel", ["ape", "apple", "peach", "puppy"]) == [
               "apple",
               "ape"
             ]
    end

    test "find_longest_match/7" do
      is_junk = fn x -> x == " " end
      a = " abcd"
      b = "abcd abcd"
      m = SequenceMatcher.find_longest_match(a, b, ahi: 5, bhi: 9, is_junk: is_junk)
      assert m == {1, 0, 4}

      a = "ab"
      b = "c"
      m = SequenceMatcher.find_longest_match(a, b, ahi: 2, bhi: 1)
      assert m == {0, 0, 0}
    end

    test "get_matching_blocks/1" do
      a = "abxcd"
      b = "abcd"
      mb = SequenceMatcher.get_matching_blocks(a, b)
      assert mb == [{0, 0, 2}, {3, 2, 2}, {5, 4, 0}]

      is_junk = fn x -> x == " " end

      a = "private Thread currentThread;"
      b = "private volatile Thread currentThread;"
      mb = SequenceMatcher.get_matching_blocks(a, b, is_junk: is_junk)
      assert mb == [{0, 0, 8}, {8, 17, 21}, {29, 38, 0}]
    end

    test "get_opcodes/1" do
      a = "qabxcd"
      b = "abycdf"

      assert SequenceMatcher.get_opcodes(a, b) == [
               {:delete, 0, 1, 0, 0},
               {:equal, 1, 3, 0, 2},
               {:replace, 3, 4, 2, 3},
               {:equal, 4, 6, 3, 5},
               {:insert, 6, 6, 5, 6}
             ]

      is_junk = fn x -> x == " " end

      a = "private Thread currentThread;"
      b = "private volatile Thread currentThread;"

      assert SequenceMatcher.get_opcodes(a, b, is_junk: is_junk) == [
               {:equal, 0, 8, 0, 8},
               {:insert, 8, 8, 8, 17},
               {:equal, 8, 29, 17, 38}
             ]
    end

    test "get_grouped_op_codes/1" do
      a = Enum.map(1..39, &Integer.to_string/1)
      b = Enum.slice(a, 0..-1//1)
      b = Enum.slice(b, 0..7) ++ ["i"] ++ Enum.slice(b, 8..-1//1)
      b = Enum.slice(b, 0..19) ++ ["20x"] ++ Enum.slice(b, 21..-1//1)
      b = Enum.slice(b, 0..22) ++ Enum.slice(b, 28..-1//1)
      b = Enum.slice(b, 0..29) ++ ["35y"] ++ Enum.slice(b, 31..-1//1)

      assert SequenceMatcher.get_grouped_opcodes(a, b) == [
               [
                 {:equal, 5, 8, 5, 8},
                 {:insert, 8, 8, 8, 9},
                 {:equal, 8, 11, 9, 12}
               ],
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
    end

    test "ratio/1" do
      a = "abcd"
      b = "bcde"
      assert SequenceMatcher.ratio(a, b) == 0.75

      is_junk = fn x -> x == " " end
      a = "private Thread currentThread;"
      b = "private volatile Thread currentThread;"

      assert SequenceMatcher.ratio(a, b, is_junk: is_junk) == 0.8656716417910447
    end

    test "quick_ratio/1" do
      a = "abcd"
      b = "bcde"
      assert SequenceMatcher.quick_ratio(a, b) == 0.75
    end

    test "real_quick_ratio/1" do
      a = "abcd"
      b = "bcde"
      assert SequenceMatcher.real_quick_ratio(a, b) == 1.0
    end

    test "test_one_insert" do
      a = String.duplicate("b", 100)
      b = "a" <> String.duplicate("b", 100)

      assert SequenceMatcher.ratio(a, b) == 0.9950248756218906

      assert SequenceMatcher.get_opcodes(a, b) == [
               {:insert, 0, 0, 0, 1},
               {:equal, 0, 100, 1, 101}
             ]

      a = String.duplicate("b", 100)
      b = String.duplicate("b", 50) <> "a" <> String.duplicate("b", 50)

      assert SequenceMatcher.ratio(a, b) == 0.9950248756218906

      assert SequenceMatcher.get_opcodes(a, b) == [
               {:equal, 0, 50, 0, 50},
               {:insert, 50, 50, 50, 51},
               {:equal, 50, 100, 51, 101}
             ]

      assert SequenceMatcher.chain_b(b) |> Map.get(:bpopular) == %{}
    end

    test "test_one_delete" do
      a = String.duplicate("a", 40) <> "c" <> String.duplicate("b", 40)
      b = String.duplicate("a", 40) <> String.duplicate("b", 40)

      assert SequenceMatcher.ratio(a, b) == 0.9937888198757764

      assert SequenceMatcher.get_opcodes(a, b) == [
               {:equal, 0, 40, 0, 40},
               {:delete, 40, 41, 40, 40},
               {:equal, 41, 81, 40, 80}
             ]
    end

    test "test_one_replace" do
      a = "ab" <> String.duplicate("x", 40) <> "cd"
      b = "ab" <> String.duplicate("y", 40) <> "cd"

      assert SequenceMatcher.ratio(a, b) == 0.09090909090909091

      assert SequenceMatcher.get_opcodes(a, b) == [
               {:equal, 0, 2, 0, 2},
               {:replace, 2, 42, 2, 42},
               {:equal, 42, 44, 42, 44}
             ]
    end

    test "test_bjunk" do
      is_junk = fn x -> x == " " end
      b = String.duplicate("a", 44) <> String.duplicate("b", 40)
      assert SequenceMatcher.chain_b(b, is_junk: is_junk) |> Map.get(:bjunk) == %{}

      b = String.duplicate("a", 44) <> String.duplicate("b", 40) <> String.duplicate(" ", 20)
      assert SequenceMatcher.chain_b(b, is_junk: is_junk) |> Map.get(:bjunk) == %{" " => true}

      is_junk = fn x -> x in [" ", "b"] end
      b = String.duplicate("a", 44) <> String.duplicate("b", 40) <> String.duplicate(" ", 20)

      assert SequenceMatcher.chain_b(b, is_junk: is_junk) |> Map.get(:bjunk) == %{
               " " => true,
               "b" => true
             }
    end

    test "test_one_insert_homogenous_sequence" do
      a = String.duplicate("b", 200)
      b = "a" <> String.duplicate("b", 200)
      assert SequenceMatcher.ratio(a, b) == 0.0
      assert SequenceMatcher.chain_b(b) |> Map.get(:bpopular) == %{"b" => true}

      a = String.duplicate("b", 200)
      b = "a" <> String.duplicate("b", 200)
      assert SequenceMatcher.ratio(a, b, auto_junk: false) == 0.9975062344139651
      assert SequenceMatcher.chain_b(b, auto_junk: false) |> Map.get(:bpopular) == %{}
    end

    test "test_ratio_for_null_seqn" do
      a = []
      b = []
      assert SequenceMatcher.ratio(a, b) == 1.0
      assert SequenceMatcher.quick_ratio(a, b) == 1.0
      assert SequenceMatcher.real_quick_ratio(a, b) == 1.0
    end
  end
end
