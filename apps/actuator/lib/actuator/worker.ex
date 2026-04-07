defmodule Actuator.Worker do
  use GenServer
  require Logger

  @interval_send_state 50000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Actuator is starting...")

    server_host = System.get_env("SERVER_IP", System.get_env("SERVER_HOST", "127.0.0.1"))

    server_port =
      System.get_env("SERVER_PORT", Integer.to_string(4000))
      |> String.to_integer()

    case :gen_tcp.connect(parse_server_host(server_host), server_port, [:binary, active: true]) do
      {:ok, socket} ->
        id = UUIDv7.generate()

        type = Enum.random(["Estação", "Lâmpada", "Caixa"])

        Logger.info("Actuator #{id} connected to server at #{server_host}:#{server_port}")

        registration = Shared.Message.ActuatorRegistration.new(id, type, false)

        {:ok, json} = Shared.Protocol.encode(registration)

        :gen_tcp.send(socket, json <> "\r\n")

        send_current_state_after_each_interval()

        {:ok, %{socket: socket, id: id, type: type, active: false, last_command_executed: nil}}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp send_current_state_after_each_interval do
    Process.send_after(self(), :send_current_state, @interval_send_state)
  end

  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_message, message})
  end

  @impl true
  def handle_cast({:send_message, message}, state) do
    {:ok, json} = Shared.Protocol.encode(message)
    :gen_tcp.send(state.socket, json <> "\r\n")
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_current_state, state) do
    message = %{
      id: state.id,
      name: state.type,
      command_executed: state.last_command_executed,
      active: state.active,
      timestamp: Shared.Message.timestamp()
    }

    GenServer.cast(self(), {:send_message, message})
    send_current_state_after_each_interval()

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    data = String.trim(data)
    Logger.info("Received data: #{inspect(data)}")

    new_state =
      with {:ok, message} <- Shared.Protocol.decode(data) do
        case message do
          %{"id" => _id, "command" => command, "timestamp" => _timestamps} ->
            Logger.info("Received command: #{inspect(command)}")

            process_command(command, state)

          _ ->
            Logger.error("Unexpected message: #{inspect(message)}")
            state
        end
      else
        {:error, reason} ->
          Logger.error("Failed to decode message: #{inspect(reason)}")
          state
      end

    message = %{
      id: new_state.id,
      name: new_state.type,
      command_executed: new_state.last_command_executed,
      active: new_state.active,
      timestamp: Shared.Message.timestamp()
    }

    GenServer.cast(self(), {:send_message, message})

    {:noreply, new_state}
  end

  defp process_command("ON", state) do
    Logger.info("Executing command: ON")
    %{state | active: true, last_command_executed: "ON"}
  end

  defp process_command("OFF", state) do
    Logger.info("Executing command: OFF")
    %{state | active: false, last_command_executed: "OFF"}
  end

  defp process_command(unknown_command, state) do
    Logger.warning("Unknown command received: #{unknown_command}")
    state
  end

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
              :inet.parse_address(String.to_charlist("127.0.0.1"))

            ip
        end
    end
  end
end
