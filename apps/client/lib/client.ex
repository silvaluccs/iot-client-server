defmodule Client do
  @moduledoc """
  Ponto de entrada principal para a aplicação Client.

  Este módulo é responsável por definir o callback da aplicação e configurar a
  árvore de supervisão, gerenciando o ciclo de vida dos processos essenciais do cliente,
  como a conexão de rede (`Client.Connection`) e a interface interativa (`Client.Shell`).
  """

  use Application

  @impl true
  @doc """
  Inicia a aplicação e a sua respectiva árvore de supervisão.

  No ambiente de testes (`:test`), os processos filhos (`Connection` e `Shell`)
  não são iniciados para evitar travamentos de terminal ou conexões de rede
  não intencionais durante a execução das suítes de testes.
  """
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        [
          Client.Connection,
          Client.Shell
        ]
      end

    opts = [strategy: :one_for_one, name: Client.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
