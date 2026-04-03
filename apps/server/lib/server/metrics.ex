defmodule Server.Metrics do
  use GenServer
  require Logger

  @moduledoc """
  GenServer responsável por armazenar métricas do servidor,
  como quantidade de comandos recebidos, processados e
  estatísticas da máquina virtual do Elixir (BEAM).
  """

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{commands_received: 0, commands_processed: 0},
      name: __MODULE__
    )
  end

  def inc_received do
    GenServer.cast(__MODULE__, {:inc, :commands_received})
  end

  def inc_processed do
    GenServer.cast(__MODULE__, {:inc, :commands_processed})
  end

  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  # --- Server Callbacks ---

  @impl true
  def init(initial_state) do
    Logger.info("Server Metrics started.")
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:inc, key}, state) do
    new_state = Map.update!(state, key, &(&1 + 1))
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    memory_total_mb = Float.round(:erlang.memory(:total) / 1024 / 1024, 2)

    # Comandos que chegaram mas ainda não terminaram de processar
    in_flight = max(0, state.commands_received - state.commands_processed)

    # Contagem de clientes ativos
    client_count =
      if Process.whereis(Server.ClientSupervisor) do
        DynamicSupervisor.count_children(Server.ClientSupervisor).active
      else
        0
      end

    # Processos criados pela aplicação: ~6 (Supervisors/Managers) + Clientes + Tasks em andamento
    server_process_count = 6 + client_count + in_flight

    enhanced_metrics =
      state
      |> Map.put(:in_flight, in_flight)
      |> Map.put(:vm_processes, server_process_count)
      |> Map.put(:vm_memory_mb, memory_total_mb)

    {:reply, enhanced_metrics, state}
  end
end
