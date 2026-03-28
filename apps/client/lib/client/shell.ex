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
    client_id = Application.get_env(:client, :client_id) || UUIDv7.generate()
    Application.put_env(:client, :client_id, client_id)

    IO.puts("Iniciando o Shell... Client ID: #{client_id}")
    Process.send_after(self(), :start_shell, @shell_start_delay)

    {:ok, %{client_id: client_id, active_graph: nil}}
  end

  @impl true
  def handle_info(:start_shell, state) do
    parent = self()

    Task.start(fn ->
      result = shell_loop(state)
      send(parent, {:shell_done, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:shell_done, :eof}, state) do
    IO.puts("EOF recebido antes do TTY estar pronto. Tentando novamente...")
    Process.send_after(self(), :start_shell, @eof_retry_delay)
    {:noreply, state}
  end

  @impl true
  def handle_info({:shell_done, :ok}, state) do
    IO.puts("Shell encerrado.")
    {:noreply, state}
  end

  @impl true
  def handle_info({:poll_top, sensor_id}, state) do
    if state.active_graph == sensor_id do
      command = Shared.Message.Command.new(state.client_id, "graph #{sensor_id}")
      Client.Connection.send_message(command)
    end

    {:noreply, state}
  end

  def display_message(message) do
    GenServer.cast(__MODULE__, {:display_message, message})
  end

  @impl true
  def handle_cast({:display_message, "CHART:" <> chart_data}, state) do
    [sensor_id, json_history] = String.split(chart_data, ":", parts: 2)
    history = Jason.decode!(json_history)

    IO.write("\e[H\e[2J")

    if length(history) > 1 do
      {:ok, chart} = Asciichart.plot(history, height: 10)
      IO.puts(chart)
    else
      IO.puts("Aguardando mais dados para desenhar o gráfico...")
    end

    IO.puts("Monitorando Sensor: #{sensor_id} (Digite 'q' e aperte ENTER para sair)")

    Process.send_after(self(), {:poll_top, sensor_id}, 1000)

    {:noreply, %{state | active_graph: sensor_id}}
  end

  @impl true
  def handle_cast({:display_message, message}, state) do
    IO.puts("#{message}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop_graph, state) do
    IO.puts("\nSaindo do modo gráfico...")
    {:noreply, %{state | active_graph: nil}}
  end

  defp shell_loop(state) do
    case IO.gets("> ") do
      {:error, _reason} ->
        :ok

      :eof ->
        IO.puts("EOF recebido.")
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
    - q: Sai do modo de monitoramento gráfico.
    - qualquer número será enviado ao servidor como comando.
    """)

    shell_loop(state)
  end

  defp handle_input("exit", _state) do
    IO.puts("Encerrando o Shell...")
    :ok
  end

  defp handle_input("clear", state) do
    IO.write("\e[H\e[2J")
    shell_loop(state)
  end

  defp handle_input("q", state) do
    GenServer.cast(__MODULE__, :stop_graph)
    shell_loop(state)
  end

  defp handle_input(input, state) do
    if state.active_graph != nil do
      IO.puts("\nSaindo do modo gráfico...")
    end

    command = Shared.Message.Command.new(state.client_id, input)
    Client.Connection.send_message(command)
    shell_loop(state)
  end
end
