defmodule Server.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Server.TcpServer, 4000},
      Server.ClientSupervisor
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
