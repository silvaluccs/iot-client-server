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

        spawn(fn -> handle_client(client_socket) end)
        send(self(), :accept)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to accept client connection: #{reason}")
        {:noreply, state}
    end
  end

  defp handle_client(client_socket) do
    case :gen_tcp.recv(client_socket, 0) do
      {:ok, data} ->
        Logger.info("Received data from client: #{data}")
        :gen_tcp.send(client_socket, "Echo: #{data}")
        handle_client(client_socket)

      {:error, reason} ->
        Logger.error("Failed to receive data from client: #{reason}")
    end
  end
end

