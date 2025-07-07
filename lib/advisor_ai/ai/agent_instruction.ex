defmodule AdvisorAi.AI.AgentInstruction do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias AdvisorAi.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_instructions" do
    field :instruction, :string
    field :is_active, :boolean, default: true
    # "email_received", "calendar_event", "hubspot_update", etc.
    field :trigger_type, :string
    field :conditions, :map, default: %{}

    belongs_to :user, AdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(agent_instruction, attrs) do
    agent_instruction
    |> cast(attrs, [:instruction, :is_active, :trigger_type, :conditions, :user_id])
    |> validate_required([:instruction, :user_id])
  end

  def list_by_user(user_id) do
    from(i in __MODULE__, where: i.user_id == ^user_id)
    |> Repo.all()
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get!(id) do
    Repo.get!(__MODULE__, id)
  end

  def update(%__MODULE__{} = agent_instruction, attrs) do
    agent_instruction
    |> changeset(attrs)
    |> Repo.update()
  end

  def delete(%__MODULE__{} = agent_instruction) do
    Repo.delete(agent_instruction)
  end

  @doc """
  Gets all active instructions for a user by trigger type.

  ## Examples

      iex> get_active_instructions_by_trigger(user_id, "email_received")
      {:ok, [%AgentInstruction{}, ...]}

  """
  def get_active_instructions_by_trigger(user_id, trigger_type) do
    case Repo.all(
      from i in __MODULE__,
      where: i.user_id == ^user_id and i.trigger_type == ^trigger_type and i.is_active == true
    ) do
      instructions when is_list(instructions) -> {:ok, instructions}
      _ -> {:ok, []}
    end
  end

  @doc """
  Gets all active instructions for a user.

  ## Examples

      iex> get_active_instructions_by_user(user_id)
      {:ok, [%AgentInstruction{}, ...]}

  """
  def get_active_instructions_by_user(user_id) do
    case Repo.all(
      from i in __MODULE__,
      where: i.user_id == ^user_id and i.is_active == true
    ) do
      instructions when is_list(instructions) -> {:ok, instructions}
      _ -> {:ok, []}
    end
  end
end
