defmodule SanityWebhookPlug do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @behaviour Plug
  require Logger
  alias SanityWebhookPlug.Signature

  @header "sanity-webhook-signature"
  @plug_error_key :sanity_webhook_error

  @doc """
  Initialize SanityWebhookPlug options.
  """
  def init(opts) do
    paths = Keyword.get(opts, :path)
    paths || Logger.warn(":path is not set for #{inspect(__MODULE__)}; skipping plug")

    sanity_json = Keyword.get(opts, :json_library)
    phoenix_json = Application.get_env(:phoenix, :json_library)
    jason = if Code.ensure_loaded?(Jason), do: Jason
    poison = if Code.ensure_loaded?(Poison), do: Poison

    [
      paths,
      Keyword.get(opts, :secret),
      Keyword.take(opts, [:length, :read_length, :read_timeout]),
      Keyword.get(opts, :halt_on_error, false),
      sanity_json || phoenix_json || jason || poison,
      Keyword.get(opts, :debug, false)
    ]
  end

  @doc """
  Process the conn for a Sanity Webhook and verify its authenticity.
  """
  def call(%Plug.Conn{request_path: path} = conn, [path | opts]) when is_binary(path) do
    call(conn, opts)
  end

  def call(%Plug.Conn{request_path: path} = conn, [paths | opts])
      when is_list(paths) and paths != [] do
    if path in paths do
      call(conn, opts)
    else
      conn
    end
  end

  def call(conn, [secret, read_opts, halt_on_error, json, debug]) do
    with {:ok, conn, body} <- read_body(conn, read_opts),
         {:ok, conn, {ts, signature}} <- get_signature(conn),
         :ok <- verify(conn, signature, ts, body, secret) do
      Plug.Conn.put_private(conn, @plug_error_key, false)
    else
      {:error, conn, error, comps} ->
        conn
        |> maybe_debug(debug, comps, secret)
        |> handle_error(halt_on_error, json, error)

      {:error, conn, error} ->
        handle_error(conn, halt_on_error, json, error)
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  Get the Sanity Webhook error from the conn.
  """
  @spec get_error(Plug.Conn.t()) :: false | String.t()
  def get_error(conn), do: conn.private[@plug_error_key]

  @doc """
  The expected header that contains the Sanity webhook signature and timestamp
  """
  @spec header() :: String.t()
  def header, do: @header

  defp verify(conn, signature, ts, body, secret) do
    case Signature.verify(signature, ts, body, secret) do
      {:error, message} -> {:error, conn, message, {signature, ts, body}}
      ok -> ok
    end
  end

  defp read_body(%{body_params: %Plug.Conn.Unfetched{}} = conn, read_opts) do
    read_body(conn, "", Plug.Conn.read_body(conn, read_opts), read_opts)
  end

  defp read_body(conn, _read_opts), do: {:ok, conn, conn.body_params}

  defp read_body(_conn, body, {:ok, more_body, conn}, _read_opts) do
    {:ok, conn, body <> more_body}
  end

  defp read_body(_conn, body, {:more, more_body, conn}, read_opts) do
    read_body(conn, body <> more_body, Plug.Conn.read_body(conn, read_opts), read_opts)
  end

  defp read_body(conn, _body, {:error, error}, _read_opts), do: {:error, conn, error}

  defp get_signature(conn) do
    case Plug.Conn.get_req_header(conn, @header) do
      [header] ->
        %{"ts" => ts, "v1" => signature} =
          Regex.named_captures(~r/^t=(?<ts>\d+)[, ]v1=(?<v1>[^, ]+)$/, String.trim(header))

        {:ok, conn, {String.to_integer(ts), String.trim(signature)}}

      _ ->
        {:error, conn, "Could not find valid Sanity webhook signature header"}
    end
  end

  defp maybe_debug(conn, true, {sig, ts, body}, secret) do
    conn
    |> Plug.Conn.put_private(:sanity_ts, ts)
    |> Plug.Conn.put_private(:sanity_sig, sig)
    |> Plug.Conn.put_private(:sanity_secret, secret)
    |> Plug.Conn.put_private(:sanity_computed_sig, Signature.compute(ts, body, secret))
    |> Plug.Conn.put_private(:sanity_payload, body)
  end
  defp maybe_debug(conn, false, _components, _secret), do: conn

  defp handle_error(conn, true, json, error) do
    conn
    |> Plug.Conn.put_private(@plug_error_key, error)
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(:bad_request, json.encode!(%{error: error}))
    |> Plug.Conn.halt()
  end
  defp handle_error(conn, false, _json, error),
    do: Plug.Conn.put_private(conn, @plug_error_key, error)
end
