defmodule Teiserver.Tachyon.Responses.LobbyHost.CreateResponse do
  @moduledoc """
  Updated status response - https://github.com/beyond-all-reason/tachyon/blob/master/src/schema/lobby_host.ts
  """

  alias Phoenix.PubSub
  alias Teiserver.Data.Types, as: T

  @spec execute({:error, String.t()} | T.lobby()) :: {T.tachyon_command(), T.tachyon_object()}
  def execute({:error, reason}) do
    {"system/error/response",
     %{
       "command" => "lobby_host/create/request",
       "reason" => reason
     }}
  end

  def execute({:ok, lobby}) do
    PubSub.unsubscribe(Central.PubSub, "teiserver_lobby_host_message:#{lobby.id}")
    PubSub.unsubscribe(Central.PubSub, "teiserver_lobby_updates:#{lobby.id}")
    PubSub.unsubscribe(Central.PubSub, "teiserver_lobby_chat:#{lobby.id}")

    PubSub.subscribe(Central.PubSub, "teiserver_lobby_host_message:#{lobby.id}")
    PubSub.subscribe(Central.PubSub, "teiserver_lobby_updates:#{lobby.id}")
    PubSub.subscribe(Central.PubSub, "teiserver_lobby_chat:#{lobby.id}")

    {"lobby_host/create/response", lobby}
  end
end
