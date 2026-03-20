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
    with {:ok, decode} <- Shared.Protocol.decode(data) do
      case decode do
        %{"pid" => _, "command_id" => _, "timestamp" => _} = map ->
          command = Shared.Message.Command.new(map["pid"], map["command_id"], map["timestamp"])

          Logger.info("Received command: #{inspect(command)}")

          # WARN: This is a very basic way to handle commands and may not be suitable for production use.
          Task.start(fn -> process_command(command, socket) end)

        _ ->
          Logger.error("Received unknown message format: #{inspect(decode)}")
      end
    else
      {:error, reason} ->
        Logger.error("Failed to decode message: #{reason}")
    end

    {:noreply, state}
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("TCP error on socket #{inspect(socket)}: #{reason}")
    {:stop, reason, state}
  end

  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Client disconnected: #{inspect(socket)}")
    {:stop, :normal, state}
  end

  defp process_command(command, client_socket) do
    # TODO: Implement actual command processing logic here
    response_message =
      case command.command_id do
        1 -> "Ping received at #{DateTime.utc_now()}"
        2 -> "Echo: #{command.pid} at #{DateTime.utc_now()}"
        _ -> "Unknown command ID: #{command.command_id}"
      end

    response =
      Shared.Message.ClienteResponse.new(command.pid, response_message, DateTime.utc_now())

    {:ok, json} = Shared.Protocol.encode(response)
    :gen_tcp.send(client_socket, json <> "\r\n")
  end
end
