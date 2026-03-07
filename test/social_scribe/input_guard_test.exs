defmodule SocialScribe.InputGuardTest do
  use ExUnit.Case, async: true

  alias SocialScribe.InputGuard

  setup do
    prev = Application.get_env(:social_scribe, :limits)

    Application.put_env(:social_scribe, :limits, %{
      inputs: %{
        crm_search_max_chars: 5,
        crm_update_max_fields: 2,
        crm_field_value_max_chars: 4,
        social_post_max_chars: 10
      }
    })

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:social_scribe, :limits)
      else
        Application.put_env(:social_scribe, :limits, prev)
      end
    end)

    :ok
  end

  test "rejects too long CRM search query" do
    assert {:error, {:too_long, 5}} = InputGuard.validate_crm_search_query("abcdef", min_len: 2)
  end

  test "rejects unknown CRM update fields" do
    assert {:error, {:unknown_fields, ["unknown"]}} =
             InputGuard.sanitize_crm_updates(%{"unknown" => "x"}, ["phone", "email"])
  end

  test "rejects too many CRM update fields" do
    assert {:error, {:too_many_fields, 2}} =
             InputGuard.sanitize_crm_updates(
               %{"phone" => "1", "email" => "a", "firstname" => "b"},
               ["phone", "email", "firstname"]
             )
  end

  test "rejects CRM update value that exceeds max length" do
    assert {:error, {:value_too_long, "phone", 4}} =
             InputGuard.sanitize_crm_updates(%{"phone" => "12345"}, ["phone"])
  end

  test "rejects social post above configured maximum" do
    assert {:error, {:too_long, 10}} = InputGuard.validate_social_post("12345678901")
  end
end
