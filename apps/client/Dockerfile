FROM elixir:1.19.5

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
COPY apps apps

RUN mix deps.get
RUN mix deps.compile

WORKDIR /app/apps/client

CMD ["mix", "run", "--no-halt"]
