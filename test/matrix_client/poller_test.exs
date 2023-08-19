##
# Copyright (C) 2021-2023  Valentin Lorentz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

defmodule M51.MatrixClient.PollerTest do
  use ExUnit.Case
  doctest M51.MatrixClient.Poller

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    start_supervised!({M51.IrcConn.State, {self()}})
    |> Process.register(:process_ircconn_state)

    start_supervised!({M51.MatrixClient.State, {self()}})
    |> Process.register(:process_matrix_state)

    start_supervised!({MockMatrixClient, {self()}})
    |> Process.register(:process_matrix_client)

    start_supervised!({MockIrcConnWriter, {self()}})
    |> Process.register(MockIrcConnWriter)

    start_supervised!({M51.MatrixClient.RoomSupervisor, {self()}})

    M51.IrcConn.State.set_nick(:process_ircconn_state, "mynick:example.com")

    :ok
  end

  defp assert_line(line) do
    receive do
      msg -> assert msg == {:line, line}
    end
  end

  defp assert_last_line() do
    refute_received {:line, _}
  end

  # Sends the state needed to consider being joined to !testid:example.org with
  # canonical alias #test:example.org; and consumes the corresponding IRC lines
  defp joined_room() do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$joinevent",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_last_line()
  end

  test "no events" do
    M51.MatrixClient.Poller.handle_events(self(), true, %{})
    assert_last_line()

    M51.MatrixClient.Poller.handle_events(self(), false, %{})
    assert_last_line()
  end

  test "malformed event" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1"
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(
      ":server. NOTICE mynick:example.com :Malformed event: %{\"content\" => %{\"alias\" => \"#test:example.org\"}, \"event_id\" => \"$event1\"}\r\n"
    )

    assert_last_line()
  end

  test "malformed backlog event" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1"
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_last_line()
  end

  Enum.each([true, false], fn is_backlog ->
    test "encrypted event (is_backlog=#{is_backlog})" do
      timeline_events = [
        %{
          "content" => %{
            "algorithm" => "m.megolm.v1.aes-sha2",
            "ciphertext" => "blah",
            "sender_key" => "blih",
            "session_id" => "bluh"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_650_470_634_565,
          "sender" => "@someone:example.org",
          "type" => "m.room.encrypted",
          "unsigned" => %{}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), unquote(is_backlog), %{
        "rooms" => %{
          "join" => %{"!testid:example.org" => %{"timeline" => %{"events" => timeline_events}}}
        }
      })

      if !unquote(is_backlog) do
        assert_line(
          ":server. NOTICE !testid:example.org :someone:example.org sent an encrypted message\r\n"
        )
      end

      assert_last_line()
    end
  end)

  test "new room" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_last_line()
  end

  test "new room with disordered events" do
    state_events = [
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.name",
        "unsigned" => %{}
      },
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 332 mynick:example.com #test:example.org :[test]\r\n")
    assert_line(":server. 353 mynick:example.com = #test:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_last_line()
  end

  test "renamed room" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :channel_rename,
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test1:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test1:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event2 :nick2:example.org!nick2@example.org RENAME #test1:example.org #test2:example.org :Canonical alias changed\r\n"
    )

    assert_last_line()
  end

  test "renamed room fallback" do
    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test1:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test1:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_last_line()

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test2:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test2:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test2:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test2:example.org :End of /NAMES list\r\n")

    assert_line(
      ":mynick:example.com!mynick@example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"
    )

    assert_line(
      ":server. NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"
    )

    assert_last_line()
  end

  test "renamed room fallback with name and topic" do
    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"name" => "test"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_975,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.name",
        "unsigned" => %{}
      },
      %{
        "content" => %{"topic" => "the topic"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_633_176_350_104,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.topic",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 332 mynick:example.com #test1:example.org :[test] the topic\r\n")

    assert_line(
      ":server. 333 mynick:example.com #test1:example.org nick:example.org :1633176350\r\n"
    )

    assert_line(":server. 353 mynick:example.com = #test1:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_last_line()

    timeline_events = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test2:example.org\r\n")
    assert_line(":server. 332 mynick:example.com #test2:example.org :[test] the topic\r\n")

    assert_line(
      ":server. 333 mynick:example.com #test2:example.org nick:example.org :1633176350\r\n"
    )

    assert_line(":server. 353 mynick:example.com = #test2:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test2:example.org :End of /NAMES list\r\n")

    assert_line(
      ":mynick:example.com!mynick@example.com PART #test1:example.org :nick2:example.org renamed this room to #test2:example.org\r\n"
    )

    assert_line(
      ":server. NOTICE #test2:example.org :nick2:example.org renamed this room from #test1:example.org\r\n"
    )

    assert_last_line()
  end

  Enum.each([false, true], fn userhost_in_names ->
    test "existing members (userhost_in_names=#{userhost_in_names})" do
      if unquote(userhost_in_names) do
        M51.IrcConn.State.add_capabilities(:process_ircconn_state, [:userhost_in_names])
      end

      state_events = [
        %{
          "content" => %{"alias" => "#test:example.org"},
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_644_251_623,
          "sender" => "@nick:example.org",
          "state_key" => "",
          "type" => "m.room.canonical_alias",
          "unsigned" => %{}
        },
        %{
          "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
          "event_id" => "$event2",
          "origin_server_ts" => 1_632_648_797_438,
          "sender" => "nick2:example.org",
          "state_key" => "nick2:example.org",
          "type" => "m.room.member",
          "unsigned" => %{}
        },
        %{
          "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
          "event_id" => "$event3",
          "origin_server_ts" => 1_632_648_797_438,
          "sender" => "mynick:example.com",
          "state_key" => "mynick:example.com",
          "type" => "m.room.member",
          "unsigned" => %{}
        },
        %{
          "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
          "event_id" => "$event4",
          "origin_server_ts" => 1_632_648_797_438,
          "sender" => "malicious nick:for example.org",
          "state_key" => "malicious nick:for example.org",
          "type" => "m.room.member",
          "unsigned" => %{}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), true, %{
        "rooms" => %{
          "join" => %{"!testid:example.org" => %{"state" => %{"events" => state_events}}}
        }
      })

      assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
      assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

      if unquote(userhost_in_names) do
        assert_line(
          ":server. 353 mynick:example.com = #test:example.org :malicious\\snick:for\\sexample.org!malicious\\snick@for\\sexample.org mynick:example.com!mynick@example.com nick2:example.org!nick2@example.org\r\n"
        )
      else
        assert_line(
          ":server. 353 mynick:example.com = #test:example.org :malicious\\snick:for\\sexample.org mynick:example.com nick2:example.org\r\n"
        )
      end

      assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
      assert_last_line()
    end
  end)

  test "new room with draft/no-implicit-names" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :no_implicit_names
    ])

    state_events1 = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    state_events2 = [
      %{
        "content" => %{"alias" => "#test2:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid1:example.org" => %{"state" => %{"events" => state_events1}}
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test1:example.org :No topic is set\r\n")

    assert_last_line()

    # Need to send more messages from the poller to make sure there really isn't any
    # message left

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid2:example.org" => %{"state" => %{"events" => state_events2}}
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test2:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test2:example.org :No topic is set\r\n")

    assert_last_line()
  end

  test "invalid room renaming" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :channel_rename,
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test1:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test1:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_last_line()

    timeline_events = [
      %{
        "content" => %{"alias" => "#invalidalias:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"body" => "my message", "msgtype" => "m.text"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :server. NOTICE #test1:example.org :Invalid room renaming to #invalidalias:example.org (sent by nick2:example.org)\r\n"
    )

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test1:example.org :my message\r\n"
    )

    assert_last_line()
  end

  test "re-joined room" do
    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "state_key" => "nick2:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    # first welcome
    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

    assert_line(
      ":server. 353 mynick:example.com = #test:example.org :mynick:example.com nick2:example.org\r\n"
    )

    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_last_line()

    timeline_events = [
      %{
        "content" => %{"membership" => "leave"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com PART :#test:example.org\r\n")

    # second welcome
    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

    assert_line(
      ":server. 353 mynick:example.com = #test:example.org :mynick:example.com nick2:example.org\r\n"
    )

    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_last_line()
  end

  test "room name suppression" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :channel_rename,
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test1:example.org"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick1:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test1:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test1:example.org :No topic is set\r\n")
    assert_line(":server. 353 mynick:example.com = #test1:example.org :mynick:example.com\r\n")
    assert_line(":server. 366 mynick:example.com #test1:example.org :End of /NAMES list\r\n")
    assert_last_line()

    timeline_events = [
      %{
        "content" => %{},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick2:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"body" => "my message", "msgtype" => "m.text"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test1:example.org :my message\r\n"
    )

    assert_last_line()
  end

  test "new members" do
    joined_room()

    timeline_events = [
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.org",
        "state_key" => "nick2:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.org",
        "state_key" => "mynick:example.org",
        "type" => "m.room.member",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":nick2:example.org!nick2@example.org JOIN :#test:example.org\r\n")
    assert_line(":mynick:example.org!mynick@example.org JOIN :#test:example.org\r\n")
    assert_last_line()
  end

  test "leaving members" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.com",
        "state_key" => "nick2:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"membership" => "ban"},
        "event_id" => "$event3",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "nick2:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"membership" => "leave"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "nick2:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"membership" => "leave"},
        "event_id" => "$event5",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "Name 2", "membership" => "join"},
        "event_id" => "$event6",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "nick2:example.com",
        "state_key" => "nick2:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"avatar_url" => nil, "displayname" => "My Name", "membership" => "join"},
        "event_id" => "$event7",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"membership" => "leave", "reason" => "I don't like you"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "nick2:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      },
      %{
        "content" => %{"membership" => "leave", "reason" => "bye"},
        "event_id" => "$event5",
        "origin_server_ts" => 1_632_648_797_438,
        "sender" => "mynick:example.com",
        "state_key" => "mynick:example.com",
        "type" => "m.room.member",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line("@msgid=$event1 :nick2:example.com!nick2@example.com JOIN :#test:example.org\r\n")

    assert_line(
      "@msgid=$event3 :mynick:example.com!mynick@example.com MODE #test:example.org +b :nick2:example.com!*@*\r\n"
    )

    assert_line(
      "@msgid=$event4 :mynick:example.com!mynick@example.com KICK #test:example.org :nick2:example.com\r\n"
    )

    assert_line(
      "@msgid=$event5 :mynick:example.com!mynick@example.com PART :#test:example.org\r\n"
    )

    assert_line("@msgid=$event6 :nick2:example.com!nick2@example.com JOIN :#test:example.org\r\n")

    assert_line(
      "@msgid=$event7 :mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n"
    )

    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

    assert_line(
      ":server. 353 mynick:example.com = #test:example.org :mynick:example.com nick2:example.com\r\n"
    )

    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")

    assert_line(
      "@msgid=$event4 :mynick:example.com!mynick@example.com KICK #test:example.org nick2:example.com :I don't like you\r\n"
    )

    assert_line(
      "@msgid=$event5 :mynick:example.com!mynick@example.com PART #test:example.org :bye\r\n"
    )

    assert_last_line()
  end

  test "join_rules" do
    joined_room()

    timeline_events = [
      %{
        "content" => %{"join_rule" => "public"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.join_rules",
        "unsigned" => %{}
      },
      %{
        "content" => %{"join_rule" => "invite"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_803,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.join_rules",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":nick:example.org!nick@example.org MODE #test:example.org :-i\r\n")
    assert_line(":nick:example.org!nick@example.org MODE #test:example.org :+i\r\n")
    assert_last_line()
  end

  for is_backlog <- [true, false] do
    test "invited to room with no alias (is_backlog=#{is_backlog})" do
      state_events = [
        %{
          "content" => %{
            "creator" => "@inviter:example.org",
            "room_version" => "6"
          },
          "event_id" => "$event2",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "",
          "type" => "m.room.create"
        },
        %{
          "content" => %{"join_rule" => "invite"},
          "event_id" => "$event3",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "",
          "type" => "m.room.join_rules"
        },
        %{
          "content" => %{"displayname" => "invited user", "membership" => "join"},
          "event_id" => "$event4",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "@inviter:example.org",
          "type" => "m.room.member"
        },
        %{
          "content" => %{
            "displayname" => "valtest",
            "is_direct" => true,
            "membership" => "invite"
          },
          "event_id" => "$event6",
          "origin_server_ts" => 1_634_330_707_082,
          "sender" => "@inviter:example.org",
          "state_key" => "invited:example.com",
          "type" => "m.room.member",
          "unsigned" => %{"age" => 54}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), unquote(is_backlog), %{
        "rooms" => %{
          "invite" => %{
            "!testid:example.org" => %{
              "invite_state" => %{"events" => state_events}
            }
          }
        }
      })

      if !unquote(is_backlog) do
        assert_line(
          ":inviter:example.org!inviter@example.org INVITE mynick:example.com :!testid:example.org\r\n"
        )
      end

      assert_last_line()
    end
  end

  for is_backlog <- [true, false] do
    test "someone else invited to room with canonical alias (is_backlog=#{is_backlog})" do
      state_events = [
        %{
          "content" => %{
            "creator" => "@inviter:example.org",
            "room_version" => "6"
          },
          "event_id" => "$event2",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "",
          "type" => "m.room.create"
        },
        %{
          "content" => %{"join_rule" => "invite"},
          "event_id" => "$event3",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "",
          "type" => "m.room.join_rules"
        },
        %{
          "content" => %{"displayname" => "invited user", "membership" => "join"},
          "event_id" => "$event4",
          "sender" => "@inviter:example.org",
          "origin_server_ts" => 1_634_330_707_082,
          "state_key" => "@inviter:example.org",
          "type" => "m.room.member"
        },
        %{
          "content" => %{"alias" => "#test:example.org"},
          "event_id" => "$event5",
          "origin_server_ts" => 1_632_644_251_623,
          "sender" => "@nick:example.org",
          "state_key" => "",
          "type" => "m.room.canonical_alias",
          "unsigned" => %{}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), true, %{
        "rooms" => %{
          "join" => %{
            "!testid:example.org" => %{
              "state" => %{"events" => state_events}
            }
          }
        }
      })

      assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
      assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

      assert_line(
        ":server. 353 mynick:example.com = #test:example.org :inviter:example.org mynick:example.com\r\n"
      )

      assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
      assert_last_line()

      timeline_events = [
        %{
          "content" => %{
            "displayname" => "valtest",
            "is_direct" => true,
            "membership" => "invite"
          },
          "event_id" => "$event6",
          "origin_server_ts" => 1_634_330_707_082,
          "sender" => "@inviter:example.org",
          "state_key" => "invited:example.com",
          "type" => "m.room.member",
          "unsigned" => %{"age" => 54}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), unquote(is_backlog), %{
        "rooms" => %{
          "join" => %{
            "!testid:example.org" => %{
              "timeline" => %{"events" => timeline_events}
            }
          }
        }
      })

      if !unquote(is_backlog) do
        assert_line(
          ":inviter:example.org!inviter@example.org INVITE invited:example.com :#test:example.org\r\n"
        )
      end

      assert_last_line()
    end
  end

  Enum.each([true, false], fn is_backlog ->
    test "messages (is_backlog=#{is_backlog})" do
      if unquote(is_backlog) do
        MockHTTPoison
        |> expect(:get, 0, fn url ->
          assert url == "https://matrix.org/.well-known/matrix/client"

          {:ok,
           %HTTPoison.Response{
             status_code: 200,
             body: ~s({"m.homeserver": {"base_url": "https://matrix-client.matrix.org"}})
           }}
        end)
      else
        MockHTTPoison
        |> expect(:get, 5, fn url ->
          assert url == "https://matrix.org/.well-known/matrix/client"

          {:ok,
           %HTTPoison.Response{
             status_code: 200,
             body: ~s({"m.homeserver": {"base_url": "https://matrix-client.matrix.org"}})
           }}
        end)
      end

      joined_room()

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
          "content" => %{
            "body" => "\x01DCC SEND STARTKEYLOGGER 0 0 0\x01",
            "msgtype" => "m.message"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "\x01ACTION is pretending to use emotes\x01",
            "msgtype" => "m.message"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "\x01ACTION is pretending to use emotes again",
            "msgtype" => "m.message"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "\x01\x01ACTION is pretending to use emotes again again\x01\x01",
            "msgtype" => "m.message"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "\x01ACTION is nesting emotes\x01",
            "msgtype" => "m.emote"
          },
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
            "body" => "this is my cat",
            "msgtype" => "m.image",
            "filename" => "cat.jpg",
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
            "body" => "cat.jpg",
            "msgtype" => "m.image",
            "filename" => "cat.jpg",
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
            "body" => "hello",
            "msgtype" => "m.file",
            "url" => "mxc://matrix.org/FHyPlCeYUSFFxlgbQYZmoEoe",
            "filename" => "blah.txt"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "hello",
            "msgtype" => "m.file",
            "url" => "mxc://matrix.org/FHyPlCeYUSFFxlgbQYZmoEoe"
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
        },
        %{
          "content" => %{
            "body" => "\x01DCC SEND STARTKEYLOGGER 0 0 0\x01",
            "msgtype" => "m.image",
            "url" => "https://example.org/chat.jpg"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "image.jpg",
            "msgtype" => "m.image",
            "url" => "https://example.org/chat.jpg"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.room.message",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "Landing",
            "url" => "mxc://matrix.org/sHhqkFCvSkFwtmvtETOtKnLP"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.sticker",
          "unsigned" => %{}
        },
        %{
          "content" => %{
            "body" => "\x01DCC SEND STARTKEYLOGGER 0 0 0\x01",
            "url" => "mxc://matrix.org/sHhqkFCvSkFwtmvtETOtKnLP"
          },
          "event_id" => "$event1",
          "origin_server_ts" => 1_632_946_233_579,
          "sender" => "@nick:example.org",
          "type" => "m.sticker",
          "unsigned" => %{}
        }
      ]

      M51.MatrixClient.Poller.handle_events(self(), unquote(is_backlog), %{
        "rooms" => %{
          "join" => %{
            "!testid:example.org" => %{
              "timeline" => %{"events" => timeline_events}
            }
          }
        }
      })

      if !unquote(is_backlog) do
        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :\x01ACTION is using emotes\x01\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :DCC SEND STARTKEYLOGGER 0 0 0\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :ACTION is pretending to use emotes\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :ACTION is pretending to use emotes again\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :ACTION is pretending to use emotes again again\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :\x01ACTION ACTION is nesting emotes\x01\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org NOTICE #test:example.org :this is a notice\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :cat.jpg https://matrix-client.matrix.org/_matrix/media/r0/download/matrix.org/rBCJlmPiZSqDvYoZGfAnkQrb\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :this is my cat https://matrix-client.matrix.org/_matrix/media/r0/download/matrix.org/rBCJlmPiZSqDvYoZGfAnkQrb/cat.jpg\r\n"
        )

        # body is the same as file name -> it's useless
        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :https://matrix-client.matrix.org/_matrix/media/r0/download/matrix.org/rBCJlmPiZSqDvYoZGfAnkQrb/cat.jpg\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :hello https://matrix-client.matrix.org/_matrix/media/r0/download/matrix.org/FHyPlCeYUSFFxlgbQYZmoEoe/blah.txt\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :hello https://matrix-client.matrix.org/_matrix/media/r0/download/matrix.org/FHyPlCeYUSFFxlgbQYZmoEoe\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :chat.jpg https://example.org/chat.jpg\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :DCC SEND STARTKEYLOGGER 0 0 0\x01 https://example.org/chat.jpg\r\n"
        )

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :https://example.org/chat.jpg\r\n"
        )

        assert_line(":nick:example.org!nick@example.org PRIVMSG #test:example.org :Landing\r\n")

        assert_line(
          ":nick:example.org!nick@example.org PRIVMSG #test:example.org :DCC SEND STARTKEYLOGGER 0 0 0\r\n"
        )
      end

      assert_last_line()
    end
  end)

  test "message with tags" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :server_time,
      :message_tags
    ])

    joined_room()

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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1;time=2021-09-29T20:10:33.579Z :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_last_line()
  end

  test "message with display-name" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :message_tags
    ])

    state_events = [
      %{
        "content" => %{"alias" => "#test:example.org"},
        "event_id" => "$event2",
        "origin_server_ts" => 1_632_644_251_623,
        "sender" => "@nick:example.org",
        "state_key" => "",
        "type" => "m.room.canonical_alias",
        "unsigned" => %{}
      },
      %{
        "content" => %{"displayname" => "cool user", "membership" => "join"},
        "event_id" => "$event3",
        "sender" => "@nick:example.org",
        "origin_server_ts" => 1_632_644_251_623,
        "state_key" => "@nick:example.org",
        "type" => "m.room.member"
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), true, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "state" => %{"events" => state_events}
          }
        }
      }
    })

    assert_line(":mynick:example.com!mynick@example.com JOIN :#test:example.org\r\n")
    assert_line(":server. 331 mynick:example.com #test:example.org :No topic is set\r\n")

    assert_line(
      ":server. 353 mynick:example.com = #test:example.org :mynick:example.com nick:example.org\r\n"
    )

    assert_line(":server. 366 mynick:example.com #test:example.org :End of /NAMES list\r\n")
    assert_last_line()

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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@+draft/display-name=cool\\suser;msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_last_line()
  end

  test "echo-message" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :echo_message,
      :message_tags,
      :labeled_response
    ])

    joined_room()

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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@label=foo;msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :second message\r\n"
    )

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test:example.org :third message\r\n"
    )

    assert_last_line()
  end

  test "drops echos if echo-message not negotiated" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :message_tags,
      :labeled_response
    ])

    joined_room()

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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event3 :nick:example.org!nick@example.org PRIVMSG #test:example.org :third message\r\n"
    )

    assert_last_line()
  end

  test "replies" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags
    ])

    joined_room()

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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :second message\r\n"
    )

    assert_last_line()
  end

  test "rich replies" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags
    ])

    joined_room()

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
          "formatted_body" =>
            "<mx-reply><blockquote><a href=\"https://matrix.to/#/!blahblah:matrix.org/$event1\">In reply to</a> <a href=\"https://matrix.to/#/@nick:example.org\">@nick:example.org</a><br>first message</blockquote></mx-reply>second <b>message</b>",
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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :second \x02message\x02\r\n"
    )

    assert_last_line()
  end

  test "reactions" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags
    ])

    joined_room()

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
          "m.relates_to" => %{
            "rel_type" => "m.annotation",
            "event_id" => "$event1",
            "key" => "👍"
          }
        },
        "event_id" => "$event2",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@nick2:example.org",
        "type" => "m.reaction",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@+draft/react=👍;+draft/reply=$event1;msgid=$event2 :nick2:example.org!nick2@example.org TAGMSG :#test:example.org\r\n"
    )

    assert_last_line()
  end

  test "multiline" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :batch,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\nb", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org BATCH +ERSXMZLOOQYQ draft/multiline :#test:example.org\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :b\r\n"
    )

    assert_line("BATCH :-ERSXMZLOOQYQ\r\n")
    assert_last_line()
  end

  test "multiline with invalid event_id" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :batch,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\nb", "msgtype" => "m.text"},
        "event_id" => 42,
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    batch_id =
      receive do
        msg ->
          {:line, line} = msg
          {:ok, parsed_msg} = M51.Irc.Command.parse(line)
          [<<"+", batch_id::binary>> | _] = parsed_msg.params

          assert msg ==
                   {:line,
                    ":nick:example.org!nick@example.org BATCH +#{batch_id} draft/multiline :#test:example.org\r\n"}

          batch_id
      end

    assert_line(
      "@batch=#{batch_id} :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(
      "@batch=#{batch_id} :nick:example.org!nick@example.org PRIVMSG #test:example.org :b\r\n"
    )

    assert_line("BATCH :-#{batch_id}\r\n")
    assert_last_line()
  end

  test "replies and multiline" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :batch,
      :account,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\nb", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "body" => "> <@pinkie:matrix.org> a\n> b\n\nc\nd",
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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org BATCH +ERSXMZLOOQYQ draft/multiline :#test:example.org\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :b\r\n"
    )

    assert_line("BATCH :-ERSXMZLOOQYQ\r\n")

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :nick:example.org!nick@example.org BATCH +ERSXMZLOOQZA draft/multiline :#test:example.org\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQZA :nick:example.org!nick@example.org PRIVMSG #test:example.org :c\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQZA :nick:example.org!nick@example.org PRIVMSG #test:example.org :d\r\n"
    )

    assert_line("BATCH :-ERSXMZLOOQZA\r\n")
    assert_last_line()
  end

  test "multiline-concat" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :batch,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => String.duplicate("abcde ", 100), "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org BATCH +ERSXMZLOOQYQ draft/multiline :#test:example.org\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :" <>
        String.duplicate("abcde ", 74) <> "\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ;draft/multiline-concat :nick:example.org!nick@example.org PRIVMSG #test:example.org :" <>
        String.duplicate("abcde ", 26) <> "\r\n"
    )

    assert_line("BATCH :-ERSXMZLOOQYQ\r\n")
    assert_last_line()
  end

  test "multiline and multiline-concat" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :batch,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\n" <> String.duplicate("abcde ", 100), "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org BATCH +ERSXMZLOOQYQ draft/multiline :#test:example.org\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ :nick:example.org!nick@example.org PRIVMSG #test:example.org :" <>
        String.duplicate("abcde ", 74) <> "\r\n"
    )

    assert_line(
      "@batch=ERSXMZLOOQYQ;draft/multiline-concat :nick:example.org!nick@example.org PRIVMSG #test:example.org :" <>
        String.duplicate("abcde ", 26) <> "\r\n"
    )

    assert_line("BATCH :-ERSXMZLOOQYQ\r\n")
    assert_last_line()
  end

  test "downgraded multiline" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\nb", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(":nick:example.org!nick@example.org PRIVMSG #test:example.org :b\r\n")
    assert_last_line()
  end

  test "replies and downgraded multiline" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :account,
      :message_tags
    ])

    joined_room()

    timeline_events = [
      %{
        "content" => %{"body" => "a\nb", "msgtype" => "m.text"},
        "event_id" => "$event1",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "body" => "> <@pinkie:matrix.org> a\n> b\n\nc\nd",
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

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :a\r\n"
    )

    assert_line(":nick:example.org!nick@example.org PRIVMSG #test:example.org :b\r\n")

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :nick:example.org!nick@example.org PRIVMSG #test:example.org :c\r\n"
    )

    assert_line(
      "@+draft/reply=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :d\r\n"
    )

    assert_last_line()
  end

  test "redacted message" do
    joined_room()

    redacted_because = %{
      "event_id" => "$event3",
      "origin_server_ts" => 1_633_587_552_816,
      "redacts" => "$event1",
      "sender" => "@censor:example.org",
      "type" => "m.room.redaction",
      "unsigned" => %{},
      "user_id" => "@censor:example.org"
    }

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
        "content" => %{},
        "event_id" => "$event2",
        "origin_server_ts" => 1_633_586_313_381,
        "redacted_because" => redacted_because,
        "room_id" => "!BIDAeUqYWNCjRLhRdj:matrix.org",
        "sender" => "@censor:example.org",
        "type" => "m.room.message",
        "unsigned" => %{
          "redacted_because" => redacted_because,
          "redacted_by" => "$event2"
        },
        "user_id" => "@censor:example.org"
      },
      %{
        "content" => %{"body" => "second message", "msgtype" => "m.text"},
        "event_id" => "$event4",
        "origin_server_ts" => 1_632_946_233_579,
        "sender" => "@nick:example.org",
        "type" => "m.room.message",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(":nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n")
    # We'll probably see the m.room.redaction message later, so we can simply ignore this one.
    assert_line(
      ":nick:example.org!nick@example.org PRIVMSG #test:example.org :second message\r\n"
    )

    assert_last_line()
  end

  test "message redaction" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags,
      :message_redaction
    ])

    joined_room()

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
        "content" => %{},
        "event_id" => "$event2",
        "redacts" => "$event1",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@admin:example.org",
        "type" => "m.room.redaction",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "reason" => "Redacting again!"
        },
        "event_id" => "$event3",
        "redacts" => "$event1",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@admin:example.org",
        "type" => "m.room.redaction",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@msgid=$event2 :admin:example.org!admin@example.org REDACT #test:example.org :$event1\r\n"
    )

    assert_line(
      "@msgid=$event3 :admin:example.org!admin@example.org REDACT #test:example.org $event1 :Redacting again!\r\n"
    )

    assert_last_line()
  end

  test "message redaction fallback" do
    M51.IrcConn.State.add_capabilities(:process_ircconn_state, [
      :multiline,
      :message_tags
    ])

    joined_room()

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
        "content" => %{},
        "event_id" => "$event2",
        "redacts" => "$event1",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@admin:example.org",
        "type" => "m.room.redaction",
        "unsigned" => %{}
      },
      %{
        "content" => %{
          "reason" => "Redacting again!"
        },
        "event_id" => "$event3",
        "redacts" => "$event1",
        "origin_server_ts" => 1_633_808_172_505,
        "sender" => "@admin:example.org",
        "type" => "m.room.redaction",
        "unsigned" => %{}
      }
    ]

    M51.MatrixClient.Poller.handle_events(self(), false, %{
      "rooms" => %{
        "join" => %{
          "!testid:example.org" => %{
            "timeline" => %{"events" => timeline_events}
          }
        }
      }
    })

    assert_line(
      "@msgid=$event1 :nick:example.org!nick@example.org PRIVMSG #test:example.org :first message\r\n"
    )

    assert_line(
      "@+draft/reply=$event1;msgid=$event2 :server. NOTICE #test:example.org :admin:example.org deleted an event\r\n"
    )

    assert_line(
      "@+draft/reply=$event1;msgid=$event3 :server. NOTICE #test:example.org :admin:example.org deleted an event: Redacting again!\r\n"
    )

    assert_last_line()
  end
end
