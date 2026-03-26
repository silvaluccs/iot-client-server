defmodule Shared.Message do
  defmodule Command do
    @derive Jason.Encoder
    defstruct [:id, :command_id, :timestamp]

    def new(id, command_id) do
      %__MODULE__{id: id, command_id: command_id, timestamp: Shared.Message.timestamp()}
    end

    def new(id, command_id, timestamp) do
      %__MODULE__{id: id, command_id: command_id, timestamp: timestamp}
    end
  end

  defmodule ClienteResponse do
    @derive Jason.Encoder
    defstruct [:client_id, :message, :timestamp]

    def new(client_id, message) do
      %__MODULE__{client_id: client_id, message: message, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule SensorData do
    @derive Jason.Encoder
    defstruct [:id, :type, :value, :timestamp]

    def new(id, type, value) do
      %__MODULE__{id: id, type: type, value: value, timestamp: Shared.Message.timestamp()}
    end
  end

  def timestamp do
    DateTime.utc_now() |> DateTime.add(-3 * 3600) |> DateTime.to_iso8601()
  end
end
