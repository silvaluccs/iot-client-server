defmodule Server.ClientHandler do
  use GenServer, restart: :temporary
  require Logger

  def start_link(socket), do: GenServer.start_link(__MODULE__, socket)

  @impl true
  def init(socket) do
    {:ok, %{socket: socket}}
  end

  @impl true
  def handle_info(:socket_ready, state) do
    :ok = :inet.setopts(state.socket, active: true, packet: :line)
    Logger.info("Client handler is ready to receive data.")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    trimmed = String.trim(data)

    if trimmed != "" do
      with {:ok, decode} <- Shared.Protocol.decode(trimmed) do
        case decode do
          %{"id" => _, "command" => _, "timestamp" => _} = map ->
            command = Shared.Message.Command.new(map["id"], map["command"], map["timestamp"])
            Server.Metrics.inc_received()
            Logger.info("Received command: #{inspect(command)}")

            Task.start(fn ->
              process_command(command, socket)
              Server.Metrics.inc_processed()
            end)

          _ ->
            Logger.error("Received unknown message format: #{inspect(decode)}")
        end
      else
        {:error, reason} ->
          Logger.error("Failed to decode message: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("TCP error on socket #{inspect(socket)}: #{reason}")
    {:stop, reason, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("Client disconnected: #{inspect(socket)}")
    {:stop, :normal, state}
  end

  defp process_command(command_map, client_socket) do
    parts =
      command_map.command
      |> String.downcase()
      |> String.split()

    case parts do
      ["server", "status"] ->
        send_server_status(client_socket, command_map)

      ["slow", seconds] ->
        simulate_slow_command(client_socket, command_map, seconds)

      ["ls"] ->
        send_active_sensors(client_socket, command_map)

      ["ls", "actuators"] ->
        send_active_actuators(client_socket, command_map)

      ["cat", "sensors"] ->
        send_all_sensors_data(client_socket, command_map)

      ["cat", "actuators"] ->
        send_all_actuators_data(client_socket, command_map)

      ["cat", "actuator", actuator_id] ->
        send_actuator_data(client_socket, command_map, actuator_id)

      ["send", actuator_id, cmd] ->
        send_command_to_actuator(client_socket, command_map, actuator_id, cmd)

      ["cat", sensor_id] ->
        sensor_data = Server.SensorManager.get_list_active_sensors() |> Map.get(sensor_id)

        if sensor_data do
          message =
            "Sensor #{sensor_id} (#{sensor_data.type}): #{sensor_data.value} visto pela última vez em #{sensor_data.timestamp}"

          response = Shared.Message.Response.new(command_map.id, message)
          {:ok, json} = Shared.Protocol.encode(response)
          :gen_tcp.send(client_socket, json <> "\r\n")
        else
          message = "Sensor #{sensor_id} não encontrado ou inativo."
          response = Shared.Message.Response.new(command_map.id, message)
          {:ok, json} = Shared.Protocol.encode(response)
          :gen_tcp.send(client_socket, json <> "\r\n")
        end

      ["graph", sensor_id] ->
        send_specific_sensor_data(client_socket, command_map, sensor_id)

      _ ->
        message = "Comando desconhecido: #{command_map.command}"
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")
    end
  end

  defp send_server_status(client_socket, command_map) do
    metrics = Server.Metrics.get_metrics()

    # O comando atual já foi contabilizado como recebido, mas só será contabilizado
    # como processado após essa função retornar. Para fins de exibição, ajustamos em flight e processados.
    processed = metrics.commands_processed + 1
    in_flight = max(0, metrics.in_flight - 1)

    message =
      "Status do Servidor: #{metrics.commands_received} recebidos | #{processed} processados | #{in_flight} em andamento (in-flight)\n" <>
        "Métricas da Aplicação: #{metrics.vm_processes} processos ativos (clientes/tasks) | #{metrics.vm_memory_mb} MB de memória alocada."

    response = Shared.Message.Response.new(command_map.id, message)
    {:ok, json} = Shared.Protocol.encode(response)
    :gen_tcp.send(client_socket, json <> "\r\n")
  end

  defp simulate_slow_command(client_socket, command_map, seconds_str) do
    case Integer.parse(seconds_str) do
      {seconds, _} when seconds > 0 ->
        :timer.sleep(seconds * 1000)
        message = "Comando 'slow' finalizado após #{seconds} segundos."
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")

      _ ->
        message = "Tempo inválido para o comando slow. Tente: slow 5"
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")
    end
  end

  defp send_specific_sensor_data(client_socket, command_map, sensor_id) do
    case Server.SensorManager.get_sensor_data(sensor_id) do
      %{active: true} = data ->
        history_to_plot = Enum.reverse(data.history)

        message = "CHART:#{sensor_id}:#{Jason.encode!(history_to_plot)}"
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")

      _ ->
        message = "Sensor #{sensor_id} não encontrado ou inativo."
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")
    end
  end

  defp send_all_sensors_data(client_socket, command_map) do
    sensors =
      Server.SensorManager.get_list_active_sensors()
      |> Enum.map(fn {id, data} ->
        %{id: id, type: data.type, value: data.value, last_seen: data.timestamp}
      end)

    message =
      "Dados dos sensores ativos: #{length(sensors)} \n #{Enum.map_join(sensors, "\n", fn s -> "- #{s.id} (#{s.type}): #{s.value} visto pela última vez em #{s.last_seen}" end)}"

    response = Shared.Message.Response.new(command_map.id, message)

    {:ok, json} = Shared.Protocol.encode(response)

    :gen_tcp.send(client_socket, json <> "\r\n")
  end

  defp send_active_sensors(client_socket, command_map) do
    sensors =
      Server.SensorManager.get_list_active_sensors()
      |> Enum.map(fn {id, data} -> %{id: id, type: data.type, last_seen: data.timestamp} end)

    message =
      "Sensores ativos: #{length(sensors)} \n #{Enum.map_join(sensors, "\n", fn s -> "- #{s.id} (#{s.type}) visto pela última vez em #{s.last_seen}" end)}"

    response = Shared.Message.Response.new(command_map.id, message)

    {:ok, json} = Shared.Protocol.encode(response)

    :gen_tcp.send(client_socket, json <> "\r\n")
  end

  defp send_active_actuators(client_socket, command_map) do
    actuators =
      Server.ActuadorManager.get_all_actuators()
      |> Enum.map(fn {id, data} -> %{id: id, name: data.name, last_seen: data.last_seen} end)

    message =
      "Atuadores ativos: #{length(actuators)} \n #{Enum.map_join(actuators, "\n", fn a -> "- #{a.id} (#{a.name}) visto pela última vez em #{a.last_seen}" end)}"

    response = Shared.Message.Response.new(command_map.id, message)
    {:ok, json} = Shared.Protocol.encode(response)
    :gen_tcp.send(client_socket, json <> "\r\n")
  end

  defp send_all_actuators_data(client_socket, command_map) do
    actuators =
      Server.ActuadorManager.get_all_actuators()
      |> Enum.map(fn {id, data} ->
        active_str = if data.active, do: "LIGADO", else: "DESLIGADO"
        cmd_str = Map.get(data, :last_command_executed, nil) || "Nenhum"
        %{id: id, name: data.name, status: active_str, cmd: cmd_str, last_seen: data.last_seen}
      end)

    message =
      "Dados dos atuadores ativos: #{length(actuators)} \n #{Enum.map_join(actuators, "\n", fn a -> "- #{a.id} (#{a.name}): Status #{a.status}, Último Comando: #{a.cmd}, visto pela última vez em #{a.last_seen}" end)}"

    response = Shared.Message.Response.new(command_map.id, message)
    {:ok, json} = Shared.Protocol.encode(response)
    :gen_tcp.send(client_socket, json <> "\r\n")
  end

  defp send_actuator_data(client_socket, command_map, actuator_id) do
    actuator_data = Server.ActuadorManager.get_actuator(actuator_id)

    if actuator_data do
      active_str = if actuator_data.active, do: "LIGADO", else: "DESLIGADO"
      cmd_str = Map.get(actuator_data, :last_command_executed, nil) || "Nenhum"

      message =
        "Atuador #{actuator_id} (#{actuator_data.name}): Status #{active_str}, Último Comando: #{cmd_str}, visto pela última vez em #{actuator_data.last_seen}"

      response = Shared.Message.Response.new(command_map.id, message)
      {:ok, json} = Shared.Protocol.encode(response)
      :gen_tcp.send(client_socket, json <> "\r\n")
    else
      message = "Atuador #{actuator_id} não encontrado ou inativo."
      response = Shared.Message.Response.new(command_map.id, message)
      {:ok, json} = Shared.Protocol.encode(response)
      :gen_tcp.send(client_socket, json <> "\r\n")
    end
  end

  defp send_command_to_actuator(client_socket, command_map, actuator_id, cmd) do
    actuator_data = Server.ActuadorManager.get_actuator(actuator_id)

    if actuator_data do
      msg = Shared.Message.Command.new(command_map.id, String.upcase(cmd))
      {:ok, act_json} = Shared.Protocol.encode(msg)
      :gen_tcp.send(actuator_data.socket, act_json <> "\r\n")

      message = "Comando '#{String.upcase(cmd)}' enviado ao Atuador #{actuator_id}."
      response = Shared.Message.Response.new(command_map.id, message)
      {:ok, json} = Shared.Protocol.encode(response)
      :gen_tcp.send(client_socket, json <> "\r\n")
    else
      message = "Atuador #{actuator_id} não encontrado ou inativo."
      response = Shared.Message.Response.new(command_map.id, message)
      {:ok, json} = Shared.Protocol.encode(response)
      :gen_tcp.send(client_socket, json <> "\r\n")
    end
  end
end
