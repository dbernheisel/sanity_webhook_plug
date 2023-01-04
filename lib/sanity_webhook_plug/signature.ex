defmodule SanityWebhookPlug.Signature do
  @moduledoc """
  Compute and verify signatures from Sanity webhooks
  """

  @minimum_ts 1_609_459_200_000

  @type secret :: mfa() | (() -> String.t()) | String.t()

  @doc """
  Verify a payload, timestamp, and secret against a computed signature
  """
  @spec verify(String.t(), pos_integer(), binary(), secret()) :: :ok | {:error, String.t()}
  def verify(signature, ts, payload, secret) do
    case compute(ts, payload, secret) do
      {:ok, ^signature} -> :ok
      {:ok, _} -> {:error, "Sanity webhook signature does not match expected"}
      error -> error
    end
  end

  @doc """
  Compute the signature for Sanity webhooks
  """
  @spec compute(pos_integer(), binary(), secret()) :: {:ok, String.t()} | {:error, String.t()}
  def compute(ts, _payload, _secret) when ts < @minimum_ts,
    do: {:error, "Timestamp #{ts} is too early to be a valid Sanity webhook"}

  def compute(ts, payload, {m, f, a}), do: compute(ts, payload, apply(m, f, a))
  def compute(ts, payload, secret) when is_function(secret), do: compute(ts, payload, secret.())

  def compute(ts, payload, nil) do
    case Application.get_env(:sanity_webhook_plug, :webhook_secret) do
      nil ->
        {:error, "No secret configured for SanityWebhookPlug"}

      secret ->
        compute(ts, payload, secret)
    end
  end

  def compute(ts, payload, secret) do
    {:ok,
     :hmac |> :crypto.mac(:sha256, secret, "#{ts}.#{payload}") |> Base.encode64(padding: false)}
  end
end
