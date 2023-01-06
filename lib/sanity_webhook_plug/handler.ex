defmodule SanityWebhookPlug.Handler do
  @moduledoc """
  Behaviour for handling webhooks from SanityWebhookPlug
  """

  @doc "Handle authenticity-validated webhooks"
  @callback handle_event(Plug.Conn.t(), map()) :: Plug.Conn.t()

  @doc "Handle inauthentic or erroneous webhooks"
  @callback handle_error(Plug.Conn.t(), String.t() | term()) :: Plug.Conn.t()
end
