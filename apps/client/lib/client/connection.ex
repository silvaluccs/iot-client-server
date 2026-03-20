defmodule Client.Connection do
  use GenServer
  require Logger

  @server_address ~c"localhost"
  @port 4000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Starting connection to server...")

    {:ok, socket} =
      :gen_tcp.connect(@server_address, @port, [
        :binary,
        packet: :line,
        active: true,
        reuseaddr: true
      ])

    Logger.info("Connected to server in port #{@port}")
    {:ok, %{socket: socket}}
  end

  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_command, message})
  end

  @impl true
  def handle_cast({:send_command, message}, state) do
    {:ok, json} = Shared.Protocol.encode(message)

    case :gen_tcp.send(state.socket, json <> "\r\n") do
      :ok ->
        Logger.info("Sent message: #{inspect(message)}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to send message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    Logger.info("Received data: #{data}")
    IO.puts("Received data: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    message = "TCP connection error. #{inspect(reason)}"
    IO.puts(message)
    Logger.error(message)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    message = "TCP connection closed by server."
    IO.puts(message)
    Logger.warning(message)
    {:stop, :normal, state}
  end
end
