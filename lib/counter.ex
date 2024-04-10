defmodule Counter do
  defmacro counter(counter_names) do
    for {counter_name, i} <- Enum.with_index(counter_names) do
      index = i + 1

      quote do
        defp unquote(counter_name)(ref), do: :counters.get(ref, unquote(index))
        defp unquote(:"inc_#{counter_name}")(ref), do: :counters.add(ref, unquote(index), 1)
        defp unquote(:"dec_#{counter_name}")(ref), do: :counters.sub(ref, unquote(index), 1)

        defp unquote(:"set_#{counter_name}")(ref, value),
          do: :counters.put(ref, unquote(index), value)
      end
    end
  end
end
