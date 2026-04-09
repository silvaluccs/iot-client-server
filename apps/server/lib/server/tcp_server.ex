defmodule Server.TcpServer do
  @moduledoc """
  Servidor TCP principal responsável por aceitar conexões de rede de clientes e atuadores.

  Este processo escuta ativamente em uma porta específica e, para cada nova conexão
  estabelecida, realiza um processo de "handshake" (aperto de mão) inicial.
  Baseado no payload do handshake, ele roteia a conexão para o manipulador
  adequado (`Server.ActuatorHandler` para atuadores ou `Server.ClientHandler`
  via `Server.ClientSupervisor` para clientes).
  """
  require Logger

  use GenServer, restart: :temporary

  @doc """
  Inicia o servidor TCP na porta especificada e o vincula à árvore de supervisão.
  """
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  @doc false
  def init(port) do
    # Inicia a escuta na porta TCP. O modo active: false é usado inicialmente
    # para que o handshake possa ser lido de forma controlada e síncrona.
    case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("Servidor TCP iniciado na porta #{port}")

        # Envia uma mensagem para si mesmo para começar a aceitar a primeira conexão
        send(self(), :accept)

        {:ok, %{socket: socket}}

      {:error, reason} ->
        Logger.error("Falha ao iniciar o servidor TCP: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  @doc false
  def handle_info(:accept, state) do
    # Aceita a próxima conexão de rede de forma bloqueante neste GenServer
    case :gen_tcp.accept(state.socket) do
      {:ok, client_socket} ->
        Logger.info("Cliente conectado: #{inspect(client_socket)}")

        # Inicia uma task paralela para ler o primeiro pacote (Handshake)
        # Isso impede que um cliente lento no envio do handshake bloqueie o servidor TCP inteiro.
        {:ok, task_pid} = Task.start(fn -> perform_handshake(client_socket) end)

        # Transfere a propriedade do socket TCP para a task criada
        case :gen_tcp.controlling_process(client_socket, task_pid) do
          :ok -> :ok
          {:error, _} -> :gen_tcp.close(client_socket)
        end

        # Solicita imediatamente aceitar a próxima conexão pendente
        send(self(), :accept)

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Falha ao aceitar conexão do cliente: #{reason}")
        {:noreply, state}
    end
  end

  # --- Funções Internas ---

  # Executa a negociação inicial para descobrir o tipo do dispositivo conectado
  defp perform_handshake(client_socket) do
    # Aguarda até 5 segundos (5000 ms) pelo primeiro pacote de registro
    case :gen_tcp.recv(client_socket, 0, 5000) do
      {:ok, data} ->
        trimmed = String.trim(data)

        # Tenta decodificar o payload JSON para identificar o remetente
        case Shared.Protocol.decode(trimmed) do
          # Se a mensagem contiver "name" e "active", assume-se que é um Atuador
          {:ok, %{"name" => _, "active" => _}} ->
            Logger.info("Handshake: Atuador identificado.")

            {:ok, pid} = Server.ActuatorHandler.start_link(client_socket)

            # Transfere a posse do socket para o novo processo handler
            case :gen_tcp.controlling_process(client_socket, pid) do
              :ok ->
                # Sinaliza que o handler pode começar a escutar o tráfego ativamente
                send(pid, :socket_ready)
                # Encaminha a mensagem original para processamento no novo handler
                send(pid, {:tcp, client_socket, data})

              {:error, _} ->
                :gen_tcp.close(client_socket)
            end

          # Se a mensagem contiver apenas "id", assume-se que é um Cliente (Shell)
          {:ok, %{"id" => _}} ->
            Logger.info("Handshake: Cliente identificado.")

            # Instancia um manipulador através do supervisor dinâmico de clientes
            {:ok, pid} = Server.ClientSupervisor.start_child(client_socket)

            # Transfere o socket para o manipulador do cliente
            case :gen_tcp.controlling_process(client_socket, pid) do
              :ok -> send(pid, :socket_ready)
              {:error, _} -> :gen_tcp.close(client_socket)
            end

          _ ->
            Logger.error("Handshake desconhecido ou falha na decodificação: #{inspect(trimmed)}")
            :gen_tcp.close(client_socket)
        end

      {:error, reason} ->
        Logger.error("Falha no Handshake: #{inspect(reason)}")
        :gen_tcp.close(client_socket)
    end
  end
end
