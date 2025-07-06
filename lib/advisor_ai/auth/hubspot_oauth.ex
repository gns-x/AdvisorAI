defmodule Ueberauth.Strategy.HubSpot.OAuth do
  @moduledoc """
  An OAuth2 strategy for HubSpot.
  """

  use OAuth2.Strategy

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__) || []

    client_opts =
      [
        site: "https://api.hubapi.com",
        authorize_url: "https://app.hubspot.com/oauth/authorize",
        token_url: "https://api.hubapi.com/oauth/v1/token",
        redirect_uri: System.get_env("HUBSPOT_REDIRECT_URI", "http://localhost:4000/auth/hubspot/callback")
      ]
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    OAuth2.Client.new(client_opts)
    |> OAuth2.Client.put_serializer("application/json", Jason)
  end

  # Required by OAuth2.Strategy behaviour
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    OAuth2.Strategy.AuthCode.get_token(client, params, headers)
  end

  def get_token!(params \\ [], _opts \\ []) do
    client()
    |> put_param_local("client_id", client().client_id)
    |> put_param_local("client_secret", client().client_secret)
    |> put_param_local("grant_type", "authorization_code")
    |> put_param_local("code", Keyword.get(params, :code))
    |> put_param_local("redirect_uri", Keyword.get(params, :redirect_uri))
    |> put_header_local("accept", "application/json")
    |> OAuth2.Client.get_token!()
  end

  def get_user!(client) do
    %{body: user} =
      OAuth2.Client.get!(client, "/oauth/v1/access-tokens/#{client.token.access_token}")

    user
  end

  def authorize_url!(params \\ []) do
    client()
    |> put_param_local("client_id", client().client_id)
    |> put_param_local("redirect_uri", Keyword.get(params, :redirect_uri))
    |> put_param_local("scope", Keyword.get(params, :scope))
    |> put_param_local("response_type", "code")
    |> put_param_local("state", "direct_oauth")
    |> OAuth2.Client.authorize_url!()
  end

  defp put_param_local(client, key, value) do
    OAuth2.Client.put_param(client, key, value)
  end

  defp put_header_local(client, key, value) do
    OAuth2.Client.put_header(client, key, value)
  end
end
