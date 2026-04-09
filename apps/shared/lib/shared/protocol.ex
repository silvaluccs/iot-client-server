defmodule Shared.Protocol do
  @moduledoc """
  Módulo responsável por encapsular a lógica de serialização e desserialização
  de mensagens utilizadas na comunicação entre os componentes do sistema IoT.

  Atualmente, a camada de transporte utiliza o formato JSON (através da
  biblioteca `Jason`) como padrão para a troca de dados pela rede.
  """

  @doc """
  Codifica uma estrutura de dados Elixir (como mapas ou structs compatíveis)
  para uma string no formato JSON.

  Retorna `{:ok, string_json}` em caso de sucesso, ou `{:error, motivo}` se
  houver falha na codificação.
  """
  def encode(data) do
    Jason.encode(data)
  end

  @doc """
  Decodifica uma string ou pacote JSON recebido da rede para uma estrutura de
  dados nativa do Elixir (geralmente um mapa).

  Retorna `{:ok, mapa}` em caso de sucesso, ou `{:error, motivo}` se a
  string fornecida não for um JSON válido.
  """
  def decode(data) do
    Jason.decode(data)
  end
end
