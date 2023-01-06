defmodule SanityWebhookPlug.Handler do
  @moduledoc """
  Behaviour for handling webhooks from SanityWebhookPlug
  """

  @type params :: map()
  @type error :: String.t() | term()

  @doc "Handle authenticity-validated webhooks"
  @callback handle_event(Plug.Conn.t(), params()) :: Plug.Conn.t()

  @doc "Handle inauthentic or erroneous webhooks"
  @callback handle_error(Plug.Conn.t(), error()) :: Plug.Conn.t()
end
