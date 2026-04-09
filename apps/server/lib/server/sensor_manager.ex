defmodule Server.SensorManager do
  @moduledoc """
  Gerenciador central do estado e histórico dos sensores conectados.

  Este GenServer mantém um mapa em memória contendo as últimas leituras de todos
  os sensores, bem como um histórico recente (até 50 leituras) para fins de plotagem
  de gráficos. Ele também executa varreduras periódicas para marcar sensores
  ausentes como inativos e, posteriormente, removê-los da memória para evitar
  vazamentos (memory leaks).
  """

  use GenServer

  # Intervalo de 60 segundos para checar se o sensor ainda está ativo
  @active_interval 60000
  # Intervalo de 120 segundos de inatividade para remoção definitiva do sensor
  @inactive_interval 120_000

  @doc """
  Inicia o gerenciador de sensores vinculando-o à árvore de supervisão.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_) do
    # Inicia imediatamente os ciclos contínuos de verificação de status (ativo/inativo)
    schedule_actives()
    schedule_remove_inactives()

    {:ok, %{}}
  end

  @doc """
  Atualiza ou insere as informações de um sensor no estado global.
  A operação é assíncrona (fire-and-forget).
  """
  def update_sensor(sensor_id, data) do
    GenServer.cast(__MODULE__, {:update, sensor_id, data})
  end

  @doc """
  Retorna um mapa contendo os dados e históricos de todos os sensores conhecidos
  (incluindo os inativos que ainda não foram removidos).
  """
  def get_all_data do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  Retorna os dados detalhados (incluindo histórico) de um sensor específico.
  """
  def get_sensor_data(sensor_id) do
    GenServer.call(__MODULE__, {:get_one, sensor_id})
  end

  @doc """
  Remove explicitamente e assincronamente um sensor do registro.
  """
  def remove_sensor(sensor_id) do
    GenServer.cast(__MODULE__, {:remove, sensor_id})
  end

  @doc false
  def schedule_actives() do
    Process.send_after(self(), :check_actives, @active_interval)
  end

  @doc false
  def schedule_remove_inactives() do
    Process.send_after(self(), :remove_inactives, @inactive_interval)
  end

  @doc """
  Filtra o mapa de sensores retornado, provendo apenas os sensores que estão
  atualmente marcados como ativos.
  """
  def get_list_active_sensors() do
    GenServer.call(__MODULE__, :get_all)
    |> Enum.filter(fn {_id, data} -> data.active end)
    |> Map.new()
  end

  @impl true
  @doc false
  def handle_info(:remove_inactives, state) do
    # Usa o UTC agora subtraindo 3 horas para equiparar ao fuso horário (BRT)
    # das timestamps enviadas pelos próprios sensores.
    now = DateTime.utc_now() |> DateTime.add(-3 * 3600)

    timeout_seconds = div(@inactive_interval, 1000)

    new_state =
      state
      # Remove os sensores que já estão marcados como inativos e cujo tempo de
      # ausência excedeu o limite máximo (timeout_seconds).
      |> Enum.reject(fn {_id, sensor_data} ->
        {:ok, last_seen, _} = DateTime.from_iso8601(sensor_data.timestamp)

        !sensor_data.active && DateTime.diff(now, last_seen) > timeout_seconds
      end)
      |> Map.new()

    schedule_remove_inactives()
    {:noreply, new_state}
  end

  @impl true
  @doc false
  def handle_info(:check_actives, state) do
    # Opcional: Aqui poderíamos subtrair 3h caso quiséssemos a mesma lógica do remove_inactives,
    # ou podemos assumir que o fluxo vai tratar o timeout coerentemente.
    now = DateTime.utc_now()

    timeout_seconds = div(@active_interval, 1000)

    new_state =
      Map.new(state, fn {id, sensor_data} ->
        {:ok, last_seen, _} = DateTime.from_iso8601(sensor_data.timestamp)

        # Se o tempo desde a última leitura for maior que o tempo limite de atividade,
        # o sensor é atualizado e marcado como inativo sem ser removido imediatamente.
        if DateTime.diff(now, last_seen) > timeout_seconds do
          {id, %{sensor_data | active: false}}
        else
          {id, sensor_data}
        end
      end)

    schedule_actives()

    {:noreply, new_state}
  end

  @impl true
  @doc false
  def handle_cast({:update, sensor_id, data}, state) do
    # Pega o estado atual do sensor ou inicia com um histórico vazio
    current_sensor = Map.get(state, sensor_id, %{history: []})

    new_value = data.value
    # Mantém apenas as últimas 50 leituras na lista de histórico para otimizar memória
    new_history = Enum.take([new_value | current_sensor.history], 50)

    updated_data = Map.put(data, :history, new_history)
    new_state = Map.put(state, sensor_id, updated_data)

    {:noreply, new_state}
  end

  @impl true
  @doc false
  def handle_call(:get_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @doc false
  def handle_call({:get_one, sensor_id}, _from, state) do
    {:reply, Map.get(state, sensor_id), state}
  end
end
