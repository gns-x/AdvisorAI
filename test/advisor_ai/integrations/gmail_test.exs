defmodule AdvisorAi.Integrations.GmailTest do
  use AdvisorAi.DataCase

  alias AdvisorAi.Integrations.Gmail
  alias AdvisorAi.Accounts

  describe "email sync" do
    setup do
      {:ok, user} = AdvisorAi.Accounts.create_user(%{email: "test@example.com"})
      %{user: user}
    end

    test "sync_emails/1 returns error when no Google tokens", %{user: user} do
      result = Gmail.sync_emails(user)
      assert {:error, "No Google account connected"} = result
    end

    test "search_emails/2 returns error when no Google tokens", %{user: user} do
      result = Gmail.search_emails(user, "test query")
      assert {:error, "No Google account connected"} = result
    end

    test "send_email/4 returns error when no Google tokens", %{user: user} do
      result = Gmail.send_email(user, "recipient@example.com", "Test Subject", "Test Body")
      assert {:error, "No Google account connected"} = result
    end
  end
end
