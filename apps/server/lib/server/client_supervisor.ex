defmodule Server.ClientSupervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_child(socket) do
    spec = {Server.ClientHandler, socket}
    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, spec)
    {:ok, pid}
  end
end
