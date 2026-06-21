# Installing Matrix2051

This document explains how to deploy Matrix2051 in a production environment.

The commands below require Elixir >= 1.9 (the version that introduced `mix release`).
If you need to use an older release, refer to the commands in `README.md`.
They won't work as well, but it's the best we can.

## Install dependencies

```
sudo apt install elixir erlang erlang-dev erlang-inets erlang-xmerl
MIX_ENV=prod mix deps.get
```

## Compilation

```
MIX_ENV=prod mix release
```

## Test run

You can now run it with this command (instead of `mix run matrix2051.exs`):

```
_build/prod/rel/matrix2051/bin/matrix2051 start
```

Make sure it listens to connections, then press Ctrl-C twice to stop it.

## Deployment

You can now run it with your favorite init.

For example, with systemd and assuming you cloned the repository in `/opt/matrix2051`:

```
[Unit]
Description=Matrix2051, a Matrix gateway for IRC
After=network.target

[Service]
Type=simple
ExecStart=/opt/matrix2051/_build/prod/rel/matrix2051/bin/matrix2051 start
ExecStop=/opt/matrix2051/_build/prod/rel/matrix2051/bin/matrix2051 stop
Restart=always
SyslogIdentifier=Matrix2051
Environment=HOME=/tmp/
DynamicUser=true

[Install]
WantedBy=multi-user.target
```

This does the following:

* Set `$HOME` to a writeable directory (requirement of `erlexec`)
* Create a temporary user to run the process as
* Makes sure the process can't write any file on the system or gain new capabilities
  (implied by `DynamicUser=true`)

# Running matrix2051 as a container

Alternatively a Containerfile is provided as well for convenience. The
image can be built with either [podman](https://podman.io/) or
[docker](https://www.docker.com/).

To build it:

```
podman build -t matrix2051 --file dist/Containerfile .
```

To run it:

```
podman run --publish 2051:2051 --interactive matrix2051
```

Alternatively, with docker to build it:

```
cd /path/to/matrix2051
cp dist/Containerfile Dockerfile
docker build -t matrix2051 .
```

To run it:

```
docker run -p 2051:2051 -it matrix2051
```
