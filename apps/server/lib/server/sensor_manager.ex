defmodule Server.SensorManager do
  use GenServer

  @active_interval 60000
  @inactive_interval 120_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_actives()
    schedule_remove_inactives()

    {:ok, %{}}
  end

  def update_sensor(sensor_id, data) do
    GenServer.cast(__MODULE__, {:update, sensor_id, data})
  end

  def get_all_data do
    GenServer.call(__MODULE__, :get_all)
  end

  def get_sensor_data(sensor_id) do
    GenServer.call(__MODULE__, {:get_one, sensor_id})
  end

  def remove_sensor(sensor_id) do
    GenServer.cast(__MODULE__, {:remove, sensor_id})
  end

  def schedule_actives() do
    Process.send_after(self(), :check_actives, @active_interval)
  end

  def schedule_remove_inactives() do
    Process.send_after(self(), :remove_inactives, @inactive_interval)
  end

  def get_list_active_sensors() do
    GenServer.call(__MODULE__, :get_all)
    |> Enum.filter(fn {_id, data} -> data.active end)
    |> Map.new()
  end

  @impl true
  def handle_info(:remove_inactives, state) do
    # i use utc_now - 3 hours to match the timezone of the incoming timestamps
    now = DateTime.utc_now() |> DateTime.add(-3 * 3600)

    timeout_seconds = div(@inactive_interval, 1000)

    new_state =
      state
      |> Enum.reject(fn {_id, sensor_data} ->
        {:ok, last_seen, _} = DateTime.from_iso8601(sensor_data.timestamp)

        !sensor_data.active && DateTime.diff(now, last_seen) > timeout_seconds
      end)
      |> Map.new()

    schedule_remove_inactives()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_actives, state) do
    now = DateTime.utc_now()

    timeout_seconds = div(@active_interval, 1000)

    new_state =
      Map.new(state, fn {id, sensor_data} ->
        {:ok, last_seen, _} = DateTime.from_iso8601(sensor_data.timestamp)

        if DateTime.diff(now, last_seen) > timeout_seconds do
          {id, %{sensor_data | active: false}}
        else
          {id, sensor_data}
        end
      end)

    schedule_actives()

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update, sensor_id, data}, state) do
    new_state = Map.put(state, sensor_id, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:get_one, sensor_id}, _from, state) do
    {:reply, Map.get(state, sensor_id), state}
  end
end
