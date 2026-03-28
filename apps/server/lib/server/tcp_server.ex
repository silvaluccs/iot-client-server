defmodule Server.TcpServer do
  require Logger

  use GenServer, restart: :temporary

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("TCP server started on port #{port}")

        send(self(), :accept)

        {:ok, %{socket: socket}}

      {:error, reason} ->
        Logger.error("Failed to start TCP server: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.socket) do
      {:ok, client_socket} ->
        Logger.info("Client connected: #{inspect(client_socket)}")

        # Inicia uma task para ler o primeiro pacote (Handshake) sem bloquear o servidor TCP
        {:ok, task_pid} = Task.start(fn -> perform_handshake(client_socket) end)
        :ok = :gen_tcp.controlling_process(client_socket, task_pid)

        send(self(), :accept)

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to accept client connection: #{reason}")
        {:noreply, state}
    end
  end

  defp perform_handshake(client_socket) do
    # Aguarda a primeira mensagem (com timeout de 5 segundos)
    case :gen_tcp.recv(client_socket, 0, 5000) do
      {:ok, data} ->
        trimmed = String.trim(data)

        case Shared.Protocol.decode(trimmed) do
          # Se a mensagem contiver "name" e "active", sabemos que é um ActuatorRegistration
          {:ok, %{"name" => _, "active" => _}} ->
            Logger.info("Handshake: Actuator identificado.")

            # Aqui chamamos o ActuatorHandler que você vai criar (ou já tem)
            {:ok, pid} = Server.ActuatorHandler.start_link(client_socket)

            # Passa o controle do socket para o novo PID
            :ok = :gen_tcp.controlling_process(client_socket, pid)
            send(pid, :socket_ready)

            # Repassa a mensagem de registro para ele processar
            send(pid, {:tcp, client_socket, data})

          # Se a mensagem contiver apenas "id" (sem os dados de atuador), é o ClientRegistration
          {:ok, %{"id" => _}} ->
            Logger.info("Handshake: Client identificado.")

            {:ok, pid} = Server.ClientSupervisor.start_child(client_socket)

            # Passa o controle do socket para o ClientHandler
            :ok = :gen_tcp.controlling_process(client_socket, pid)
            send(pid, :socket_ready)

          # (Opcional) Repassar a mensagem de registro se o ClientHandler for usar o Client ID

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
