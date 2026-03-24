defmodule Shared.Message do
  defmodule Command do
    @derive Jason.Encoder
    defstruct [:pid, :command_id, :timestamp]

    def new(pid, command_id, timestamp) do
      %__MODULE__{pid: pid, command_id: command_id, timestamp: timestamp}
    end
  end

  defmodule ClienteResponse do
    @derive Jason.Encoder
    defstruct [:pid, :message, :timestamp]

    def new(pid, message, timestamp) do
      %__MODULE__{pid: pid, message: message, timestamp: timestamp}
    end
  end

  defmodule SensorData do
    @derive Jason.Encoder
    defstruct [:id, :type, :value, :timestamp]

    def new(id, type, value) do
      brazilian_time = DateTime.utc_now() |> DateTime.add(-3 * 3600) |> DateTime.to_iso8601()
      %__MODULE__{id: id, type: type, value: value, timestamp: brazilian_time}
    end
  end
end
