defmodule Server.StressTest do
  use ExUnit.Case
  require Logger

  @port 4000
  @host ~c"localhost"

  # Aumenta o timeout do teste para 5 minutos para dar tempo das 10.000 conexões completarem
  @moduletag timeout: 300_000
  @moduletag capture_log: true

  setup_all do
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: :info) end)
    :ok
  end

  defp connect_actuator(actuator_id, name) do
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :line])

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

  defp simulate_client(client_id, actuator_id, command_val) do
    # Cada cliente abre uma nova conexão, faz handshake, envia o comando e espera a resposta
    case :gen_tcp.connect(@host, @port, [:binary, active: false, packet: :line]) do
      {:ok, socket} ->
        handshake = Jason.encode!(%{"id" => client_id}) <> "\r\n"
        :gen_tcp.send(socket, handshake)

        cmd_str = "send #{actuator_id} #{command_val}"
        command = Shared.Message.Command.new(client_id, cmd_str)
        {:ok, json} = Shared.Protocol.encode(command)
        :gen_tcp.send(socket, json <> "\r\n")

        case :gen_tcp.recv(socket, 0, 5000) do
          {:ok, data} ->
            trimmed = String.trim(data)
            {:ok, decoded} = Shared.Protocol.decode(trimmed)
            :gen_tcp.close(socket)
            {:ok, decoded}

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp drain_socket(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _data} -> drain_socket(socket)
      {:error, _} -> :ok
    end
  end

  defp wait_for_processing(initial_metrics, expected_count, retries \\ 200) do
    if retries == 0 do
      Server.Metrics.get_metrics()
    else
      current = Server.Metrics.get_metrics()
      if (current.commands_processed - initial_metrics.commands_processed) >= expected_count do
        current
      else
        Process.sleep(100)
        wait_for_processing(initial_metrics, expected_count, retries - 1)
      end
    end
  end

  test "stress test: 10000 clientes enviando comandos concorrentemente" do
    actuator_id = "act_stress_10k"
    act_sock = connect_actuator(actuator_id, "Atuador de Stress")

    Task.start(fn -> drain_socket(act_sock) end)

    # Guardar as métricas antes do teste iniciar para fazer a diferença depois
    initial_metrics = Server.Metrics.get_metrics()

    total_requests = 10000
    concurrent_requests = total_requests - 1

    # Gerar a lista de 9.999 tarefas alternando o comando entre ON e OFF
    requests =
      1..concurrent_requests
      |> Enum.map(fn i ->
        cmd = if rem(i, 2) == 0, do: "ON", else: "OFF"
        {"client_stress_#{i}", cmd}
      end)

    Logger.warning("Iniciando o disparo de #{concurrent_requests} clientes concorrentes...")

    # Dispara os clientes usando Task.async_stream.
    # max_concurrency controla o número de sockets paralelos simultâneos para evitar erro
    # de limite de arquivos do SO (ulimit), mas ainda mantém uma altíssima concorrência real.
    results =
      Task.async_stream(
        requests,
        fn {c_id, cmd} ->
          simulate_client(c_id, actuator_id, cmd)
        end,
        max_concurrency: 20,
        timeout: :infinity
      )
      |> Enum.to_list()

    # Envia o último comando de forma sequencial para garantir que seja processado por último e seja "OFF"
    Logger.warning("Enviando o último comando (OFF) para garantir o estado final...")
    last_result = simulate_client("client_stress_10000", actuator_id, "OFF")

    successes =
      Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

    successes = if match?({:ok, _}, last_result), do: successes + 1, else: successes

    Logger.warning("Requisições TCP com sucesso (sem dropar): #{successes} de #{total_requests}")

    # Espera até que o processamento seja concluído ou dê timeout
    final_metrics = wait_for_processing(initial_metrics, successes)

    received_diff = final_metrics.commands_received - initial_metrics.commands_received
    processed_diff = final_metrics.commands_processed - initial_metrics.commands_processed

    Logger.warning(
      "Métricas após o Stress Test -> Recebidos: #{received_diff}, Processados: #{processed_diff}"
    )

    # Garantir que os comandos não dropados foram contabilizados e processados
    assert received_diff >= successes
    assert processed_diff == received_diff

    # Garantir que o atuador ainda existe
    actuator_data = Server.ActuadorManager.get_actuator(actuator_id)
    assert actuator_data != nil

    # O atuador de mock deste teste não implementa o envio de feedback
    # de volta para o servidor, portanto o manager não atualizará o last_command_executed.
    # Em vez disso, validamos se o último cliente recebeu a confirmação de
    # que o comando foi roteado para o atuador corretamente.
    assert {:ok, %{"message" => msg}} = last_result
    assert String.contains?(msg, "enviado ao Atuador")

    :gen_tcp.close(act_sock)
  end
end
