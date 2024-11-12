defmodule Plausible.Repo.Migrations.SegmentsCleanup do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION clean_segments() RETURNS trigger AS $$
    BEGIN
      UPDATE segments
      SET owner_id = null
      WHERE site_id in (SELECT id FROM sites WHERE sites.team_id = OLD.team_id) AND owner_id = OLD.user_id AND type = 'site';

      DELETE FROM segments
      WHERE site_id in (SELECT id FROM sites WHERE sites.team_id = OLD.team_id) AND owner_id = OLD.user_id AND type = 'personal';

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER user_deassociated_from_team
    AFTER DELETE ON team_memberships
    FOR EACH ROW
    EXECUTE FUNCTION clean_segments();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS user_deassociated_from_team ON team_memberships;"
    execute "DROP FUNCTION IF EXISTS clean_segments();"
  end
end
