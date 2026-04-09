defmodule Sensor.Application do
  @moduledoc """
  Ponto de entrada principal para a aplicação Sensor.

  Este módulo é responsável por definir o callback da aplicação e configurar a
  árvore de supervisão, gerenciando o ciclo de vida dos processos do sensor
  (como o `Sensor.Worker`).
  """

  use Application

  @impl true
  @doc """
  Inicia a aplicação e a sua respectiva árvore de supervisão.

  No ambiente de testes (`:test`), o worker não é iniciado para evitar
  conexões de rede não intencionais durante a execução dos testes.
  """
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        [
          {Sensor.Worker, []}
        ]
      end

    opts = [strategy: :one_for_one, name: Sensor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
