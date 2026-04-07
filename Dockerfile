FROM elixir:1.19.5 AS build
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
COPY apps ./apps

RUN mix deps.get --only prod
RUN mix deps.compile
RUN mix compile

FROM elixir:1.19.5
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY --from=build /app /app

RUN mkdir -p logs && chmod 777 logs

CMD ["mix", "run", "--no-halt"]
