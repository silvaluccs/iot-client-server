defmodule Server.TcpServer do
  require Logger

  use GenServer, restart: :temporary

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("TCP server started on port #{port}")

        send(self(), :accept)

        {:ok, %{socket: socket}}

      {:error, reason} ->
        Logger.error("Failed to start TCP server: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.socket) do
      {:ok, client_socket} ->
        Logger.info("Client connected: #{inspect(client_socket)}")
        {:ok, pid} = Server.ClientSupervisor.start_child(client_socket)
        Logger.info("Started client handler with PID: #{inspect(pid)}")

        :gen_tcp.controlling_process(client_socket, pid)

        send(pid, :socket_ready)
        send(self(), :accept)

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to accept client connection: #{reason}")
        {:noreply, state}
    end
  end
end
