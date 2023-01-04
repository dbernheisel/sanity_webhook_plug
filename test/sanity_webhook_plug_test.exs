defmodule SanityWebhookPlugTest do
  use ExUnit.Case
  use Plug.Test

  def secret, do: "test"
  def bad_secret, do: "test2"

  @good_payload Jason.encode!(%{"_id" => "resume"})
  @good_ts 1_633_519_811_129
  @good_hash "tLa470fx7qkLLEcMOcEUFuBbRSkGujyskxrNXcoh0N0"
  @good_signature "t=#{@good_ts},v1=#{@good_hash}"
  @opts [
    paths: ["/sanity"],
    halt_on_error: true,
    secret: "test"
  ]

  test "computes signature" do
    assert {:ok, computed} =
             SanityWebhookPlug.Signature.compute(@good_ts, @good_payload, @opts[:secret])

    assert computed == @good_hash

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    refute conn.halted
    assert conn.private.sanity_webhook_error == false
  end

  test "reads secret from MFA" do
    opts = Keyword.put(@opts, :secret, {__MODULE__, :bad_secret, []})

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(opts))

    assert conn.halted
    assert conn.private.sanity_webhook_error == "Sanity webhook signature does not match expected"

    opts = Keyword.put(@opts, :secret, {__MODULE__, :secret, []})

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(opts))

    refute conn.halted
    assert conn.private.sanity_webhook_error == false
  end

  test "halts on incorrect signature - timestamp" do
    bad_ts = 1_633_519_811_999
    bad_signature = "t=#{bad_ts},v1=#{@good_hash}"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    assert conn.halted
    assert conn.private.sanity_webhook_error == "Sanity webhook signature does not match expected"
  end

  test "halts on incorrect signature - old timestamp" do
    bad_ts = 123
    bad_signature = "t=#{bad_ts},v1=#{@good_hash}"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    assert conn.halted

    assert conn.private.sanity_webhook_error ==
             "Timestamp 123 is too early to be a valid Sanity webhook"
  end

  test "halts on incorrect signature - hash" do
    bad_signature = "t=#{@good_ts},v1=badhash"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    assert conn.halted
    assert conn.private.sanity_webhook_error == "Sanity webhook signature does not match expected"
  end

  test "halts on incorrect signature - payload" do
    bad_payload = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>

    conn =
      bad_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    assert conn.halted
    assert conn.private.sanity_webhook_error == "Sanity webhook signature does not match expected"
  end

  test "works with smaller read lengths" do
    opts = Keyword.put(@opts, :length, 8)

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(opts))

    refute conn.halted
  end

  test "does not halt with halt_on_error false" do
    bad_payload = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
    opts = Keyword.put(@opts, :halt_on_error, false)

    conn =
      bad_payload
      |> setup_conn(@good_signature)
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(opts))

    refute conn.halted
    assert conn.private.sanity_webhook_error == "Sanity webhook signature does not match expected"
  end

  test "halts on incorrect header" do
    conn =
      :post
      |> conn("/sanity", @good_payload)
      |> put_req_header("some-other-header", @good_signature)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("user-agent", "Sanity.io webhook delivery")
      |> put_req_header("accept-encoding", "gzip")
      |> SanityWebhookPlug.call(SanityWebhookPlug.init(@opts))

    assert conn.halted

    assert conn.private.sanity_webhook_error ==
             "Could not find valid Sanity webhook signature header"
  end

  defp setup_conn(payload, signature) do
    :post
    |> conn("/sanity", payload)
    |> put_req_header(SanityWebhookPlug.header(), signature)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("user-agent", "Sanity.io webhook delivery")
    |> put_req_header("accept-encoding", "gzip")
  end
end
