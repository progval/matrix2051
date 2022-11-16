# Matrix2051

*Join Matrix from your favorite IRC client*

Matrix2051 (or M51 for short) is an IRC server backed by Matrix. You can also see it
as an IRC bouncer that connects to Matrix homeservers instead of IRC servers.
In other words:

```
         IRC client
  (eg. weechat or hexchat)
             |
             |     IRC protocol
             v
         Matrix2051
             |
             |     Matrix protocol
             v
     Your Homeserver
     (eg. matrix.org)
```


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

## Major features

* Registration and password authentication
* Joining rooms
* Sending and receiving messages (supports formatting, multiline, highlights, replying, reacting to messages)
* Partial [IRCv3 ChatHistory](https://ircv3.net/specs/extensions/chathistory) support;
  enough for Gamja to work.
  [open chathistory issues](https://github.com/progval/matrix2051/milestone/3)
* [Partial](https://github.com/progval/matrix2051/issues/14) display name support

## Shortcomings

* [Direct chats are shown as regular channels, with random names](https://github.com/progval/matrix2051/issues/11)
* Does not "feel" like a real IRC network (yet?)
* User IDs and room names are uncomfortably long
* Loading the nick list of huge rooms like #matrix:matrix.org overloads some IRC clients
* IRC clients without [hex color](https://modern.ircdocs.horse/formatting.html#hex-color)
  support will see some garbage instead of colors. (Though colored text seems very uncommon on Matrix)
* IRC clients without advanced IRCv3 support work miss out on many features:
  [quote replies](https://github.com/progval/matrix2051/issues/16), reacts, display names.

## Screenshot

![screenshot of #synapse:matrix.org with Element and IRCCloud side-by-side](https://raw.githubusercontent.com/progval/matrix2051/assets/screenshot_element_irccloud.png)

Two notes on this screenshot:

* [Message edits](https://spec.matrix.org/v1.4/client-server-api/#event-replacements) are rendered with a fallback, as message edits are [not yet supported by IRC](https://github.com/ircv3/ircv3-specifications/pull/425),
* Replies on IRCCloud are rendered with colored icons, and clicking these icons opens a column showing the whole thread. Other clients may render replies differently.

## Usage

* Install system dependencies. For example, on Debian: `sudo apt install elixir erlang erlang-dev erlang-inets erlang-xmerl`
* Install Elixir dependencies: `mix deps.get`
* Run tests to make sure everything is working: `mix test`
* Run: `mix run matrix2051.exs`
* Connect a client to `localhost:2051`, with the following config:
  * no SSL/TLS
  * SASL username: your full matrix ID (`user:homeserver.example.org`)
  * SASL password: your matrix password

See below for extra instructions to work with web clients.

See `INSTALL.md` for a more production-oriented guide.

## End-to-end encryption

Matrix2051 does not support Matrix's end-to-end encryption (E2EE), but can optionally be used with [Pantalaimon](https://github.com/matrix-org/pantalaimon).

To do so, setup Pantalaimon locally, and configure `plaintextproxy=http://localhost:8009` as your IRC client's GECOS/"real name".

## Architecture

* `matrix2051.exs` starts M51.Application, which starts M51.Supervisor, which
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

### What IRC clients are supported?

In theory, any IRC client should work. In particular, I test it with
[Gamja](https://git.sr.ht/~emersion/gamja/), [IRCCloud](https://www.irccloud.com/),
[The Lounge](https://thelounge.chat/), and [WeeChat](https://weechat.org/).

Please open an issue if your client has any issue.

### What Matrix homeservers are supported?

In theory, any, as I wrote this by reading the Matrix specs.
In practice, this is only tested with [Synapse](https://github.com/matrix-org/synapse/).

A notable exception is registration, which uses a Synapse-specific API
as Matrix itself does not specify registration.

Please open an issue if you have any issue with your homeserver
(a dummy login/password I can use to connect to it would be appreciated).

### Are you planning to support features X, Y, ...?

At the time of writing, if both Matrix and IRC/IRCv3 support them, Matrix2051 likely will.
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

### I still have a question, how can I contact you?

Join [#matrix2051 at irc.interlinked.me](ircs://irc.interlinked.me/matrix2051).
(No I am not eating my own dogfood, I still prefer "native" IRC.)
