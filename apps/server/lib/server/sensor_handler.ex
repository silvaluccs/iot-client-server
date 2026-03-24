defmodule Server.SensorHandler do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
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
