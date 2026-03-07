defmodule SocialScribeWeb.SalesforceEntryTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Salesforce meeting entry point" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "shows Salesforce integration CTA when credential exists", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Salesforce Integration"
      assert html =~ "Review Salesforce Updates"
    end

    test "opens and closes Salesforce review modal shell", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute has_element?(view, "#salesforce-review-modal")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      assert has_element?(view, "#salesforce-review-modal")
      assert has_element?(view, "#salesforce-review-shell")
      assert render(view) =~ "Salesforce Contact Review"

      render_click(view, "close_salesforce_review")

      refute has_element?(view, "#salesforce-review-modal")
    end

    test "searches Salesforce contacts and renders results", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Ada"

        {:ok,
         [
           %{
             id: "003ABC",
             display_name: "Ada Lovelace",
             email: "ada@example.com"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)

      assert has_element?(view, "#salesforce-search-results")
      assert has_element?(view, "#salesforce-contact-result-003ABC")
      assert render(view) =~ "Ada Lovelace"
    end

    test "shows empty state when Salesforce search has no results", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "NoMatch"
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "NoMatch"}})
      |> render_submit()

      :timer.sleep(50)

      assert has_element?(view, "#salesforce-search-empty")
      assert render(view) =~ "No Salesforce contacts found."
    end

    test "requires at least 3 characters before searching", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ad"}})
      |> render_submit()

      assert has_element?(view, "#salesforce-search-error")
      assert render(view) =~ "Enter at least 3 characters to search."
    end

    test "caps displayed search results and shows narrowing notice", %{
      conn: conn,
      meeting: meeting
    } do
      many_contacts =
        1..12
        |> Enum.map(fn idx ->
          %{
            id: "003ABC#{idx}",
            display_name: "Contact #{idx}",
            email: "contact#{idx}@example.com"
          }
        end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Many"
        {:ok, many_contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Many"}})
      |> render_submit()

      assert has_element?(view, "#salesforce-search-notice")

      assert render(view) =~
               "Returned too many contacts. Showing first 10; please narrow your search."

      assert has_element?(view, "#salesforce-contact-result-003ABC1")
      assert has_element?(view, "#salesforce-contact-result-003ABC10")
      refute has_element?(view, "#salesforce-contact-result-003ABC11")
      refute has_element?(view, "#salesforce-contact-result-003ABC12")
    end

    test "selects a Salesforce contact and loads full contact details", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Ada"

        {:ok,
         [
           %{
             id: "003ABC",
             display_name: "Ada Lovelace",
             email: "ada@example.com"
           }
         ]}
      end)
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "003ABC"

        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [
           %{
             field: "phone",
             value: "8885550000",
             context: "Client said my new phone is 8885550000"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)

      view
      |> element("#salesforce-contact-result-003ABC")
      |> render_click()

      :timer.sleep(50)

      assert has_element?(view, "#salesforce-selected-contact")
      assert has_element?(view, "#salesforce-suggestions-list")
      assert render(view) =~ "Selected Contact"
      assert render(view) =~ "ada@example.com"
      assert render(view) =~ "8885550000"
    end

    test "opens and closes mapping editor from suggestion card", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      refute has_element?(view, "#salesforce-mapping-editor")

      view
      |> element("button[phx-click='open_salesforce_mapping'][phx-value-field='phone']")
      |> render_click()

      assert has_element?(view, "#salesforce-mapping-editor")

      view
      |> element("button[phx-click='close_salesforce_mapping']")
      |> render_click()

      refute has_element?(view, "#salesforce-mapping-editor")
    end

    test "saves mapping and applies it to refreshed suggestions", %{
      conn: conn,
      meeting: meeting,
      user: user
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333",
           mobilephone: "3332221111"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      # Initial suggestion maps to phone.
      assert render(view) =~ "name=\"values[phone]\""

      view
      |> element("button[phx-click='open_salesforce_mapping'][phx-value-field='phone']")
      |> render_click()

      view
      |> form("#salesforce-mapping-form", %{
        "salesforce_mapping" => %{"source_field" => "phone", "target_field" => "mobilephone"}
      })
      |> render_submit()

      :timer.sleep(50)

      assert render(view) =~ "Salesforce field mapping updated."
      assert render(view) =~ "name=\"values[mobilephone]\""
      refute render(view) =~ "name=\"values[phone]\""

      mappings = SocialScribe.Accounts.get_user_salesforce_field_mappings_map(user.id)
      assert mappings["phone"] == "mobilephone"
    end

    test "shows reconnect guidance when Salesforce session is invalid", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Ada"

        {:error,
         {:api_error, 401,
          [%{"errorCode" => "INVALID_SESSION_ID", "message" => "Session expired or invalid"}]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)

      assert has_element?(view, "#salesforce-search-error")

      assert render(view) =~
               "Salesforce session expired. Reconnect Salesforce in Settings and try again."
    end

    test "shows Gemini quota guidance when suggestion generation is rate limited", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Ada"

        {:ok,
         [
           %{
             id: "003ABC",
             display_name: "Ada Lovelace",
             email: "ada@example.com"
           }
         ]}
      end)
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "003ABC"

        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:error, {:api_error, 429, %{}}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view
      |> element("button[phx-click='open_salesforce_review']")
      |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)

      view
      |> element("#salesforce-contact-result-003ABC")
      |> render_click()

      :timer.sleep(50)

      assert render(view) =~
               "Gemini quota exceeded. Enable billing or wait for quota reset, then try again."
    end

    test "applies selected Salesforce updates successfully", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)
      |> expect(:apply_updates, fn _credential, "003ABC", updates_list ->
        assert Enum.any?(
                 updates_list,
                 &(&1.field == "phone" and &1.new_value == "8885550000" and &1.apply)
               )

        {:ok, %{id: "003ABC"}}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "8885550000"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      view
      |> form("#salesforce-suggestions-list", %{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "8885550000"}
      })
      |> render_submit()

      :timer.sleep(100)
      assert render(view) =~ "Successfully updated 1 field(s) in Salesforce."
    end

    test "shows error when submitting Salesforce updates with no selected fields", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      render_change(view, "toggle_salesforce_suggestion", %{
        "apply" => %{},
        "values" => %{"phone" => "8885550000"}
      })

      render_submit(view, "apply_salesforce_updates", %{
        "values" => %{"phone" => "8885550000"}
      })

      assert render(view) =~ "Select at least one field to update."
    end

    test "shows error when submitting updates before selecting a contact", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      render_submit(view, "apply_salesforce_updates", %{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "8885550000"}
      })

      assert render(view) =~ "Select a Salesforce contact first."
    end

    test "shows Salesforce update error when API update fails", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)
      |> expect(:apply_updates, fn _credential, "003ABC", _updates_list ->
        {:error, {:api_error, 500, %{}}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      view
      |> form("#salesforce-suggestions-list", %{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "8885550000"}
      })
      |> render_submit()

      :timer.sleep(50)
      assert render(view) =~ "Failed to update Salesforce contact."
    end

    test "submits edited suggestion values to Salesforce update payload", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)
      |> expect(:apply_updates, fn _credential, "003ABC", updates_list ->
        assert [%{field: "phone", new_value: "7771112222", apply: true}] = updates_list
        {:ok, %{id: "003ABC"}}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "7771112222"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      view
      |> form("#salesforce-suggestions-list", %{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "7771112222"}
      })
      |> render_submit()

      :timer.sleep(100)
      assert render(view) =~ "Successfully updated 1 field(s) in Salesforce."
    end

    test "shows partial success message when Salesforce updates but contact reload fails", %{
      conn: conn,
      meeting: meeting
    } do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, "Ada" ->
        {:ok, [%{id: "003ABC", display_name: "Ada Lovelace", email: "ada@example.com"}]}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:ok,
         %{
           id: "003ABC",
           display_name: "Ada Lovelace",
           email: "ada@example.com",
           phone: "1112223333"
         }}
      end)
      |> expect(:apply_updates, fn _credential, "003ABC", _updates_list ->
        {:ok, %{id: "003ABC"}}
      end)
      |> expect(:get_contact, fn _credential, "003ABC" ->
        {:error, {:http_error, :timeout}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:ok,
         [%{field: "phone", value: "8885550000", context: "Client said phone is 8885550000"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      view |> element("button[phx-click='open_salesforce_review']") |> render_click()

      view
      |> form("#salesforce-contact-search-form", %{"salesforce_search" => %{"query" => "Ada"}})
      |> render_submit()

      :timer.sleep(50)
      view |> element("#salesforce-contact-result-003ABC") |> render_click()
      :timer.sleep(50)

      view
      |> form("#salesforce-suggestions-list", %{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "8885550000"}
      })
      |> render_submit()

      :timer.sleep(100)

      assert render(view) =~ "Updated Salesforce, but failed to reload contact details."
      assert render(view) =~ "Network error while contacting Salesforce. Please try again."
    end
  end

  describe "Salesforce entry without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not render salesforce section", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Review Salesforce Updates"
    end
  end

  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "User",
            "words" => [%{"text" => "Hello"}, %{"text" => "world"}]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
