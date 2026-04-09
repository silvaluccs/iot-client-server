defmodule Server.UdpServer do
  @moduledoc """
  Servidor UDP principal, otimizado para receber alto volume de telemetria.

  Diferente dos clientes e atuadores que usam TCP (orientados à conexão),
  os sensores enviam dados de forma contínua e assíncrona via protocolo UDP ("fire and forget").
  Este processo GenServer escuta na porta configurada, decodifica os pacotes JSON
  recebidos e encaminha as leituras para o `Server.SensorManager` atualizar o estado global.
  """

  require Logger
  use GenServer, restart: :permanent

  @doc """
  Inicia o servidor UDP na porta especificada e o vincula à árvore de supervisão principal.
  """
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(port \\ 5000) do
    Logger.info("Iniciando servidor UDP na porta #{port}...")

    # Abre o socket UDP. A diretiva `active: :once` é um padrão fundamental de
    # controle de fluxo em Elixir/Erlang. Ela instrui a VM a entregar apenas a
    # próxima mensagem recebida ao processo, evitando o travamento da caixa de
    # mensagens no caso de uma inundação (flood) intensa de requisições de rede.
    case :gen_udp.open(port, [:binary, active: :once, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("Servidor UDP iniciado com sucesso na porta #{port}")
        {:ok, %{socket: socket}}

      {:error, reason} ->
        Logger.error("Falha ao iniciar servidor UDP: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  @doc false
  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    # Tenta desserializar o payload binário de entrada (esperado que seja um JSON válido)
    with {:ok, message} <- Shared.Protocol.decode(data) do
      case message do
        # Pattern matching garante que a mensagem segue a estrutura de telemetria do Sensor
        %{"id" => id, "type" => type, "value" => value, "timestamp" => timestamp} ->
          # Envia as leituras desempacotadas assincronamente para o repositório global (SensorManager)
          Server.SensorManager.update_sensor(id, %{
            type: type,
            value: value,
            timestamp: timestamp,
            active: true
          })

        _ ->
          Logger.warning("Payload UDP recebido com formato desconhecido: #{inspect(message)}")
      end
    else
      {:error, reason} ->
        Logger.error("Falha ao decodificar mensagem UDP: #{inspect(reason)}")
    end

    # Após o processamento seguro de um pacote, rearmamos o socket para
    # capturar e enviar o próximo pacote UDP da fila
    :inet.setopts(state.socket, active: :once)

    {:noreply, state}
  end
end
