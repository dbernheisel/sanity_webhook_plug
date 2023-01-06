<!-- badges -->
[![Hex.pm Version](http://img.shields.io/hexpm/v/sanity_webhook_plug)](https://hex.pm/packages/sanity_webhook_plug)
[![Hex docs](http://img.shields.io/badge/hex.pm-docs-blue.svg?style=flat)](https://hexdocs.pm/sanity_webhook_plug)
[![License](https://img.shields.io/hexpm/l/sanity_webhook_plug)](./LICENSE)

# Sanity Webhook Plug

You're reading the main branch's readme. Please visit
[hexdocs](https://hexdocs.pm/sanity_webhook_plug) for the latest published documentation.

<!-- MDOC !-->

SanityWebhookPlug is a Plug that verifies Sanity webhooks for your Elixir Plug
application. Designed to work with [Sanity GROQ-powered
webhooks](https://www.sanity.io/docs/webhooks)

## Installation

```elixir
def deps do
  [
    {:sanity_webhook_plug, "~> 0.1.0"}
  ]
end
```

## Usage

Use this plug in your endpoint:

```elixir
# If using Plug or Phoenix, place before `plug Plug.Parsers`
# For Phoenix apps, in lib/my_app_web/endpoint.ex:
plug SanityWebhookPlug,
  at: "/webhooks/sanity"
```

You may alternatively configure the secret in config, which will be read during
runtime:

```elixir
# in config/runtime.exs
config :sanity_webhook_plug,
  secret: System.get_env("SANITY_WEBHOOK_SECRET")
```

Verifying the signature requires reading the body, but its best to do this
before _interpreting_ the body into JSON or other parsed formats. Plug can
protect your system by limiting how much of body to read to prevent exhaustion.
Ideally, any of these settings you have for `Plug.Parsers` in your endpoint, you
should also have here for SanityWebhookPlug.

The body will be read into the plug conn's key `:params` which matches Phoenix
behavior.

By default, errors will be handled by the plug by responding with a 400 error
and a error message.

### Options:

- `:at` (required): The request path to match against. eg, `"/webhooks/sanity"`
- `:handler` (required): The controller-like module that responds to
    `handle_event/2` that is passed the conn and the params, and
    `handle_error/2` that is passed the conn and the error. The error may be an
    exception or a string.
- `:secret`: The Sanity webhook secret. eg: `123abc`. Supplying an MFA tuple will
    be called at runtime, otherwise it will be compiled. If not set, it will
    obtain via `Application.get_env(:sanity_webhook_plug, :webhook_secret)`.
    If supplying an MFA or function reference, it must return `{:ok, my_secret}`
    or a string.
- `:json_decoder`: JSON encoding library. When not supplied, it will use choose
    Phoenix's configured library, `Jason`, or `Poison`. Sanity requires
    JSON-encoded responses.

Options forwarded to `Plug.Conn.read_body/2`:

- `:length` - sets the number of bytes to read from the request at a time.
- `:read_length` - sets the amount of bytes to read at one time from the
    underlying socket to fill the chunk.
- `:read_timeout` - sets the timeout for each socket read.

### Handle Errors Yourself

If errors occur, you need to handle them yourself. You can inspect the context
of the webhook with `SanityWebhookPlug.get_debug(conn)`.


### Full example

For example, here's a controller:

```elixir
def MyAppWeb.SanityWebhookHandler do
  use MyAppWeb, :controller
  require Logger

  # handle known events
  def handle_event(conn, %{"_id" => id, "_type" => type}) do
    # ... do your normal thing
    json(conn, %{ok: "processed"})
  end

  # have a pass-thru handler
  def handle_event(conn, _params) do
    Logger.warn("Unhandled webhook #{inspect(params)}")
    json(conn, %{ok: "unhandled"})
  end

  # handle errors
  def handle_error(conn, error) do
    debug = SanityWebhookPlug.get_debug(conn)
    Logger.error("Sanity Webhook error: #{inspect(debug)}")
    conn
    |> put_status(500)
    |> json(%{error: inspect(error)})
  end
end
```
