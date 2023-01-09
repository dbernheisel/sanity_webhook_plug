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
          hash: String.t(),
          ts: pos_integer()
        }

  defstruct [:body, :computed, :secret, :hash, :ts, error: false]

  @header "sanity-webhook-signature"
  @plug_key :sanity_webhook_plug

  @doc """
  Initialize SanityWebhookPlug options.
  """
  def init(opts) do
    path_info = opts |> Keyword.fetch!(:at) |> String.split("/", trim: true)
    handler = Keyword.fetch!(opts, :handler)

    sanity_json = Keyword.get(opts, :json_decoder)
    phoenix_json = Application.get_env(:phoenix, :json_library)
    jason = if Code.ensure_loaded?(Jason), do: Jason
    poison = if Code.ensure_loaded?(Poison), do: Poison

    [
      path_info,
      handler,
      Keyword.get(opts, :secret),
      Keyword.take(opts, [:length, :read_length, :read_timeout]),
      sanity_json || phoenix_json || jason || poison
    ]
  end

  @doc """
  Process the conn for a Sanity Webhook and verify its authenticity.
  """
  def call(conn, opts)

  def call(%Plug.Conn{halted: true} = conn, _), do: conn
  def call(%Plug.Conn{path_info: path_info} = conn, [path_info | opts]) do
    call(conn, opts)
  end

  def call(conn, [handler, secret, read_opts, json_mod]) do
    with {:ok, secret} <- get_secret(secret),
         {:ok, conn, body} <- read_body(conn, read_opts),
         {:ok, conn, {ts, hash}} <- get_signature(conn),
         :ok <- verify(conn, hash, ts, body, secret),
         {:ok, json} <- parse(json_mod, body, conn, ts, hash) do
      conn
      |> put_debug({hash, ts, nil}, hash, secret, false)
      |> handler.handle_event(json)
      |> Plug.Conn.halt()
    else
      {:error, error} ->
        # Bad secret or bad JSON decoding
        conn
        |> put_debug(nil, nil, secret, error)
        |> handle_error()
        |> handler.handle_error(error)

      {:error, error, conn} ->
        # Bad body read or no header
        conn
        |> put_debug(nil, nil, secret, error)
        |> handle_error()
        |> handler.handle_error(error)

      {:error, error, conn, components, computed} ->
        # Bad signature
        conn
        |> put_debug(components, computed, secret, error)
        |> handle_error()
        |> handler.handle_error(error)
    end
  end

  def call(conn, _opts), do: conn

  defp parse(json_mod, body, conn, ts, hash) do
    case json_mod.decode(body) do
      {:ok, json} ->
        {:ok, Map.merge(json, conn.query_params)}

      {:error, error} ->
        {:error, error, conn, {ts, hash, body}, nil}
    end
  end

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

  defp verify(conn, hash, ts, body, secret) do
    case Signature.verify(hash, ts, body, secret) do
      {:error, message, computed} -> {:error, message, conn, {hash, ts, body}, computed}
      ok -> ok
    end
  end

  defp read_body(%{body_params: %Plug.Conn.Unfetched{}} = conn, read_opts) do
    read_body(conn, "", Plug.Conn.read_body(conn, read_opts), read_opts)
  end

  defp read_body(conn, _read_opts), do: {:ok, conn, conn.body_params}

  defp read_body(_conn, body, {:ok, more_body, conn}, read_opts) do
    {:ok, Plug.Conn.fetch_query_params(conn, read_opts), body <> more_body}
  end

  defp read_body(_conn, body, {:more, more_body, conn}, read_opts) do
    read_body(conn, body <> more_body, Plug.Conn.read_body(conn, read_opts), read_opts)
  end

  defp read_body(conn, _body, {:error, error}, _read_opts), do: {:error, error, conn}

  defp get_signature(conn) do
    case Plug.Conn.get_req_header(conn, @header) do
      [header] ->
        %{"ts" => ts, "v1" => hash} =
          Regex.named_captures(~r/^t=(?<ts>\d+)[, ]v1=(?<v1>[^, ]+)$/, String.trim(header))

        {:ok, conn, {String.to_integer(ts), String.trim(hash)}}

      _ ->
        {:error, "Could not find valid Sanity webhook signature header", conn}
    end
  end

  defp put_debug(conn, nil, nil, secret, error) do
    secret = secret |> get_secret() |> elem(1)
    Plug.Conn.put_private(conn, @plug_key, %__MODULE__{error: error, secret: secret})
  end

  defp put_debug(conn, {hash, ts, body}, computed, secret, error) do
    {:ok, secret} = get_secret(secret)

    Plug.Conn.put_private(conn, @plug_key, %__MODULE__{
      hash: hash,
      error: error,
      ts: ts,
      computed: computed,
      secret: secret,
      body: body
    })
  end

  defp handle_error(conn), do: conn |> Plug.Conn.put_status(400) |> Plug.Conn.halt()

  defp get_secret({m, f, a}), do: get_secret(apply(m, f, a))
  defp get_secret(fun) when is_function(fun), do: get_secret(fun.())
  defp get_secret({:ok, secret}) when is_binary(secret), do: {:ok, secret}
  defp get_secret({:ok, nil}), do: get_secret(nil)
  defp get_secret({:error, _} = error), do: error
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
