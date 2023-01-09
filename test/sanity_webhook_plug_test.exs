defmodule SanityWebhookPlugTest do
  use ExUnit.Case
  use Plug.Test
  import ExUnit.CaptureIO
  alias SanityWebhookPlug.Signature

  def secret, do: {:ok, "test"}
  def bare_secret, do: "test"
  def bad_secret, do: {:ok, "test2"}
  def error_secret, do: {:error, "no secret"}

  @test_payload File.read!("test/support/test.jpg")
  @good_payload Jason.encode!(%{"_id" => "resume"})
  @good_ts 1_633_519_811_129
  @good_hash "tLa470fx7qkLLEcMOcEUFuBbRSkGujyskxrNXcoh0N0"
  @good_signature "t=#{@good_ts},v1=#{@good_hash}"
  @opts [
    handler: __MODULE__.Handler,
    at: "/sanity",
    secret: "test"
  ]

  defmodule Handler do
    def handle_event(conn, _params) do
      Plug.Conn.send_resp(conn, 200, Jason.encode!(%{success: "ok"}))
    end

    def handle_error(conn, error) when is_binary(error) do
      Plug.Conn.send_resp(conn, 400, Jason.encode!(%{error: error}))
    end

    def handle_error(conn, error) when is_exception(error) do
      Plug.Conn.send_resp(conn, 400, Jason.encode!(%{error: "error"}))
    end
  end

  test "secret is not printed" do
    # credo:disable-for-lines:1
    refute capture_io(fn -> IO.inspect(%SanityWebhookPlug{secret: "foo"}) end) =~ "foo"
  end

  test "base64url encoding and decoding" do
    original = "ladies and gentlemen, we are floating in space"
    encoded = "bGFkaWVzIGFuZCBnZW50bGVtZW4sIHdlIGFyZSBmbG9hdGluZyBpbiBzcGFjZQ"
    assert Signature.base64url_encode(original) == encoded
    assert Signature.base64url_decode(encoded) == original

    bin = Signature.base64url_encode(@test_payload)
    refute String.contains?(bin, "+")
    refute String.contains?(bin, "/")
    refute String.contains?(bin, "=")
    assert Signature.base64url_decode(bin) == @test_payload
  end

  test "works with single path" do
    opts = Keyword.put(@opts, :path, "/sanity")

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    assert %{error: false} = conn.private.sanity_webhook_plug
  end

  test "skips without path match" do
    opts = Keyword.put(@opts, :path, "/no-matchy")

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    refute :sanity_webhook_error in Map.keys(conn.private)

    opts = Keyword.put(@opts, :path, ["/no-matchy", "/no-matchy-2"])

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    refute :sanity_webhook_error in Map.keys(conn.private)
  end

  test "computes signature" do
    assert {:ok, computed} =
             SanityWebhookPlug.Signature.compute(@good_ts, @good_payload, @opts[:secret])

    assert computed == @good_hash

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(@opts)

    debug = conn.private.sanity_webhook_plug
    assert debug.error == false
    assert debug.computed == computed
    assert debug.hash == @good_hash
    assert debug.ts == @good_ts
    assert debug.body == nil
    assert debug.secret == @opts[:secret]
  end

  test "reads secret from MFA" do
    opts = Keyword.put(@opts, :secret, {__MODULE__, :bad_secret, []})

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    expected_message = "Sanity webhook signature does not match expected"
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug

    # --

    opts = Keyword.put(@opts, :secret, &__MODULE__.error_secret/0)

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    expected_message = "no secret"
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug

    # --

    opts = Keyword.put(@opts, :secret, {__MODULE__, :secret, []})

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    assert %{error: false} = conn.private.sanity_webhook_plug

    # --

    opts = Keyword.put(@opts, :secret, {__MODULE__, :bare_secret, []})

    conn =
      @good_payload
      |> setup_conn(@good_signature)
      |> call(opts)

    assert %{error: false} = conn.private.sanity_webhook_plug
  end

  test "halts on incorrect signature - timestamp" do
    bad_ts = 1_633_519_811_999
    bad_signature = "t=#{bad_ts},v1=#{@good_hash}"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> call(@opts)

    expected_message = "Sanity webhook signature does not match expected"
    assert conn.resp_body == Jason.encode!(%{error: expected_message})

    debug = conn.private.sanity_webhook_plug
    assert debug.error == expected_message
    assert debug.computed == "MvOplWzHD4SnEHitPZJmur5XzUATpQdN4oFX1ndiW7g"
    assert debug.hash == @good_hash
    assert debug.computed != debug.hash
    assert debug.ts == bad_ts
    assert debug.body == @good_payload
    assert debug.secret == @opts[:secret]
  end

  test "halts on incorrect signature - old timestamp" do
    bad_ts = 123
    bad_signature = "t=#{bad_ts},v1=#{@good_hash}"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> call(@opts)

    expected_message = "Timestamp 123 is too early to be a valid Sanity webhook"
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
  end

  test "halts on incorrect signature - hash" do
    bad_signature = "t=#{@good_ts},v1=badhash"

    conn =
      @good_payload
      |> setup_conn(bad_signature)
      |> call(@opts)

    expected_message = "Sanity webhook signature does not match expected"
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
  end

  test "halts on incorrect signature - payload" do
    bad_payload = "{\"_id\":\"foo\"}"

    conn =
      bad_payload
      |> setup_conn(@good_signature)
      |> call(@opts)

    expected_message = "Sanity webhook signature does not match expected"
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
  end

  test "json decoding errors" do
    binary = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
    {:ok, hash} = Signature.compute(@good_ts, binary, @opts[:secret])
    signature = "t=#{@good_ts},v1=#{hash}"

    conn =
      binary
      |> setup_conn(signature)
      |> call(@opts)

    assert %{error: %Jason.DecodeError{}} = conn.private.sanity_webhook_plug
    assert conn.resp_body == Jason.encode!(%{error: "error"})
  end

  # test "works with smaller read lengths" do
  #   opts = Keyword.put(@opts, :length, 8)
  #
  #   conn =
  #     @good_payload
  #     |> setup_conn(@good_signature)
  #     |> call(opts)
  # end

  test "halts on incorrect header" do
    conn =
      :post
      |> conn("/sanity", @good_payload)
      |> put_req_header("some-other-header", @good_signature)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("user-agent", "Sanity.io webhook delivery")
      |> put_req_header("accept-encoding", "gzip")
      |> call(@opts)

    expected_message = "Could not find valid Sanity webhook signature header"
    assert %{error: ^expected_message} = conn.private.sanity_webhook_plug
    assert conn.resp_body == Jason.encode!(%{error: expected_message})
  end

  defp setup_conn(payload, signature) do
    :post
    |> conn("/sanity?foo=bar", payload)
    |> put_req_header(SanityWebhookPlug.header(), signature)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("user-agent", "Sanity.io webhook delivery")
    |> put_req_header("accept-encoding", "gzip")
  end

  defp call(conn, opts) do
    SanityWebhookPlug.call(conn, SanityWebhookPlug.init(opts))
  end
end
