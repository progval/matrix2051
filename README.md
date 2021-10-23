# Matrix2051

An IRC server backed by Matrix. You can also see it as an IRC bouncer that
connects to Matrix homeservers instead of IRC servers.

Goals:

1. Make it easy for IRC users to join Matrix seamlessly
2. Support existing relay bots, to allows relays that behave better on IRC than
   existing IRC/Matrix bridges
3. Bleeding-edge IRCv3 implementation
4. Very easy to install. This means:
   1. as little configuration and database as possible (ideally zero)
   2. small set of depenencies.

Non-goals:

1. Being a hosted service (it would require spam countermeasures, and that's a lot of work).
2. TLS support (see previous point). Just run it on localhost. If you really need it to be remote, access it via a VPN or a reverse proxy.
3. Connecting to multiple accounts per IRC connection or to other protocols (à la [Bitlbee](https://www.bitlbee.org/)). This conflicts with goals 1 and 4.
4. Implementing any features not natively by **both** protocols (ie. no need for service bots that you interract with using PRIVMSG)

## Usage

* Install system dependencies. For example, on Debian: `sudo apt install elixir otp erlang-dev erlang-inets erlang-xmerl`
* Install Elixir dependencies: `mix deps.get`
* Run tests to make sure everything is working: `mix test`
* Run: `mix run --no-halt matrix2051.exs`
* Connect a client to `localhost:2051`, with the following config:
  * no SSL/TLS
  * SASL username: your full matrix ID (`user:homeserver.example.org`)
  * SASL password: your matrix password

See below for extra instructions to work with web clients.

## Roadmap

* [x] password authentication (using [SASL](https://ircv3.net/specs/extensions/sasl-3.1) on the IRC side)
* [x] registration (using the [draft/account-registration](https://github.com/ircv3/ircv3-specifications/pull/435) spec)
  * [x] on Synapse with no email verification
  * [ ] on Synapse with email verification
  * [ ] on other homeservers (when the Matrix spec defines how to)
* [x] retrieving the room list and joining clients to it
* [x] retrieving the member list and sending it to clients
* [x] support JOIN from clients
* [x] sending messages from IRC clients
* [x] receiving messages from Matrix
  * [x] basics
  * [x] split at 512 bytes
* [x] rewrite mentions/highlights
  * [x] Matrix -> IRC
  * [x] IRC -> Matrix
* [x] rewrite formatting and colors
  * [x] Matrix -> IRC
  * [x] IRC -> Matrix
* [x] show JOIN/PART events from other members
* [ ] figure out images / files
  * [x] Matrix -> IRC
  * [ ] IRC -> Matrix
* [x] [display names](https://github.com/ircv3/ircv3-specifications/pull/452)
* [ ] [chat history](https://ircv3.net/specs/extensions/chathistory)
  * [x] AFTER/AROUND/BEFORE with msgids
  * [ ] [AFTER/AROUND/BEFORE with timestamps](https://github.com/progval/matrix2051/issues/1)
  * [ ] BETWEEN
  * [ ] LATEST
* [x] [multiline](https://ircv3.net/specs/extensions/multiline) messages
  * [x] Matrix -> IRC
  * [x] IRC -> Matrix
* [x] [reacts](https://ircv3.net/specs/client-tags/react) ([Matrix draft spec](https://github.com/matrix-org/matrix-doc/pull/2677))
  * [x] Matrix -> IRC
  * [x] IRC -> Matrix
* [x] [replies](https://ircv3.net/specs/client-tags/reply)
  * [x] Matrix -> IRC
  * [x] IRC -> Matrix
* [ ] message edition/deletion
* [ ] support PART from IRC clients
* [ ] invites
* [ ] translate channel modes / room privileges
  * [ ] Matrix -> IRC
  * [ ] IRC -> Matrix
* [x] use [channel renaming](https://ircv3.net/specs/extensions/channel-rename)
  * [x] when the canonical name changes
  * [ ] in case of joining duplicate aliases of the same room?

In the far future:

* [ ] support authentication with non-password flows
* [ ] direct messages (it's really hard, in Matrix they are actual rooms you can
      invite people to)
* [ ] end-to-"end" encryption (Matrix2051 would be the end)
* [ ] Matrix P2P

## Architecture

* `matrix2051.exs` starts Matrix2051, which starts Matrix2051.Supervisor, which
  supervises:
  * `config.ex`: global config agent
  * `irc_server.ex`: a `DynamicSupervisor` that receives connections from IRC clients.

Every time `irc_server.ex` receives a connection, it spawns `irc_conn/supervisor.ex`,
which supervises:

* `irc_conn/state.ex`: stores the state of the connection
* `irc_conn/writer.ex`: genserver holding the socket and allowing
  to write lines to it (and batches of lines in the future)
* `irc_conn/handler.ex`: task busy-waiting on the incoming commands
  from the reader, answers to the simple ones, and dispatches more complex
  commands
* `matrix_client/state.ex`: keeps the state of the connection to a Matrix homeserver
* `matrix_client/client.ex`: handles one connection to a Matrix homeserver, as a single user
* `matrix_client/sender.ex`: sends events to the Matrix homeserver and with retries on failure
* `matrix_client/poller.ex`: repeatedly asks the Matrix homeserver for new events (including the initial sync)
* `irc_conn/reader.ex`: task busy-waiting on the incoming lines,
  and sends them to the handler

Utilities:

* `matrix/raw_client.ex`: low-level Matrix client / thin wrapper around HTTP requests
* `irc/command.ex`: IRC line manipulation, including "downgrading" them for clients
  that don't support some capabilities.
* `irc/word_wrap.ex`: generic line wrapping
* `format/`: Convert between IRC's formatting and `org.matrix.custom.html`
* `matrix_client/chat_history.ex`: fetches message history from Matrix, when requested
  by the IRC client

## Questions

### Why?

There are many great IRC clients, but I can't find a Matrix client I like.
Yet, some communities are moving from IRC to Matrix, so I wrote this so I can
join them with a comfortable client.

This is also a way to prototype the latest IRCv3 features easily,
and for me to learn the Matrix protocol.

### Are you planning support ... ?

At the time of writing, if both Matrix and IRC/IRCv3 support it, it likely will.
Take a look at [the list of open 'enhancement' issues](https://github.com/progval/matrix2051/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).

A notable exception is [direct messages](https://github.com/progval/matrix2051/issues/11),
because Matrix's model differs significantly from IRC's.

### Can I connect with a web client?

To connect web clients, you need a websocket gateway.
Matrix2051 was tested with [KiwiIRC's webircgateway](https://github.com/kiwiirc/webircgateway)
(try [this patch](https://github.com/kiwiirc/webircgateway/pull/91) if you need to run it on old Go versions).

Here is how you can configure it to connect to Matrix2051 with [Gamja](https://git.sr.ht/~emersion/gamja/):

```toml
[fileserving]
enabled = true
webroot = "/path/to/gamja"


[upstream.1]
hostname = "localhost"
port = 2051
tls = false
# Connection timeout in seconds
timeout = 20
# Throttle the lines being written by X per second
throttle = 100
webirc = ""
serverpassword = ""
```

### What's with the name?

This is a reference to [xkcd 1782](https://xkcd.com/1782/):

![2004: Our team stays in touch over IRC. 2010: Our team mainly uses Skype, but some of us prefer to stick to IRC. 2017: We've got almost everyone on Slack, But three people refuse to quit IRC and connect via gateway. 2051: All consciousnesses have merged with the Galactic Singularity, Except for one guy who insists on joining through his IRC client. "I just have it set up the way I want, okay?!" *Sigh*](https://imgs.xkcd.com/comics/team_chat.png)
