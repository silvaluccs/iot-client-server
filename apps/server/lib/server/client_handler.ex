defmodule Server.ClientHandler do
  use GenServer
  require Logger

  def start_link(socket), do: GenServer.start_link(__MODULE__, socket)

  @impl true
  def init(socket) do
    {:ok, %{socket: socket}}
  end

  @impl true
  def handle_info(:socket_ready, state) do
    :ok = :inet.setopts(state.socket, active: true, packet: :line)
    Logger.info("Client handler is ready to receive data.")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    trimmed = String.trim(data)

    if trimmed != "" do
      with {:ok, decode} <- Shared.Protocol.decode(trimmed) do
        case decode do
          %{"id" => _, "command_id" => _, "timestamp" => _} = map ->
            command = Shared.Message.Command.new(map["id"], map["command_id"], map["timestamp"])
            Logger.info("Received command: #{inspect(command)}")
            Task.start(fn -> process_command(command, socket) end)

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
    Logger.error("TCP error on socket #{inspect(socket)}: #{reason}")
    {:stop, reason, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Client disconnected: #{inspect(socket)}")
    {:stop, :normal, state}
  end

  defp process_command(command, client_socket) do
    response_message =
      case command.command_id do
        1 -> "Ping received at #{DateTime.utc_now()}"
        2 -> "Echo: #{command.id} at #{DateTime.utc_now()}"
        _ -> "Unknown command ID: #{command.command_id}"
      end

    response = Shared.Message.ClienteResponse.new(command.id, response_message)
    {:ok, json} = Shared.Protocol.encode(response)
    :gen_tcp.send(client_socket, json <> "\r\n")
  end
end

