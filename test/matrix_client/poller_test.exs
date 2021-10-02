defmodule Matrix2051.MatrixClient.PollerTest do
  use ExUnit.Case
  doctest Matrix2051.MatrixClient.Poller

  setup do
    start_supervised!({Matrix2051.IrcConn.State, {nil, nil}})
    |> Process.register(:process_ircconn_state)

    start_supervised!({Matrix2051.MatrixClient.State, []})
    |> Process.register(:process_matrix_state)

    start_supervised!({MockIrcConnWriter, {self()}})
    |> Process.register(MockIrcConnWriter)

    Matrix2051.IrcConn.State.set_nick(:process_ircconn_state, "mynick:example.com")

    :ok
  end

  test "no events" do
    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{})
  end

  test "new room" do
    events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end
  end

  test "new room with disordered events" do
    events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      },
      %{
        "content" => %{"name" => "test"},
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":nick:example.org TOPIC !testid:example.org :[test]\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end
  end

  test "renamed room" do
    events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias"
      },
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test1:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test1:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test2:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test2:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  ":mynick:example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  ":server NOTICE #test2:example.org :nick2:example.org renamed this room was renamed from #test1:example.org\r\n"}
    end
  end

  test "renamed room with name and topic" do
    events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias"
      },
      %{
        "content" => %{"topic" => "the topic"},
        "origin_server_ts" => 1_633_176_350_104,
        "sender" => "@nick:example.org",
        "type" => "m.room.topic"
      },
      %{
        "content" => %{"name" => "test"},
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name"
      },
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test1:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test1:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":nick:example.org TOPIC #test1:example.org :[test]\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, ":nick:example.org TOPIC #test1:example.org :[test] the topic\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test2:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, "332 mynick:example.com #test2:example.org :[test] the topic\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  ":mynick:example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  ":server NOTICE #test2:example.org :nick2:example.org renamed this room was renamed from #test1:example.org\r\n"}
    end
  end
end
