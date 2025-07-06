defmodule AdvisorAi.Auth.HubSpotStrategy do
  @moduledoc """
  HubSpot OAuth2 strategy for Ueberauth.
  """

  use Ueberauth.Strategy,
    default_scope: "",
    send_redirect_uri: true,
    oauth2_module: Ueberauth.Strategy.HubSpot.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    send_redirect_uri? = Keyword.get(options(conn), :send_redirect_uri, true)

    opts =
      [redirect_uri: callback_url(conn)]
      |> put_scope(scopes)
      |> maybe_put_redirect_uri(send_redirect_uri?)

    module = option(conn, :oauth2_module)
    redirect!(conn, apply(module, :authorize_url!, [opts]))
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    module = option(conn, :oauth2_module)
    client = apply(module, :get_token!, [[code: code, redirect_uri: callback_url(conn)]])

    case token_to_user(client.token, client) do
      {:ok, user} ->
        put_private(conn, :hubspot_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("token_error", reason)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:hubspot_user, nil)
  end

  def uid(conn) do
    conn.private.hubspot_user["user"]
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.hubspot_user["access_token"],
        refresh_token: conn.private.hubspot_user["refresh_token"],
        expires_at: conn.private.hubspot_user["expires_in"]
      }
    }
  end

  def credentials(conn) do
    %Credentials{
      expires: !!conn.private.hubspot_user["expires_in"],
      expires_at: conn.private.hubspot_user["expires_in"],
      scopes: conn.private.hubspot_user["scope"],
      token: conn.private.hubspot_user["access_token"],
      refresh_token: conn.private.hubspot_user["refresh_token"],
      token_type: "Bearer"
    }
  end

  def info(conn) do
    %Info{
      email: conn.private.hubspot_user["user"],
      name: conn.private.hubspot_user["user"]
    }
  end

  defp token_to_user(token, _client) do
    case Ueberauth.Strategy.HubSpot.OAuth.get_user!(%OAuth2.Client{token: token}) do
      %{"user" => _user} = data -> {:ok, data}
      _ -> {:error, "Could not fetch user info from HubSpot"}
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp put_scope(opts, nil), do: opts
  defp put_scope(opts, scope) when is_binary(scope) and scope != "", do: Keyword.put(opts, :scope, scope)
  defp put_scope(opts, scope) when is_binary(scope) and scope == "", do: opts

  defp put_scope(opts, scopes) when is_list(scopes),
    do: Keyword.put(opts, :scope, Enum.join(scopes, " "))

  defp maybe_put_redirect_uri(opts, true), do: opts
  defp maybe_put_redirect_uri(opts, false), do: Keyword.delete(opts, :redirect_uri)
end
