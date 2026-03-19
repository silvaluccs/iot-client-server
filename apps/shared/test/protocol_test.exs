defmodule ProtocolTest do
  use ExUnit.Case, async: true

  test "Encode map para um formato JSON" do
    data = %{name: "Alice", age: 30}
    assert Shared.Protocol.encode(data) == {:ok, "{\"name\":\"Alice\",\"age\":30}"}
  end

  test "Encode uma lista de mapas para um formato JSON" do
    data = [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]

    assert Shared.Protocol.encode(data) ==
             {:ok, "[{\"name\":\"Alice\",\"age\":30},{\"name\":\"Bob\",\"age\":25}]"}
  end

  test "Decode uma string JSON para um mapa" do
    json_string = "{\"name\":\"Alice\",\"age\":30}"
    assert Shared.Protocol.decode(json_string) == {:ok, %{"name" => "Alice", "age" => 30}}
  end
end
