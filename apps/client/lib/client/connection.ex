defmodule Client.Connection do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    IO.puts("Conectando ao servidor...")

    server_address =
      System.get_env("SERVER_IP", System.get_env("SERVER_HOST", "localhost"))
      |> String.to_charlist()

    port = System.get_env("SERVER_PORT", "4000") |> String.to_integer()

    {:ok, socket} =
      :gen_tcp.connect(server_address, port, [
        :binary,
        packet: :line,
        active: true,
        reuseaddr: true
      ])

    client_id = Application.get_env(:client, :client_id) || UUIDv7.generate()
    Application.put_env(:client, :client_id, client_id)

    registration = Shared.Message.ClientRegistration.new(client_id)
    {:ok, json} = Shared.Protocol.encode(registration)
    :gen_tcp.send(socket, json <> "\r\n")

    {:ok, %{socket: socket}}
  end

  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_command, message})
  end

  @impl true
  def handle_cast({:send_command, message}, state) do
    {:ok, json} = Shared.Protocol.encode(message)

    :gen_tcp.send(state.socket, json <> "\r\n")

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    data = String.trim(data)

    case Shared.Protocol.decode(data) do
      {:ok, %{"client_id" => _, "message" => message, "timestamp" => _}} ->
        Client.Shell.display_message(message)

      {:error, reason} ->
        IO.puts(
          "A mensagem recebida do servidor não pôde ser processada. Verifique os logs para mais detalhes. #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    message = "Erro na conexão TCP. #{inspect(reason)}"
    IO.puts(message)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    message = "A conexão com o servidor foi fechada."
    IO.puts(message)
    {:stop, :normal, state}
  end
end
