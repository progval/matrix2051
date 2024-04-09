FROM docker.io/alpine:3.19

ENV MIX_ENV=prod

RUN apk add --update --no-cache elixir

WORKDIR /app

COPY . /app

RUN mix deps.get
RUN mix release

CMD _build/prod/rel/matrix2051/bin/matrix2051 start
