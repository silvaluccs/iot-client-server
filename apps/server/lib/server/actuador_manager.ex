defmodule Server.ActuadorManager do
  @moduledoc """
  Gerenciador central de estado dos atuadores conectados.

  Este GenServer mantém um registro na memória (um mapa) de todos os atuadores ativos no servidor,
  armazenando suas informações vitais (como referência do socket, estado de ativação e a data/hora
  da última comunicação). Ele também gerencia um processo de limpeza periódica que remove da
  memória os atuadores que estão inativos ou desconectados há muito tempo.
  """

  use GenServer

  @doc """
  Inicia o processo gerenciador de atuadores e o vincula à árvore de supervisão local.
  """
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(_args) do
    # Dispara imediatamente o ciclo de limpeza contínua de atuadores ociosos (dead-lettering)
    schedule_actuators()

    # O estado inicial do GenServer é um mapa vazio %{}
    {:ok, %{}}
  end

  # Função auxiliar privada para agendar uma verificação na própria caixa de mensagens
  # após 180.000 milissegundos (3 minutos).
  defp schedule_actuators() do
    Process.send_after(self(), :check_status_and_remove, 180_000)
  end

  @doc """
  Retorna o último comando executado (ex: "ON", "OFF") por um atuador específico através do seu `id`.
  """
  def get_last_command_executed(id) do
    GenServer.call(__MODULE__, {:get_last_command_executed, id})
  end

  @doc """
  Atualiza as informações de telemetria e estado de um atuador. Caso o atuador não exista,
  ele é inserido no mapa de registros. Operação assíncrona (fire-and-forget).
  """
  def update_actuator(id, actuador) do
    GenServer.cast(__MODULE__, {:update_actuator, id, actuador})
  end

  @doc """
  Retorna um mapa contendo as informações completas de todos os atuadores registrados e ativos.
  """
  def get_all_actuators() do
    GenServer.call(__MODULE__, {:get_all_actuators})
  end

  @doc """
  Retorna os detalhes de um único atuador baseado no seu identificador único (`id`).
  """
  def get_actuator(id) do
    GenServer.call(__MODULE__, {:get_actuator, id})
  end

  @impl true
  @doc false
  def handle_info(:check_status_and_remove, state) do
    # Gera a data e hora atual ajustada ao fuso de Brasília (UTC-3)
    # para garantir consistência temporal com os registros que chegam dos dispositivos.
    now = DateTime.utc_now() |> DateTime.add(-3 * 3600)

    # Define o tempo limite de tolerância (timeout) para 120 segundos.
    # Se o atuador não relatar presença por mais de 2 minutos, ele será considerado "morto".
    timeout_seconds = div(120_000, 1000)

    new_state =
      state
      # Itera sobre cada atuador registrado e expulsa (reject) os que atingiram o limite de inatividade.
      |> Enum.reject(fn {_id, actuator_data} ->
        # Faz o parser da string ISO8601 guardada no atributo 'last_seen' do dispositivo.
        {:ok, last_seen, _} = DateTime.from_iso8601(actuator_data.last_seen)

        # Se a diferença em segundos entre 'agora' e a 'última vez visto' for maior que o tolerado, ele é removido.
        DateTime.diff(now, last_seen) > timeout_seconds
      end)
      |> Map.new()

    # Reagenda a próxima rotina de verificação
    schedule_actuators()

    {:noreply, new_state}
  end

  @impl true
  @doc false
  def handle_call({:get_last_command_executed, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, nil, state}
      actuator_data -> {:reply, actuator_data.last_command_executed, state}
    end
  end

  @impl true
  @doc false
  def handle_call({:get_all_actuators}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @doc false
  def handle_call({:get_actuator, id}, _from, state) do
    {:reply, Map.get(state, id), state}
  end

  @impl true
  @doc false
  def handle_cast({:update_actuator, id, actuador}, state) do
    # Cria ou substitui de forma eficiente o registro do atuador usando seu ID como chave de mapeamento
    {:noreply, Map.put(state, id, actuador)}
  end
end
