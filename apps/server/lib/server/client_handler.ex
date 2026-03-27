defmodule Server.ClientHandler do
  use GenServer
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
            Logger.info("Received command: #{inspect(command)}")
            Task.start(fn -> process_command(command, socket) end)

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
      ["ls"] ->
        send_active_sensors(client_socket, command_map)

      ["cat", "sensors"] ->
        send_all_sensors_data(client_socket, command_map)

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

  defp send_specific_sensor_data(client_socket, command_map, sensor_id) do
    case Server.SensorManager.get_sensor_data(sensor_id) do
      data when not is_nil(data) ->
        history_to_plot = Enum.reverse(data.history)

        message = "CHART:#{sensor_id}:#{Jason.encode!(history_to_plot)}"
        response = Shared.Message.Response.new(command_map.id, message)
        {:ok, json} = Shared.Protocol.encode(response)
        :gen_tcp.send(client_socket, json <> "\r\n")

      _ ->
        message = "Sensor #{sensor_id} não encontrado."
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
end
