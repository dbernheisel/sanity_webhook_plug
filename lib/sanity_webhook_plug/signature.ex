defmodule SanityWebhookPlug.Signature do
  @moduledoc """
  Compute and verify signatures from Sanity webhooks
  """

  @minimum_ts 1_609_459_200_000

  @type secret :: mfa() | (() -> String.t() | {:ok, String.t()}) | String.t()

  @doc """
  Verify a payload, timestamp, and secret against a computed signature
  """
  @spec verify(String.t(), pos_integer(), binary(), secret()) ::
          :ok | {:error, String.t(), String.t()}
  def verify(hash, ts, payload, secret) do
    case compute(ts, payload, secret) do
      {:ok, computed} ->
        if Plug.Crypto.secure_compare(hash, computed) do
          :ok
        else
          {:error, "Sanity webhook signature does not match expected", computed}
        end

      error ->
        error
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
    {:ok, :hmac |> :crypto.mac(:sha256, secret, "#{ts}.#{payload}") |> base64url_encode()}
  end

  def base64url_encode(payload) do
    payload
    |> Base.encode64(padding: false)
    |> String.replace("+", "-")
    |> String.replace("/", "_")
  end

  def base64url_decode(payload) do
    payload
    |> String.replace("_", "/")
    |> String.replace("-", "+")
    |> Base.decode64!(padding: false)
  end
end
