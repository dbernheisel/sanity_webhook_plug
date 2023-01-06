defmodule SanityWebhookPlug.Signature do
  @moduledoc """
  Compute and verify signatures from Sanity webhooks
  """

  @minimum_ts 1_609_459_200_000

  @doc """
  Verify a payload, timestamp, and secret against a computed signature
  """
  @spec verify(String.t(), pos_integer(), binary(), String.t()) ::
          :ok | {:error, String.t(), String.t()}
  def verify(signature, ts, payload, secret) do
    case compute(ts, payload, secret) do
      {:ok, ^signature} -> :ok
      {:ok, computed} -> {:error, "Sanity webhook signature does not match expected", computed}
      error -> error
    end
  end

  @doc """
  Compute the signature for Sanity webhooks
  """
  @spec compute(pos_integer(), binary(), String.t()) ::
          {:ok, String.t()} | {:error, String.t(), nil}
  def compute(ts, _payload, _secret) when ts < @minimum_ts,
    do: {:error, "Timestamp #{ts} is too early to be a valid Sanity webhook", nil}

  def compute(ts, payload, secret) do
    {:ok,
     :hmac |> :crypto.mac(:sha256, secret, "#{ts}.#{payload}") |> Base.encode64(padding: false)}
  end
end
