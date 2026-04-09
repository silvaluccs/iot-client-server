defmodule Server.ClientSupervisor do
  @moduledoc """
  Supervisor dinâmico responsável por gerenciar conexões de clientes sob demanda.

  Como o servidor pode receber um número imprevisível de conexões simultâneas,
  este `DynamicSupervisor` é utilizado para iniciar, supervisionar e isolar
  falhas de cada processo `Server.ClientHandler` de maneira independente.
  """

  use DynamicSupervisor

  @doc """
  Inicia o supervisor dinâmico de clientes e o vincula à árvore de supervisão principal.
  """
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init(_) do
    # Estratégia :one_for_one garante que a falha de um client handler não afete os demais
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Inicia dinamicamente um novo processo `Server.ClientHandler` filho, anexando-o a
  este supervisor e passando o `socket` TCP recém-estabelecido como argumento inicial.
  """
  def start_child(socket) do
    spec = {Server.ClientHandler, socket}
    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, spec)
    {:ok, pid}
  end
end
