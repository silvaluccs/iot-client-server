defmodule Shared.Message do
  @moduledoc """
  Módulo base que define as estruturas (structs) de mensagens utilizadas na
  comunicação entre os diferentes componentes do sistema (Cliente, Servidor,
  Sensor e Atuador).

  Todas as estruturas derivam `Jason.Encoder` para facilitar a serialização em JSON
  antes do envio pela rede.
  """

  defmodule Command do
    @moduledoc """
    Representa um comando genérico enviado por um cliente para o servidor.
    """
    @derive Jason.Encoder
    defstruct [:id, :command, :timestamp]

    @doc """
    Cria uma nova estrutura de comando utilizando o timestamp atual.
    """
    def new(id, command) do
      %__MODULE__{id: id, command: command, timestamp: Shared.Message.timestamp()}
    end

    @doc """
    Cria uma nova estrutura de comando com um timestamp especificado.
    """
    def new(id, command, timestamp) do
      %__MODULE__{id: id, command: command, timestamp: timestamp}
    end
  end

  defmodule Response do
    @moduledoc """
    Representa uma resposta enviada pelo servidor e direcionada a um cliente específico.
    """
    @derive Jason.Encoder
    defstruct [:client_id, :message, :timestamp]

    @doc """
    Cria uma nova resposta com o timestamp atual.
    """
    def new(client_id, message) do
      %__MODULE__{client_id: client_id, message: message, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule SensorData do
    @moduledoc """
    Representa os dados de telemetria coletados e enviados por um sensor.
    """
    @derive Jason.Encoder
    defstruct [:id, :type, :value, :timestamp]

    @doc """
    Cria uma nova estrutura de leitura de sensor com o timestamp atual.
    """
    def new(id, type, value) do
      %__MODULE__{id: id, type: type, value: value, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule ActuatorCommand do
    @moduledoc """
    Representa um comando de ação (ex: "ON" ou "OFF") despachado do servidor para um atuador.
    """
    @derive Jason.Encoder
    defstruct [:id, :command, :timestamp]

    @doc """
    Cria um novo comando de atuador com o timestamp atual.
    """
    def new(id, command) do
      %__MODULE__{id: id, command: command, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule ActuatorRegistration do
    @moduledoc """
    Representa a mensagem de registro enviada por um atuador assim que estabelece conexão com o servidor.
    """
    @derive Jason.Encoder
    defstruct [:id, :name, :active, :timestamp]

    @doc """
    Cria uma nova mensagem de registro de atuador com o timestamp atual.
    """
    def new(id, name, active) do
      %__MODULE__{id: id, name: name, active: active, timestamp: Shared.Message.timestamp()}
    end
  end

  defmodule ClientRegistration do
    @moduledoc """
    Representa a mensagem de registro inicial enviada por um cliente ao conectar ao servidor.
    """
    @derive Jason.Encoder
    defstruct [:id, :timestamp]

    @doc """
    Cria uma nova mensagem de registro de cliente com o timestamp atual.
    """
    def new(id) do
      %__MODULE__{id: id, timestamp: Shared.Message.timestamp()}
    end
  end

  @doc """
  Gera uma string ISO8601 correspondente ao momento atual, ajustado para o fuso horário de Brasília (UTC-3).
  """
  def timestamp do
    DateTime.utc_now() |> DateTime.add(-3 * 3600) |> DateTime.to_iso8601()
  end
end
