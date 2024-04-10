# Credit to https://github.com/dominicletz/while/tree/master
# didn't want to take on the dependancy for a 25 lines of code
defmodule While do
  @moduledoc false

  defmacro while(condition, do: block) do
    quote do
      while_impl(fn -> unquote(condition) end, fn -> unquote(block) end)
    end
  end

  def while_impl(condition, body) do
    if condition.() do
      body.()
      while_impl(condition, body)
    end
  end

  def reduce_while(acc, fun) do
    case fun.(acc) do
      {:halt, new} -> new
      {:cont, new} -> reduce_while(new, fun)
    end
  end
end
