defmodule Shared.Protocol do
  def encode(data) do
    Jason.encode(data)
  end

  def decode(data) do
    Jason.decode(data)
  end
end
