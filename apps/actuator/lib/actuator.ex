defmodule Actuator.Application do
  @moduledoc """
  O ponto de entrada para a aplicação do Atuador (Actuator).

  Este módulo define o callback da aplicação e configura a árvore de supervisão
  para o serviço do atuador, gerenciando o ciclo de vida dos seus processos de trabalho.
  """

  use Application

  @doc """
  Inicia a aplicação e sua árvore de supervisão.
  """
  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        [
          Actuator.Worker
        ]
      end

    opts = [strategy: :one_for_one, name: Actuator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
