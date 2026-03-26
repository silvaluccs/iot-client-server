defmodule Client.Shell do
  require Logger
  use GenServer

  @shell_start_delay 1_000
  @eof_retry_delay 2_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    client_id = UUIDv7.generate()
    IO.puts("Iniciando o Shell... Client ID: #{client_id}")
    Process.send_after(self(), :start_shell, @shell_start_delay)
    {:ok, %{client_id: client_id}}
  end

  @impl true
  def handle_info(:start_shell, state) do
    # Roda o shell numa Task; quando terminar, notifica o GenServer
    parent = self()

    Task.start(fn ->
      result = shell_loop(state)
      send(parent, {:shell_done, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:shell_done, :eof}, state) do
    # TTY ainda não estava pronto, tenta novamente
    IO.puts("EOF recebido antes do TTY estar pronto. Tentando novamente...")
    Process.send_after(self(), :start_shell, @eof_retry_delay)
    {:noreply, state}
  end

  def handle_info({:shell_done, :ok}, state) do
    IO.puts("Shell encerrado.")
    {:noreply, state}
  end

  def display_message(message) do
    GenServer.cast(__MODULE__, {:display_message, message})
  end

  @impl true
  def handle_cast({:display_message, message}, state) do
    IO.puts("Mensagem do servidor: #{inspect(message)}")
    {:noreply, state}
  end

  defp shell_loop(state) do
    case IO.gets("> ") do
      {:error, _reason} ->
        :ok

      :eof ->
        IO.puts("EOF recebido.")
        # <-- retorna :eof para o GenServer decidir o que fazer
        :eof

      input when is_binary(input) ->
        input
        |> String.trim()
        |> handle_input(state)
    end
  end

  defp handle_input("", state), do: shell_loop(state)

  defp handle_input("help", state) do
    IO.puts("""
    Comandos disponíveis:
    - help: Exibe esta mensagem de ajuda.
    - exit: Encerra o shell.
    - qualquer número será enviado ao servidor como comando.
    """)

    shell_loop(state)
  end

  defp handle_input("exit", _state) do
    IO.puts("Encerrando o Shell...")
    :ok
  end

  defp handle_input(input, state) do
    case Integer.parse(input) do
      {command_id, ""} ->
        command = Shared.Message.Command.new(state.client_id, command_id)
        Client.Connection.send_message(command)
        shell_loop(state)

      _ ->
        IO.puts("Comando desconhecido: #{inspect(input)}. Digite 'help' para ver os comandos.")

        shell_loop(state)
    end
  end
end
