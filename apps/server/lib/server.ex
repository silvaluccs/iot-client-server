defmodule Server.Application do
  @moduledoc """
  Ponto de entrada principal para a aplicação do Servidor Central.

  Este módulo define o callback da aplicação e é responsável por iniciar
  e monitorar a árvore de supervisão principal do servidor. A árvore de
  supervisão inclui gerenciadores de estado (Sensores e Atuadores),
  servidores de rede (TCP e UDP), métricas e o supervisor dinâmico para
  os clientes conectados.
  """

  use Application

  @doc """
  Inicia a aplicação do servidor e sua respectiva árvore de supervisão.

  Os seguintes processos filhos são iniciados em ordem:
  - `Server.Metrics`: Mantém as métricas de saúde e desempenho do servidor.
  - `Server.TcpServer`: Escuta na porta 4000 requisições de Clientes e Atuadores.
  - `Server.UdpServer`: Escuta na porta 5000 telemetria contínua dos Sensores.
  - `Server.SensorManager`: Gerencia o estado e histórico de sensores.
  - `Server.ActuadorManager`: Gerencia o estado de atuadores.
  - `Server.ClientSupervisor`: Supervisor dinâmico para processos de clientes TCP.
  """
  @impl true
  def start(_type, _args) do
    children = [
      Server.Metrics,
      {Server.TcpServer, 4000},
      {Server.UdpServer, 5000},
      Server.SensorManager,
      Server.ActuadorManager,
      Server.ClientSupervisor
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
