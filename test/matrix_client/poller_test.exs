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

  defp assert_line(line) do
    receive do
      msg -> assert msg == {:line, line}
    end
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
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
  end

  test "new room with disordered events" do
    state_events = [
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name",
        "unsigned" => %{}
      },
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("332 mynick:example.com #test:example.org :[test]\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
  end

  test "renamed room" do
    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line("331 mynick:example.com :#test1:example.org\r\n")
    assert_line("366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_line(":mynick:example.com!mynick@example.com JOIN :#test2:example.org\r\n")
    assert_line("331 mynick:example.com :#test2:example.org\r\n")
    assert_line("366 mynick:example.com #test2:example.org :End of /NAMES list\r\n")

    assert_line(
      ":mynick:example.com!mynick@example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"
    )

    assert_line(
      ":server NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"
    )
  end

  test "renamed room with name and topic" do
    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "type" => "m.room.name",
        "unsigned" => %{}
      },
      %{
        "content" => %{"topic" => "the topic"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_633_176_350_104,
        "sender" => "@nick:example.org",
        "type" => "m.room.topic",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line("332 mynick:example.com #test1:example.org :[test] the topic\r\n")
    assert_line("333 mynick:example.com #test1:example.org nick:example.org :1633176350\r\n")
    assert_line("366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_line(":mynick:example.com!mynick@example.com JOIN :#test2:example.org\r\n")
    assert_line("332 mynick:example.com #test2:example.org :[test] the topic\r\n")
    assert_line("333 mynick:example.com #test2:example.org nick:example.org :1633176350\r\n")
    assert_line("366 mynick:example.com #test2:example.org :End of /NAMES list\r\n")

    assert_line(
      ":mynick:example.com!mynick@example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"
    )

    assert_line(
      ":server NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"
    )
  end

  test "existing members" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      }
    ]

    Matrix2051.MatrixClient.Poller.handle_events(MockIrcSupervisor, self(), %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("353 mynick:example.com = #test:example.org :mynick:example.org\r\n")
    assert_line("353 mynick:example.com = #test:example.org :nick2:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
  end

  test "new members" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_line(":nick2:example.org!nick2@example.org JOIN :#test:example.org\r\n")
  end

  test "join_rules" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"join_rule" => "public"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "type" => "m.room.join_rules",
        "unsigned" => %{}
      },
      %{
        "content" => %{"join_rule" => "invite"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "type" => "m.room.join_rules",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_line(":nick:example.org!nick@example.org MODE #test:example.org :-i\r\n")
    assert_line(":nick:example.org!nick@example.org MODE #test:example.org :+i\r\n")
  end

  test "messages" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{"body" => "is using emotes", "msgtype" => "m.emote"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{"body" => "this is a notice", "msgtype" => "m.notice"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "body" => "cat.jpg",
          "msgtype" => "m.image",
          "url" => "mxc://matrix.org/rBCJlmPiZSqDvYoZGfAnkQrb"
        },
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "body" => "chat.jpg",
          "msgtype" => "m.image",
          "url" => "https://example.org/chat.jpg"
        },
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_line(":nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n")

    assert_line(
      ":nick:example.org!nick@example.org PRIVMSG #test:example.org :\x01ACTION is using emotes\x01\r\n"
    )

    assert_line(
      ":nick:example.org!nick@example.org NOTICE #test:example.org :this is a notice\r\n"
    )

    assert_line(
      ":nick:example.org!nick@example.org PRIVMSG #test:example.org :cat.jpg https://matrix.org/_matrix/media/r0/download/matrix.org/rBCJlmPiZSqDvYoZGfAnkQrb\r\n"
    )

    assert_line(
      ":nick:example.org!nick@example.org PRIVMSG #test:example.org :chat.jpg https://example.org/chat.jpg\r\n"
    )
  end

  test "message with tags" do
    Matrix2051.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :server_time,
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_line(
      "@msgid=$event1;time=2021-09-29T20:10:33.579Z :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )
  end

  test "echo-message" do
    Matrix2051.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :echo_message,
      :message_tags,
      :labeled_response
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event0",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{"transaction_id" => "m51-cl-Zm9v"}
      },
      %{
        "content" => %{"body" => "second message", "msgtype" => "m.text"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{"transaction_id" => "m51-gen-bar"}
      },
      %{
        "content" => %{"body" => "third message", "msgtype" => "m.text"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_line(
      "@label=foo;msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :second message\r\n"
    )

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test:example.org :third message\r\n"
    )
  end

  test "drops echos if echo-message not negotiated" do
    Matrix2051.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :message_tags,
      :labeled_response
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event0",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{"transaction_id" => "m51-cl-Zm9v"}
      },
      %{
        "content" => %{"body" => "second message", "msgtype" => "m.text"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{"transaction_id" => "m51-gen-bar"}
      },
      %{
        "content" => %{"body" => "third message", "msgtype" => "m.text"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test:example.org :third message\r\n"
    )
  end

  test "replies" do
    Matrix2051.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    timeline_events = [
      %{
        "content" => %{"body" => "first message", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "body" => "> <@nick:example.org> first message\n\nsecond message",
          "format" => "org.matrix.custom.html",
          "m.relates_to" => %{
            "m.in_reply_to" => %{
              "event_id" => "$event1"
            }
          },
          "msgtype" => "m.text"
        },
        "event_id" => "$event2",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
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

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line("331 mynick:example.com :#test:example.org\r\n")
    assert_line("366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :second message\r\n"
    )
  end
end
