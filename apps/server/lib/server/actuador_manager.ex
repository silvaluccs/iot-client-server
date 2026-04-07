defmodule Server.ActuadorManager do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    schedule_actuators()
    {:ok, %{}}
  end

  defp schedule_actuators() do
    Process.send_after(self(), :check_status_and_remove, 180000)
  end

  def get_last_command_executed(id) do
    GenServer.call(__MODULE__, {:get_last_command_executed, id})
  end

  def update_actuator(id, actuador) do
    GenServer.cast(__MODULE__, {:update_actuator, id, actuador})
  end

  def get_all_actuators() do
    GenServer.call(__MODULE__, {:get_all_actuators})
  end

  def get_actuator(id) do
    GenServer.call(__MODULE__, {:get_actuator, id})
  end

  @impl true
  def handle_info(:check_status_and_remove, state) do
    now = DateTime.utc_now() |> DateTime.add(-3 * 3600)

    timeout_seconds = div(120_000, 1000)

    new_state =
      state
      |> Enum.reject(fn {_id, actuator_data} ->
        {:ok, last_seen, _} = DateTime.from_iso8601(actuator_data.last_seen)

        DateTime.diff(now, last_seen) > timeout_seconds
      end)
      |> Map.new()

    schedule_actuators()

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_last_command_executed, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, nil, state}
      actuator_data -> {:reply, actuator_data.last_command_executed, state}
    end
  end

  @impl true
  def handle_call({:get_all_actuators}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:get_actuator, id}, _from, state) do
    {:reply, Map.get(state, id), state}
  end

  @impl true
  def handle_cast({:update_actuator, id, actuador}, state) do
    {:noreply, Map.put(state, id, actuador)}
  end
end
