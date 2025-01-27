defmodule Teiserver.Account.LoginThrottleServerTest do
  @moduledoc false

  use Central.DataCase, async: false
  alias Central.Config
  alias Teiserver.Account
  alias Teiserver.Account.LoginThrottleServer
  alias Teiserver.Common.PubsubListener
  import Teiserver.TeiserverTestLib, only: [
    new_user: 0
  ]
  require Logger

  test "throttle test" do
    Teiserver.TeiserverConfigs.teiserver_configs()
    pid = LoginThrottleServer.get_login_throttle_server_pid()
    Config.update_site_config("system.User limit", 10)

    bot = new_user()
    Account.update_cache_user(bot.id, %{roles: ["Bot"]})
    bot_listener = PubsubListener.new_listener([])

    moderator = new_user()
    Account.update_cache_user(moderator.id, %{roles: ["Moderator"]})
    moderator_listener = PubsubListener.new_listener([])

    contributor = new_user()
    Account.update_cache_user(contributor.id, %{roles: ["Contributor"]})
    contributor_listener = PubsubListener.new_listener([])

    vip = new_user()
    Account.update_cache_user(vip.id, %{roles: ["VIP"]})
    vip_listener = PubsubListener.new_listener([])

    standard = new_user()
    Account.update_cache_user(standard.id, %{roles: ["Standard"]})
    standard_listener = PubsubListener.new_listener([])

    toxic = new_user()
    Account.update_cache_user(toxic.id, %{behaviour_score: 1})
    toxic_listener = PubsubListener.new_listener([])

    send(pid, %{channel: "teiserver_telemetry", event: :data, data: %{
      client: %{
        total: 10
      }
    }})

    # Bots should get in regardless of capacity, no messages for the listener
    r = LoginThrottleServer.attempt_login(bot_listener, bot.id)
    assert r == true
    assert PubsubListener.get(bot_listener) == []

    # Moderators have to wait in the queue
    r = LoginThrottleServer.attempt_login(moderator_listener, moderator.id)
    assert r == false
    assert PubsubListener.get(moderator_listener) == []

    # Now do the same for the other users
    r = LoginThrottleServer.attempt_login(contributor_listener, contributor.id)
    assert r == false
    assert PubsubListener.get(contributor_listener) == []

    r = LoginThrottleServer.attempt_login(vip_listener, vip.id)
    assert r == false
    assert PubsubListener.get(vip_listener) == []

    r = LoginThrottleServer.attempt_login(standard_listener, standard.id)
    assert r == false
    assert PubsubListener.get(standard_listener) == []

    r = LoginThrottleServer.attempt_login(toxic_listener, toxic.id)
    assert r == false
    assert PubsubListener.get(toxic_listener) == []

    state = :sys.get_state(pid)
    assert state.queues.moderator == [moderator.id]
    assert state.queues.contributor == [contributor.id]
    assert state.queues.vip == [vip.id]
    assert state.queues.standard == [standard.id]
    assert state.queues.toxic == [toxic.id]

    # We let one through (the bot) even though we were at capacity
    assert state.remaining_capacity == -1
    assert state.awaiting_release == []

    # Now we alter the capacity and see what happens
    send(pid, %{channel: "teiserver_telemetry", event: :data, data: %{
      client: %{
        total: 9
      }
    }})
    send(pid, :tick)

    # Give it a chance to dequeue
    :timer.sleep(100)

    state = :sys.get_state(pid)
    assert PubsubListener.get(moderator_listener) == [{:login_accepted, moderator.id}]
    assert PubsubListener.get(contributor_listener) == []
    assert PubsubListener.get(vip_listener) == []
    assert PubsubListener.get(standard_listener) == []
    assert PubsubListener.get(toxic_listener) == []

    assert state.queues.moderator == []
    assert state.queues.contributor == [contributor.id]
    assert state.queues.vip == [vip.id]
    assert state.queues.standard == [standard.id]
    assert state.queues.toxic == [toxic.id]

    Logger.warn("Dropping client count")

    # Now approve the rest of them
    # the toxic one will have to wait a bit longer though
    send(pid, %{channel: "teiserver_telemetry", event: :data, data: %{
      client: %{
        total: 4
      }
    }})
    state = :sys.get_state(pid)
    assert state.remaining_capacity == 6

    send(pid, :tick)

    # Give it a chance to dequeue
    :timer.sleep(400)

    state = :sys.get_state(pid)
    assert PubsubListener.get(moderator_listener) == []
    assert PubsubListener.get(contributor_listener) == [{:login_accepted, contributor.id}]
    assert PubsubListener.get(vip_listener) == [{:login_accepted, vip.id}]
    assert PubsubListener.get(standard_listener) == [{:login_accepted, standard.id}]
    assert PubsubListener.get(toxic_listener) == []

    assert state.queues.moderator == []
    assert state.queues.contributor == []
    assert state.queues.vip == []
    assert state.queues.standard == []
    assert state.queues.toxic == [toxic.id]
  end
end
