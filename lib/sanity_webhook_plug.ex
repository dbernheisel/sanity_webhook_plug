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

    [
      paths,
      Keyword.get(opts, :secret),
      Keyword.take(opts, [:length, :read_length, :read_timeout]),
      Keyword.get(opts, :halt_on_error, false)
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

  def call(conn, [secret, read_opts, halt_on_error]) do
    with {:ok, conn, body} <- read_body(conn, read_opts),
         {:ok, conn, {ts, signature}} <- get_signature(conn),
         :ok <- verify(conn, signature, ts, body, secret) do
      Plug.Conn.put_private(conn, @plug_error_key, false)
    else
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
