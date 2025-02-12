defmodule Plausible.IngestRepo.Migrations.EventsEngagementTime do
  use Ecto.Migration

  def change do
    alter table(:events_v2) do
      add :engagement_time, :UInt32
    end

    alter table(:imported_pages) do
      add :total_time_on_page, :UInt64
      add :total_time_on_page_visits, :UInt64
    end
  end
end
