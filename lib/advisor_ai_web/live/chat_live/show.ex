defmodule AdvisorAiWeb.ChatLive.Show do
  use AdvisorAiWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, :id, id)}
  end
end
