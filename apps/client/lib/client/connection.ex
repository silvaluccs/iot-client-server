defmodule Client.Connection do
  @moduledoc """
  Gerencia a conexão TCP persistente entre o cliente e o servidor central.

  Este processo GenServer é responsável por iniciar a conexão (com suporte a retentativas),
  registrar a identidade única do cliente e atuar como a interface principal para envio
  e recebimento de comandos/mensagens de forma assíncrona.
  """

  use GenServer
  require Logger

  @doc """
  Inicia o processo de conexão e o vincula à árvore de supervisão local.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_) do
    IO.puts("Conectando ao servidor...")

    server_address =
      System.get_env("SERVER_IP", System.get_env("SERVER_HOST", "localhost"))
      |> String.to_charlist()

    port = System.get_env("SERVER_PORT", "4000") |> String.to_integer()

    socket = connect_with_retry(server_address, port)

    client_id = Application.get_env(:client, :client_id) || UUIDv7.generate()
    Application.put_env(:client, :client_id, client_id)

    registration = Shared.Message.ClientRegistration.new(client_id)
    {:ok, json} = Shared.Protocol.encode(registration)
    :gen_tcp.send(socket, json <> "\r\n")

    {:ok, %{socket: socket}}
  end

  @doc """
  Envia um comando ou mensagem genérica para o servidor de forma assíncrona.
  """
  def send_message(message) do
    GenServer.cast(__MODULE__, {:send_command, message})
  end

  @impl true
  @doc false
  def handle_cast({:send_command, message}, state) do
    {:ok, json} = Shared.Protocol.encode(message)

    :gen_tcp.send(state.socket, json <> "\r\n")

    {:noreply, state}
  end

  @impl true
  @doc false
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

  defp connect_with_retry(server_address, port) do
    case :gen_tcp.connect(server_address, port, [
           :binary,
           packet: :line,
           active: true,
           reuseaddr: true
         ]) do
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
