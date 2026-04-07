defmodule Server.UdpServer do
  require Logger
  use GenServer, restart: :permanent

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port \\ 5000) do
    Logger.info("Starting UDP server on port #{port}...")

    case :gen_udp.open(port, [:binary, active: :once, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("UDP server started on port #{port}")
        {:ok, %{socket: socket}}

      {:error, reason} ->
        Logger.error("Failed to start UDP server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    with {:ok, message} <- Shared.Protocol.decode(data) do
      case message do
        %{"id" => id, "type" => type, "value" => value, "timestamp" => timestamp} ->
          Server.SensorManager.update_sensor(id, %{
            type: type,
            value: value,
            timestamp: timestamp,
            active: true
          })

        _ ->
          Logger.warning("Received UDP payload with unknown format: #{inspect(message)}")
      end
    else
      {:error, reason} ->
        Logger.error("Failed to decode message: #{inspect(reason)}")
    end

    :inet.setopts(state.socket, active: :once)
    {:noreply, state}
  end
end
