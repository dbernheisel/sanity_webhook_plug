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
  path: ["/webhooks/sanity/bust_cache"]
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

- `:path` (required): The request paths to match against. Can either be a single
    route or a list of routes. eg: `["/webhooks/sanity/bust_cache"]` or `"/sanity"`
- `:halt_on_error` (default: `true`): Halt on error. If you want to handle errors
    yourself, provide `false` and handle the error in your controller action.
- `:secret`: The Sanity webhook secret. eg: `123abc`. Supplying an MFA tuple will
    be called at runtime, otherwise it will be compiled. If not set, it will
    obtain via config `Application.get_env(:sanity_webhook_plug, :webhook_secret)`.
    If supplying an MFA or function reference, it must return `{:ok, my_secret}`
- `:json_library`: JSON encoding library. When not supplied, it will use choose
    Phoenix's configured library, `Jason`, or `Poison`. Sanity requires
    JSON-encoded responses.

Options forwarded to `Plug.Conn.read_body/2`:

- `:length` - sets the number of bytes to read from the request at a time.
- `:read_length` - sets the amount of bytes to read at one time from the
    underlying socket to fill the chunk.
- `:read_timeout` - sets the timeout for each socket read.

### Handle Errors Yourself

If you want to handle errors yourself, you may configure the plug to
`halt_on_error: false` and handle the error yourself. If an error occurs, you
can get it with `SanityWebhookPlug.get_debug(conn)` and handle it yourself.

For example, here's a controller that checks the error:

```elixir
# assuming you have a route setup in your router to land in this controller.
def MyAppWeb.SanityController do
  use MyAppWeb, :controller
  require Logger

  def my_action(conn, params) do
    # ... do your normal thing
  end

  def action(conn, _) do
    debug = SanityWebhookPlug.debug(conn)
    if debug.error do
      # secret is present in the struct, but will not be present during inspect
      Logger.error("Sanity Webhook error: #{inspect(debug)}")
      Plug.Conn.resp(conn, 500, "Error: #{debug.error}")
    else
      apply(__MODULE__, action_name(conn), [conn, conn.params])
    end
  end
end
```
