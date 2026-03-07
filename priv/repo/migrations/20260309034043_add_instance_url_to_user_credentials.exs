defmodule SocialScribe.Repo.Migrations.AddInstanceUrlToUserCredentials do
  use Ecto.Migration

  def change do
    alter table(:user_credentials) do
      add_if_not_exists :instance_url, :string
    end
  end
end
