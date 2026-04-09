defmodule Actuator.Worker do
  @moduledoc """
  Um processo GenServer que representa um dispositivo atuador IoT.

  Este módulo é responsável por:
  - Estabelecer uma conexão TCP com o servidor central.
  - Registrar-se com um identificador único (UUIDv7) e um tipo aleatório (Estação, Lâmpada ou Caixa).
  - Enviar seu estado atual periodicamente ao servidor.
  - Receber e processar comandos remotos (como "ON" e "OFF") para alterar seu estado.
  """

  use GenServer
  require Logger

  @interval_send_state 50000

  @doc """
  Inicia o processo do atuador e o vincula à árvore de supervisão.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_) do
    Logger.info("Actuator is starting...")

    server_host = System.get_env("SERVER_IP", System.get_env("SERVER_HOST", "127.0.0.1"))

    server_port =
      System.get_env("SERVER_PORT", Integer.to_string(4000))
      |> String.to_integer()

    socket = connect_with_retry(parse_server_host(server_host), server_port)

    id = UUIDv7.generate()

    type = Enum.random(["Estação", "Lâmpada", "Caixa"])

    Logger.info("Actuator #{id} connected to server at #{server_host}:#{server_port}")

    registration = Shared.Message.ActuatorRegistration.new(id, type, false)

    {:ok, json} = Shared.Protocol.encode(registration)

    :gen_tcp.send(socket, json <> "\r\n")

    send_current_state_after_each_interval()

    {:ok, %{socket: socket, id: id, type: type, active: false, last_command_executed: nil}}
  end

  defp send_current_state_after_each_interval do
    Process.send_after(self(), :send_current_state, @interval_send_state)
  end

  @doc """
  Envia uma mensagem assíncrona para o servidor através da conexão TCP existente.
  """
  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_message, message})
  end

  @impl true
  @doc false
  def handle_cast({:send_message, message}, state) do
    {:ok, json} = Shared.Protocol.encode(message)
    :gen_tcp.send(state.socket, json <> "\r\n")
    {:noreply, state}
  end

  @impl true
  @doc false
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
  @doc false
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

  @impl true
  @doc false
  def handle_info({:tcp_error, _socket, reason}, state) do
    message = "Erro na conexão TCP. #{inspect(reason)}"
    IO.puts(message)
    {:stop, :normal, state}
  end

  @impl true
  @doc false
  def handle_info({:tcp_closed, _socket}, state) do
    message = "A conexão com o servidor foi fechada."
    IO.puts(message)
    {:stop, :normal, state}
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

  defp connect_with_retry(server_address, port) do
    case :gen_tcp.connect(server_address, port, [:binary, active: true]) do
      {:ok, socket} ->
        socket

      {:error, reason} ->
        Logger.warning(
          "Falha ao conectar: #{inspect(reason)}. Tentando novamente em 2 segundos..."
        )

        :timer.sleep(2000)
        connect_with_retry(server_address, port)
    end
  end
end
