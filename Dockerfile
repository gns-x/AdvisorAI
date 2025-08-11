# ---- Build Stage ----
FROM hexpm/elixir:1.15.7-erlang-26.2.1-alpine-3.18.4 AS build

# Install build dependencies
RUN apk add --no-cache build-base git npm

# Set build env vars
ENV MIX_ENV=prod

# Prepare app dir
WORKDIR /app

# Install Hex + Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files and install deps
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy the rest of the app
COPY . .

# Build assets
RUN mix assets.deploy

# Compile the app
RUN mix compile

# Build the release
RUN mix release

# ---- Release Stage ----
FROM alpine:3.18.4 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs
WORKDIR /app

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/advisor_ai .

ENV PHX_SERVER=true
ENV MIX_ENV=prod

# Expose port 4000
EXPOSE 4000

# Start the Phoenix app
ENTRYPOINT ["/app/bin/advisor_ai", "start"] 