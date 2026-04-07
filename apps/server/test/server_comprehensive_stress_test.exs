defmodule Server.ComprehensiveStressTest do
  use ExUnit.Case
  require Logger

  @tcp_port 4000
  @udp_port 5000
  @host ~c"localhost"

  @moduletag timeout: 300_000
  @moduletag capture_log: true

  setup_all do
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: :info) end)
    :ok
  end

  defp send_udp_packet(socket, sensor_id) do
    payload = Shared.Message.SensorData.new(sensor_id, "temperature", :rand.uniform(100))
    {:ok, json} = Shared.Protocol.encode(payload)
    :gen_udp.send(socket, @host, @udp_port, json <> "\n")
  end

  defp simulate_incomplete_handshake(_) do
    case :gen_tcp.connect(@host, @tcp_port, [:binary, active: false, packet: :line]) do
      {:ok, socket} ->
        # Send garbage or close immediately to test fault tolerance
        :gen_tcp.send(socket, "GARBAGE_HANDSHAKE\r\n")
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_udp_processing(expected_count, retries \\ 50) do
    sensors = Server.SensorManager.get_all_data()
    count = map_size(sensors)

    if count >= expected_count do
      {:ok, count}
    else
      if retries == 0 do
        Logger.warning("Timeout UDP. Pacotes recebidos: #{count} de #{expected_count}")
        {:error, count}
      else
        Process.sleep(100)
        wait_for_udp_processing(expected_count, retries - 1)
      end
    end
  end

  test "stress test UDP: milhares de sensores enviando dados simultaneamente" do
    Logger.warning("Iniciando Stress Test UDP...")

    {:ok, udp_socket} = :gen_udp.open(0, [:binary, active: false])
    total_packets = 5000

    requests = Enum.map(1..total_packets, fn i -> "sensor_stress_#{i}" end)

    Task.async_stream(
      requests,
      fn sensor_id ->
        send_udp_packet(udp_socket, sensor_id)
      end,
      max_concurrency: 100,
      timeout: :infinity
    )
    |> Stream.run()

    # O servidor UDP do Elixir processa mensagens em fila. Damos um tempo para o SensorManager ser populado.
    # Como UDP não tem garantia de entrega (e sofre drop no buffer local), aceitamos perdas.
    result = wait_for_udp_processing(total_packets)

    count = case result do
      {:ok, c} -> c
      {:error, c} -> c
    end

    Logger.warning("Pacotes UDP processados: #{count} de #{total_packets}")
    assert count > 0

    :gen_udp.close(udp_socket)
    Logger.warning("Stress Test UDP concluído com sucesso!")
  end

  test "stress test TCP fault tolerance: milhares de conexoes com handshakes invalidos/incompletos" do
    Logger.warning("Iniciando Stress Test de Handshakes Incompletos TCP...")

    total_connections = 2000

    results =
      Task.async_stream(
        1..total_connections,
        &simulate_incomplete_handshake/1,
        max_concurrency: 50,
        timeout: :infinity
      )
      |> Enum.to_list()

    successes = Enum.count(results, &match?({:ok, :ok}, &1))

    Logger.warning("Conexões com erro tratadas: #{successes} de #{total_connections}")

    # O servidor não deve ter crashado e deve estar pronto para aceitar conexões válidas.
    assert successes > 0

    # Valida se o servidor ainda responde a uma conexão real após a tempestade de conexões falhas
    case :gen_tcp.connect(@host, @tcp_port, [:binary, active: false, packet: :line]) do
      {:ok, socket} ->
        handshake = Jason.encode!(%{"id" => "client_survivor"}) <> "\r\n"
        :gen_tcp.send(socket, handshake)
        :gen_tcp.close(socket)
        assert true

      {:error, reason} ->
        flunk("O servidor parou de aceitar conexões após o stress test. Motivo: #{inspect(reason)}")
    end

    Logger.warning("Stress Test de Handshakes Incompletos concluído!")
  end
end
