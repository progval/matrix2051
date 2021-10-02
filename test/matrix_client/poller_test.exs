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
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end
  end

  test "new room with disordered events" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      },
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "332 mynick:example.com #test:example.org :[test]\r\n"}
    end
  end

  test "renamed room" do
    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
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
                  ":server NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"}
    end
  end

  test "renamed room with name and topic" do
    state_events = [
      %{
        "content" => %{"topic" => "the topic"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_633_176_350_104,
        "sender" => "@nick:example.org",
        "type" => "m.room.topic"
      },
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name"
      },
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test1:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, "332 mynick:example.com #test1:example.org :[test] the topic\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line,
                  "333 mynick:example.com #test1:example.org nick:example.org :1633176350104\r\n"}
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
                  "333 mynick:example.com #test2:example.org nick:example.org :1633176350104\r\n"}
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
                  ":server NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"}
    end
  end

  test "existing members" do
    state_events = [
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.org",
        "type" => "m.room.member"
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "type" => "m.room.member"
      },
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg ==
                 {:line, "353 mynick:example.com = #test:example.org :mynick:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, "353 mynick:example.com = #test:example.org :nick2:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test:example.org\r\n"}
    end
  end

  test "new members" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.org",
        "type" => "m.room.member"
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "type" => "m.room.member"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":nick2:example.org JOIN :#test:example.org\r\n"}
    end
  end

  test "join_rules" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"join_rule" => "invite"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "type" => "m.room.join_rules"
      },
      %{
        "content" => %{"join_rule" => "public"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "type" => "m.room.join_rules"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":nick:example.org MODE #test:example.org :-i\r\n"}
    end

    receive do
      msg -> assert msg == {:line, ":nick:example.org MODE #test:example.org :+i\r\n"}
    end
  end

  test "message" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, ":nick:example.org PRIVMSG #test:example.org :first message\r\n"}
    end
  end

  test "message with tags" do
    Matrix2051.IrcConn.State.add_capabilities(:process_ircconn_state, [:server_time, :message_tags])
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias"
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message"
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events},
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    receive do
      msg -> assert msg == {:line, ":mynick:example.com JOIN :#test:example.org\r\n"}
    end

    receive do
      msg -> assert msg == {:line, "331 mynick:example.com :#test:example.org\r\n"}
    end

    receive do
      msg ->
        assert msg == {:line, "@msgid=$event1;server_time=2021-09-29T20:10:33.579Z :nick:example.org PRIVMSG #test:example.org :first message\r\n"}
    end
  end
end
