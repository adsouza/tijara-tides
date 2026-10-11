defmodule TijaraTides.Repo.Migrations.AllowDynamicInvitationProgress do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE game_invitation_progress
      DROP CONSTRAINT game_invitation_progress_progress_ms_check,
      ADD CONSTRAINT game_invitation_progress_progress_ms_check
        CHECK (progress_ms >= 0)
    """)
  end

  def down, do: raise("Dynamic invitation progress must be retained")
end
