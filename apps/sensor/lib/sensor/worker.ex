defmodule Sensor.Worker do
  require Logger
  use GenServer

  @server_address {127, 0, 0, 1}
  @port 5000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Starting connection to server...")

    case :gen_udp.open(0, [:binary, active: true]) do
      {:ok, socket} ->
        type_sensor = Enum.random(["temperature", "humidity", "pressure"])

        sensor_id = UUIDv7.generate()

        Logger.info("Connected to server on port #{@port}")

        scheudule_send()

        {:ok,
         %{
           socket: socket,
           type: type_sensor,
           server_address: @server_address,
           id: sensor_id,
           port: @port
         }}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:send_data, state) do
    value =
      case state.type do
        "temperature" -> Enum.random(15..30)
        "humidity" -> Enum.random(30..70)
        "pressure" -> Enum.random(980..1050)
      end

    message = Shared.Message.SensorData.new(state.id, state.type, value)

    {:ok, json} = Shared.Protocol.encode(message)

    :gen_udp.send(state.socket, state.server_address, state.port, json)

    scheudule_send()
    {:noreply, state}
  end

  defp scheudule_send(), do: Process.send_after(self(), :send_data, 1)
end
