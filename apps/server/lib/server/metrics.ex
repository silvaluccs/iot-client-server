defmodule Server.Metrics do
  @moduledoc """
  GenServer responsável por rastrear e fornecer métricas de saúde e
  desempenho do servidor.

  Ele contabiliza a quantidade de comandos recebidos e processados,
  calcula a quantidade de comandos "em voo" (in-flight) e fornece
  estatísticas de uso de recursos da máquina virtual Elixir (BEAM),
  como alocação de memória e número de processos ativos.
  """

  use GenServer
  require Logger

  @doc """
  Inicia o processo de métricas com os contadores zerados e o vincula
  à árvore de supervisão local.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{commands_received: 0, commands_processed: 0},
      name: __MODULE__
    )
  end

  @doc """
  Incrementa assincronamente o contador global de comandos recebidos.
  """
  def inc_received do
    GenServer.cast(__MODULE__, {:inc, :commands_received})
  end

  @doc """
  Incrementa assincronamente o contador global de comandos processados.
  Deve ser chamado apenas após a conclusão bem-sucedida do trabalho.
  """
  def inc_processed do
    GenServer.cast(__MODULE__, {:inc, :commands_processed})
  end

  @doc """
  Sincronamente solicita e consolida o estado atual das métricas da aplicação,
  agregando dados internos (contadores) com informações externas (BEAM e Supervisor).
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  # --- Server Callbacks ---

  @impl true
  @doc false
  def init(initial_state) do
    Logger.info("Métricas do Servidor iniciadas.")
    {:ok, initial_state}
  end

  @impl true
  @doc false
  def handle_cast({:inc, key}, state) do
    # Atualiza o contador especificado pela chave incrementando seu valor em 1
    new_state = Map.update!(state, key, &(&1 + 1))
    {:noreply, new_state}
  end

  @impl true
  @doc false
  def handle_call(:get_metrics, _from, state) do
    # Calcula a memória total alocada pela máquina virtual Erlang em Megabytes
    memory_total_mb = Float.round(:erlang.memory(:total) / 1024 / 1024, 2)

    # Comandos que chegaram mas ainda não terminaram de processar
    in_flight = max(0, state.commands_received - state.commands_processed)

    # Contagem de clientes ativos verificando os filhos no supervisor dinâmico de clientes
    client_count =
      if Process.whereis(Server.ClientSupervisor) do
        DynamicSupervisor.count_children(Server.ClientSupervisor).active
      else
        0
      end

    # Processos criados pela aplicação: ~6 (Supervisors/Managers básicos) + Clientes + Tasks em andamento
    server_process_count = 6 + client_count + in_flight

    # Enriquece o mapa de estado com os cálculos dinâmicos realizados sob demanda
    enhanced_metrics =
      state
      |> Map.put(:in_flight, in_flight)
      |> Map.put(:vm_processes, server_process_count)
      |> Map.put(:vm_memory_mb, memory_total_mb)

    {:reply, enhanced_metrics, state}
  end
end
