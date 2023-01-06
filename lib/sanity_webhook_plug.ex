defmodule SanityWebhookPlug do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @behaviour Plug
  require Logger
  alias SanityWebhookPlug.Signature

  @derive {Inspect, except: [:secret]}

  @type t :: %__MODULE__{
          body: binary() | nil,
          computed: String.t(),
          error: String.t() | false,
          secret: String.t(),
          signature: String.t(),
          ts: pos_integer()
        }

  defstruct [:body, :computed, :secret, :signature, :ts, error: false]

  @header "sanity-webhook-signature"
  @plug_key :sanity_webhook_plug

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
      sanity_json || phoenix_json || jason || poison
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

  def call(conn, [secret, read_opts, halt_on_error, json]) do
    with {:ok, secret} <- get_secret(secret),
         {:ok, conn, body} <- read_body(conn, read_opts),
         {:ok, conn, {ts, signature}} <- get_signature(conn),
         :ok <- verify(conn, signature, ts, body, secret) do
      put_debug(conn, {signature, ts, nil}, signature, secret)
    else
      {:error, error} ->
        # Bad secret
        conn
        |> put_debug(nil, nil, secret)
        |> handle_error(halt_on_error, json, error)

      {:error, error, conn} ->
        # Bad body read or no header
        conn
        |> put_debug(nil, nil, secret)
        |> handle_error(halt_on_error, json, error)

      {:error, error, conn, components, computed} ->
        # Bad signature
        conn
        |> put_debug(components, computed, secret)
        |> handle_error(halt_on_error, json, error)
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  Get the Sanity Webhook debug information from the conn.
  """
  @spec get_debug(Plug.Conn.t()) :: t()
  def get_debug(conn), do: conn.private[@plug_key]

  @doc """
  The expected request header that contains the Sanity webhook signature and timestamp
  """
  @spec header() :: String.t()
  def header, do: @header

  defp verify(conn, signature, ts, body, secret) do
    case Signature.verify(signature, ts, body, secret) do
      {:error, message, computed} -> {:error, message, conn, {signature, ts, body}, computed}
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

  defp read_body(conn, _body, {:error, error}, _read_opts), do: {:error, error, conn}

  defp get_signature(conn) do
    case Plug.Conn.get_req_header(conn, @header) do
      [header] ->
        %{"ts" => ts, "v1" => signature} =
          Regex.named_captures(~r/^t=(?<ts>\d+)[, ]v1=(?<v1>[^, ]+)$/, String.trim(header))

        {:ok, conn, {String.to_integer(ts), String.trim(signature)}}

      _ ->
        {:error, "Could not find valid Sanity webhook signature header", conn}
    end
  end

  defp put_debug(conn, nil, nil, secret) do
    Plug.Conn.put_private(conn, @plug_key, %__MODULE__{
      secret: secret
    })
  end

  defp put_debug(conn, {sig, ts, body}, computed, secret) do
    Plug.Conn.put_private(conn, @plug_key, %__MODULE__{
      signature: sig,
      ts: ts,
      computed: computed,
      secret: secret,
      body: body
    })
  end

  defp handle_error(conn, true, json, error) do
    conn
    |> Plug.Conn.put_private(@plug_key, %{conn.private[@plug_key] | error: error})
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(:bad_request, json.encode!(%{error: error}))
    |> Plug.Conn.halt()
  end

  defp handle_error(conn, false, _json, error) do
    Plug.Conn.put_private(conn, @plug_key, %{conn.private[@plug_key] | error: error})
  end

  defp get_secret({m, f, a}), do: get_secret(apply(m, f, a))
  defp get_secret(fun) when is_function(fun), do: get_secret(fun.())
  defp get_secret({:ok, secret}) when is_binary(secret), do: {:ok, secret}
  defp get_secret(secret) when is_binary(secret), do: {:ok, secret}

  defp get_secret(nil) do
    case Application.get_env(:sanity_webhook_plug, :webhook_secret) do
      nil ->
        {:error, "No secret configured for SanityWebhookPlug"}

      secret ->
        {:ok, secret}
    end
  end
end
