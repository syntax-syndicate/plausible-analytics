defmodule Plausible.Repo.Migrations.AddIsAutocreatedToTeamMemberships do
  use Ecto.Migration

  def change do
    alter table(:team_memberships) do
      add :is_autocreated, :boolean, null: false, default: false
    end

    create unique_index(:team_memberships, [:user_id],
             where: "role = 'owner' and is_autocreated = true",
             name: :one_autocreated_owner_per_user
           )

    drop unique_index(:team_memberships, [:user_id],
           where: "role != 'guest'",
           name: :one_team_per_user
         )
  end
end
