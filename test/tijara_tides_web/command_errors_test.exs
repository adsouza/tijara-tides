defmodule TijaraTidesWeb.CommandErrorsTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameLive

  test "contained command failures and paused worlds have distinct player messages" do
    TijaraTides.Localization.with_locale("en", fn ->
      assert GameLive.error_message(:command_failed) ==
               "That command could not be completed. The game is still running. Please contact the operator if this keeps happening."

      assert GameLive.error_message(:internal_error) ==
               "The world paused after an internal error. Please contact the operator."
    end)
  end

  test "the contained failure has an Arabic translation" do
    TijaraTides.Localization.with_locale("ar", fn ->
      assert GameLive.error_message(:command_failed) ==
               "تعذّر إكمال هذا الأمر. لا تزال اللعبة تعمل. يُرجى التواصل مع المشغّل إذا تكرر ذلك."
    end)
  end
end
