defmodule Actuator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Actuator.Worker
      # Starts a worker by calling: Actuator.Worker.start_link(arg)
      # {Actuator.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Actuator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
