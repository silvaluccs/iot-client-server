defmodule Client.Shell do
  @moduledoc """
  Interface de linha de comando (CLI) interativa para o cliente.

  Este módulo atua como um GenServer que gerencia a entrada do usuário pelo
  terminal e a exibição de respostas do servidor, incluindo a renderização
  de gráficos em tempo real utilizando caracteres ASCII.
  """

  require Logger
  use GenServer

  @shell_start_delay 1_000
  @eof_retry_delay 2_000

  @doc """
  Inicia o processo do Shell e o vincula à árvore de supervisão local.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_) do
    client_id = Application.get_env(:client, :client_id) || UUIDv7.generate()
    Application.put_env(:client, :client_id, client_id)

    IO.puts("Iniciando o Shell... Client ID: #{client_id}")

    # Atrasa o início do shell para permitir que outras inicializações (como a conexão TCP) ocorram primeiro
    Process.send_after(self(), :start_shell, @shell_start_delay)

    {:ok, %{client_id: client_id, active_graph: nil, timer_ref: nil}}
  end

  @impl true
  @doc false
  def handle_info(:start_shell, state) do
    parent = self()

    # Inicia uma tarefa assíncrona para ler a entrada do usuário de forma bloqueante (IO.gets)
    # sem travar o loop principal de mensagens do GenServer.
    Task.start(fn ->
      result = shell_loop(state)
      send(parent, {:shell_done, result})
    end)

    {:noreply, state}
  end

  @impl true
  @doc false
  def handle_info({:shell_done, :eof}, state) do
    IO.puts("EOF recebido antes do TTY estar pronto. Tentando novamente...")
    Process.send_after(self(), :start_shell, @eof_retry_delay)
    {:noreply, state}
  end

  @impl true
  @doc false
  def handle_info({:shell_done, :ok}, state) do
    IO.puts("Shell encerrado.")
    {:noreply, state}
  end

  @impl true
  @doc false
  def handle_info({:poll_top, sensor_id}, state) do
    # Se o gráfico deste sensor ainda estiver ativo, solicita iterativamente a atualização dos dados ao servidor
    if state.active_graph == sensor_id do
      command = Shared.Message.Command.new(state.client_id, "graph #{sensor_id}")
      Client.Connection.send_message(command)
    end

    {:noreply, state}
  end

  @doc """
  Exibe uma mensagem ou renderiza um gráfico no terminal do usuário.
  Normalmente chamado por outros processos (como a conexão TCP) ao receber dados do servidor.
  """
  def display_message(message) do
    GenServer.cast(__MODULE__, {:display_message, message})
  end

  @impl true
  @doc false
  def handle_cast({:display_message, "CHART:" <> chart_data}, state) do
    # Processa e renderiza os dados em forma de gráfico recebidos do servidor
    [sensor_id, json_history] = String.split(chart_data, ":", parts: 2)

    if state.active_graph != nil and state.active_graph != sensor_id do
      {:noreply, state}
    else
      history = Jason.decode!(json_history)

      # Limpa a tela do terminal (sequência de escape ANSI) para desenhar o novo quadro
      IO.write("\e[H\e[2J")

      if length(history) > 1 do
        {:ok, chart} = Asciichart.plot(history, height: 10)
        IO.puts(chart)
      else
        IO.puts("Aguardando mais dados para desenhar o gráfico...")
      end

      IO.puts("Monitorando Sensor: #{sensor_id} (Digite 'q' e aperte ENTER para sair)")

      # Cancela o temporizador antigo (se houver) e agenda o próximo ciclo de atualização da tela
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
      timer_ref = Process.send_after(self(), {:poll_top, sensor_id}, 1000)

      {:noreply, %{state | active_graph: sensor_id, timer_ref: timer_ref}}
    end
  end

  @impl true
  @doc false
  def handle_cast({:display_message, message}, state) do
    # Tratamento especial quando o sensor que está sendo monitorado para de responder ou é removido
    if state.active_graph != nil and String.contains?(message, "não encontrado ou inativo") do
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
      IO.puts("\n#{message}")
      IO.puts("Monitoramento encerrado automaticamente.")
      {:noreply, %{state | active_graph: nil, timer_ref: nil}}
    else
      IO.puts("#{message}")
      {:noreply, state}
    end
  end

  @impl true
  @doc false
  def handle_cast(:stop_graph, state) do
    # Cancela as requisições recorrentes (polling) de gráfico
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    IO.puts("\nSaindo do modo gráfico...")
    {:noreply, %{state | active_graph: nil, timer_ref: nil}}
  end

  @impl true
  @doc false
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Loop recursivo e interativo para leitura de comandos via entrada padrão do terminal
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
    - ls: Lista todos os sensores ativos.
    - ls actuators: Lista todos os atuadores ativos.
    - cat sensors: Lista os detalhes de todos os sensores.
    - cat <sensor_id>: Exibe os detalhes de um sensor específico.
    - cat actuators: Lista os detalhes de todos os atuadores.
    - cat actuator <actuator_id>: Exibe os detalhes de um atuador específico.
    - graph <sensor_id>: Exibe o gráfico de um sensor específico.
    - send <actuator_id> <ON/OFF>: Envia um comando para um atuador específico.
    - server status: Exibe o status e métricas de processamento do servidor.
    - slow <segundos>: Simula um comando lento para testar concorrência.
    """)

    shell_loop(state)
  end

  defp handle_input("exit", _state) do
    IO.puts("Encerrando o Shell...")
    :ok
  end

  defp handle_input("clear", state) do
    # Limpa a tela do terminal
    IO.write("\e[H\e[2J")
    shell_loop(state)
  end

  defp handle_input("q", state) do
    GenServer.cast(__MODULE__, :stop_graph)
    shell_loop(state)
  end

  defp handle_input("graph " <> _ = input, state) do
    current_state = GenServer.call(__MODULE__, :get_state)

    if current_state.active_graph != nil do
      IO.puts(
        "Um gráfico já está ativo para o sensor #{current_state.active_graph}. Digite 'q' para sair primeiro."
      )

      shell_loop(state)
    else
      command = Shared.Message.Command.new(state.client_id, input)
      Client.Connection.send_message(command)
      shell_loop(state)
    end
  end

  defp handle_input(input, state) do
    # Envia comandos arbitrários ou parseados para o servidor central por meio da conexão ativa
    command = Shared.Message.Command.new(state.client_id, input)
    Client.Connection.send_message(command)
    shell_loop(state)
  end
end
