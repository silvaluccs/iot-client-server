defmodule Shared.Message do
  defmodule Command do
    @derive Jason.Encoder
    defstruct [:id, :command, :timestamp]

    def new(id, command) do
      %__MODULE__{id: id, command: command, timestamp: Shared.Message.timestamp()}
    end

    def new(id, command, timestamp) do
      %__MODULE__{id: id, command: command, timestamp: timestamp}
    end
  end

  defmodule Response do
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

  defmodule ActuatorCommand do
    @derive Jason.Encoder
    defstruct [:id, :command, :timestamp]

    def new(id, command) do
      %__MODULE__{id: id, command: command, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule ActuatorRegistration do
    @derive Jason.Encoder
    defstruct [:id, :name, :active, :timestamp]

    def new(id, name, active) do
      %__MODULE__{id: id, name: name, active: active, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule ClientRegistration do
    @derive Jason.Encoder
    defstruct [:id, :timestamp]

    def new(id) do
      %__MODULE__{id: id, timestamp: Shared.Message.timestamp()}
    end
  end

  def timestamp do
    DateTime.utc_now() |> DateTime.add(-3 * 3600) |> DateTime.to_iso8601()
  end
end
