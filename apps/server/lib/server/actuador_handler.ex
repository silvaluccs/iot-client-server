defmodule Server.ActuatorHandler do
  @moduledoc """
  Gerencia a conexão TCP individual de um atuador conectado ao servidor.

  Este processo GenServer é iniciado temporariamente para cada novo atuador que se conecta.
  Ele é responsável por receber os dados de telemetria e estado (via socket TCP decodificado de JSON),
  e registrar ou atualizar as informações do atuador no gerenciador global de atuadores (`Server.ActuadorManager`).
  """

  require Logger
  use GenServer, restart: :temporary

  @doc """
  Inicia o processo manipulador (handler) vinculando-o ao socket TCP do cliente recém-conectado.
  """
  def start_link(client_socket), do: GenServer.start_link(__MODULE__, client_socket)

  @impl true
  @doc false
  def init(client_socket) do
    # O estado inicial do GenServer apenas mantém a referência para o socket TCP da conexão ativa.
    {:ok, %{socket: client_socket}}
  end

  @impl true
  @doc false
  def handle_info(:socket_ready, state) do
    # Configura o socket para enviar as mensagens recebidas como eventos do Erlang/Elixir ({:tcp, ...})
    # O packet: :line garante que os pacotes sejam lidos linha a linha (delimitados por \n ou \r\n).
    :ok = :inet.setopts(state.socket, active: true, packet: :line)
    Logger.info("O manipulador do atuador está pronto para receber dados.")
    {:noreply, state}
  end

  @impl true
  @doc false
  def handle_info({:tcp, socket, data}, state) do
    trimmed = String.trim(data)

    if trimmed != "" do
      with {:ok, decode} <- Shared.Protocol.decode(trimmed) do
        case decode do
          # Casamento de padrão 1: O atuador enviou o relatório de estado contendo o último comando executado
          %{
            "id" => id,
            "name" => actuador_name,
            "command_executed" => command_executed,
            "active" => active,
            "timestamp" => ts
          } ->
            Server.ActuadorManager.update_actuator(
              id,
              %{
                id: id,
                socket: socket,
                name: actuador_name,
                last_command_executed: command_executed,
                active: active,
                last_seen: ts
              }
            )

          # Casamento de padrão 2: O atuador enviou a mensagem de registro inicial, sem comandos prévios executados
          %{"id" => id, "name" => actuador_name, "active" => active, "timestamp" => ts} ->
            Server.ActuadorManager.update_actuator(
              id,
              %{
                id: id,
                socket: socket,
                name: actuador_name,
                active: active,
                last_seen: ts,
                last_command_executed: nil
              }
            )

          # Tratamento para mensagens não reconhecidas
          _ ->
            Logger.error(
              "Formato de mensagem desconhecido recebido do atuador: #{inspect(decode)}"
            )
        end
      else
        {:error, reason} ->
          Logger.error("Falha ao decodificar a mensagem do atuador: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  @doc false
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("Erro TCP no socket do atuador #{inspect(socket)}: #{reason}")
    {:stop, reason, state}
  end

  @impl true
  @doc false
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Atuador desconectado: #{inspect(socket)}")
    {:stop, :normal, state}
  end
end
