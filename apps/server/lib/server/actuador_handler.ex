defmodule Server.ActuatorHandler do
  require Logger
  use GenServer

  def start_link(client_socket), do: GenServer.start_link(__MODULE__, client_socket)

  @impl true
  def init(client_socket) do
    {:ok, %{socket: client_socket}}
  end

  @impl true
  def handle_info(:socket_ready, state) do
    :ok = :inet.setopts(state.socket, active: true, packet: :line)
    Logger.info("Actuator handler is ready to receive data.")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    trimmed = String.trim(data)

    if trimmed != "" do
      with {:ok, decode} <- Shared.Protocol.decode(trimmed) do
        case decode do
          %{"id" => id, "name" => actuador_name, "active" => active, "timestamp" => ts} ->
            Server.ActuadorManager.update_actuator(
              id,
              %{id: id, socket: socket, name: actuador_name, active: active, last_seen: ts}
            )

          %{
            "id" => id,
            "name" => actuador_name,
            "command_executed" => command_executed,
            "active" => active,
            "timestamp" => ts
          } ->
            Server.ActuadorManager.update_actuator(
              id,
              %{
                id: id,
                socket: socket,
                name: actuador_name,
                last_command_executed: command_executed,
                active: active,
                last_seen: ts
              }
            )

          _ ->
            Logger.error("Received unknown message format: #{inspect(decode)}")
        end
      else
        {:error, reason} ->
          Logger.error("Failed to decode message: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("TCP error on actuator socket #{inspect(socket)}: #{reason}")
    {:stop, reason, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Actuator disconnected: #{inspect(socket)}")
    {:stop, :normal, state}
  end
end
