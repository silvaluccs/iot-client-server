defmodule Server.ConcurrencyTest do
  use ExUnit.Case
  require Logger

  @port 4000
  @host ~c"localhost"

  setup do
    # Garante que as métricas estão limpas (ou podemos apenas isolar por IDs)
    # Como as métricas são globais no GenServer, o estado pode acumular entre testes.
    :ok
  end

  defp connect_client(client_id) do
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :line])

    # Handshake do Client
    handshake = Jason.encode!(%{"id" => client_id}) <> "\r\n"
    :ok = :gen_tcp.send(socket, handshake)

    # Dá um tempinho mínimo pro servidor processar o handshake e passar pro ClientHandler
    Process.sleep(100)
    socket
  end

  defp connect_actuator(actuator_id, name) do
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :line])

    # Handshake do Atuador
    handshake =
      Jason.encode!(%{
        "id" => actuator_id,
        "name" => name,
        "active" => true,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }) <> "\r\n"

    :ok = :gen_tcp.send(socket, handshake)
    Process.sleep(100)
    socket
  end

  defp send_command(socket, client_id, command_str) do
    command = Shared.Message.Command.new(client_id, command_str)
    {:ok, json} = Shared.Protocol.encode(command)
    :ok = :gen_tcp.send(socket, json <> "\r\n")
  end

  defp receive_response(socket, timeout \\ 5000) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        trimmed = String.trim(data)
        {:ok, decoded} = Shared.Protocol.decode(trimmed)
        decoded

      {:error, reason} ->
        {:error, reason}
    end
  end

  @tag timeout: 10000
  test "cliente 2 nao eh bloqueado pelo comando slow do cliente 1 (Concorrencia)" do
    # 1. Conecta os dois clientes
    sock1 = connect_client("client_slow")
    sock2 = connect_client("client_fast")

    # 2. Cliente 1 envia um comando pesado (demora 2 segundos)
    send_command(sock1, "client_slow", "slow 2")

    # Garante que o comando chegou no servidor
    Process.sleep(100)

    # 3. Cliente 2 envia um comando leve enquanto o Cliente 1 está travado no servidor
    send_command(sock2, "client_fast", "server status")

    # 4. Cliente 2 deve receber a resposta IMEDIATAMENTE (timeout bem curto para provar que não bloqueou)
    # Se o servidor fosse sequencial/bloqueante, o recv do sock2 ia dar timeout aqui!
    start_time = System.monotonic_time(:millisecond)
    # Timeout de 500ms
    resp2 = receive_response(sock2, 500)
    end_time = System.monotonic_time(:millisecond)

    assert map_size(resp2) > 0
    assert String.contains?(resp2["message"], "Status do Servidor:")

    # O tempo de resposta do Cliente 2 tem que ser MUITO menor que os 2 segundos do slow
    assert end_time - start_time < 1000

    # 5. Cliente 1 recebe a resposta só depois dos 2 segundos
    resp1 = receive_response(sock1, 3000)
    assert map_size(resp1) > 0
    assert String.contains?(resp1["message"], "Comando 'slow' finalizado")

    :gen_tcp.close(sock1)
    :gen_tcp.close(sock2)
  end

  test "atuador e cliente operam concorrentemente sem bloqueios" do
    # 1. Conecta um Atuador
    act_sock = connect_actuator("act_test_1", "Luz da Sala")

    # 2. Conecta um Cliente
    client_sock = connect_client("client_act_test")

    # 3. Cliente pede a lista de atuadores
    send_command(client_sock, "client_act_test", "ls actuators")

    resp_ls = receive_response(client_sock, 1000)
    assert map_size(resp_ls) > 0
    assert String.contains?(resp_ls["message"], "act_test_1")
    assert String.contains?(resp_ls["message"], "Luz da Sala")

    # 4. Cliente envia um comando para o Atuador ligar (ON)
    send_command(client_sock, "client_act_test", "send act_test_1 ON")

    # 5. Verifica se o Atuador recebeu o comando concorrentemente
    # O servidor encaminha a mensagem pro socket do Atuador
    act_msg = receive_response(act_sock, 1000)
    assert map_size(act_msg) > 0
    assert act_msg["command"] == "ON"

    # 6. Verifica se o cliente recebeu o ACK de confirmação de envio
    resp_send = receive_response(client_sock, 1000)
    assert map_size(resp_send) > 0
    assert String.contains?(resp_send["message"], "enviado ao Atuador act_test_1")

    :gen_tcp.close(act_sock)
    :gen_tcp.close(client_sock)
  end
end
