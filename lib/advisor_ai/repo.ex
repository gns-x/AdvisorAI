defmodule AdvisorAi.Repo do
  use Ecto.Repo,
    otp_app: :advisor_ai,
    adapter: Ecto.Adapters.Postgres
end
