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

  Options:

  - `:paths` (req): The request paths to match against. eg: `["/webhooks/sanity/bust_cache"]`
  - `:halt_on_error` (default: true): Halt on error. If you want to handle errors yourself, make this `false` and handle
      in your controller action.
  - `:secret`: The Sanity webhook secret. eg: `123abc`. Supplying an MFA tuple will be called at runtime, otherwise it
      will be compiled. If not set, it will obtain via config
      `Application.get_env(:sanity_webhook_plug, :webhook_secret)`

  Options forwarded to `Plug.Conn.read_body/2`:

  - `:length` - sets the number of bytes to read from the request at a time.
  - `:read_length` - sets the amount of bytes to read at one time from the underlying socket to fill the chunk.
  - `:read_timeout` - sets the timeout for each socket read.
  """
  def init(opts) do
    paths = Keyword.get(opts, :paths)
    paths || Logger.warn(":paths is not set for #{inspect(__MODULE__)}, skipping plug")

    [
      Keyword.get(opts, :secret),
      List.wrap(paths),
      Keyword.take(opts, [:length, :read_length, :read_timeout]),
      Keyword.get(opts, :halt_on_error, false)
    ]
  end

  @doc """
  Process the conn for a Sanity Webhook and verify its authenticity.
  """
  def call(%Plug.Conn{request_path: path} = conn, [secret, paths, read_opts, halt_on_error])
      when paths != [] do
    with true <- path in paths,
         {:ok, conn, body} <- read_body(conn, read_opts),
         {:ok, conn, {ts, signature}} <- get_signature(conn),
         :ok <- verify(conn, signature, ts, body, secret) do
      Plug.Conn.put_private(conn, @plug_error_key, false)
    else
      false ->
        conn

      {:error, conn, error} ->
        conn = Plug.Conn.put_private(conn, @plug_error_key, error)

        if halt_on_error do
          conn
          |> Plug.Conn.send_resp(:bad_request, error)
          |> Plug.Conn.halt()
        else
          conn
        end
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
      {:error, message} -> {:error, conn, message}
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

        {:ok, conn, {String.to_integer(ts), signature}}

      _ ->
        {:error, conn, "Could not find valid Sanity webhook signature header"}
    end
  end
end
