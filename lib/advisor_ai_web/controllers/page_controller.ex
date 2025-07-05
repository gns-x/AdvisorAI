defmodule AdvisorAiWeb.PageController do
  use AdvisorAiWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
