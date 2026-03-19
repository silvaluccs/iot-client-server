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

          response =
            Shared.Message.ClienteResponse.new(
              command.pid,
              "Command received",
              DateTime.utc_now()
            )

          case Jason.encode(response) do
            {:ok, json_response} ->
              Logger.info("Sending response: #{json_response}")
              :gen_tcp.send(socket, json_response <> "\r\n")

            {:error, reason} ->
              Logger.error("Failed to encode response: #{reason}")
          end

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
end
