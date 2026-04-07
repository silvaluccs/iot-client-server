defmodule Sensor.Worker do
  require Logger
  use GenServer

  @default_server_host "127.0.0.1"
  @default_port 5000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Starting connection to server...")

    server_host = System.get_env("SERVER_IP", System.get_env("SERVER_HOST", @default_server_host))

    server_port =
      System.get_env("SERVER_PORT", Integer.to_string(@default_port))
      |> String.to_integer()

    server_address = parse_server_host(server_host)

    case :gen_udp.open(0, [:binary, active: true]) do
      {:ok, socket} ->
        type_sensor = Enum.random(["Temperatura", "Umidade", "Pressão"])

        sensor_id = UUIDv7.generate()

        Logger.info(
          "Sensor #{sensor_id} with type #{type_sensor} Connected to server at #{server_host}:#{server_port}"
        )

        scheudule_send()

        {:ok,
         %{
           socket: socket,
           type: type_sensor,
           server_address: server_address,
           id: sensor_id,
           port: server_port
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
        "Temperatura" -> Enum.random(15..30)
        "Umidade" -> Enum.random(30..70)
        "Pressão" -> Enum.random(980..1050)
      end

    message = Shared.Message.SensorData.new(state.id, state.type, value)

    {:ok, json} = Shared.Protocol.encode(message)

    :gen_udp.send(state.socket, state.server_address, state.port, json)

    scheudule_send()
    {:noreply, state}
  end

  defp scheudule_send(), do: Process.send_after(self(), :send_data, 1)

  defp parse_server_host(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, ip} ->
        ip

      {:error, _} ->
        case :inet.getaddr(charlist, :inet) do
          {:ok, ip} ->
            ip

          {:error, _} ->
            {:ok, ip} =
              :inet.parse_address(String.to_charlist(@default_server_host))

            ip
        end
    end
  end
end
