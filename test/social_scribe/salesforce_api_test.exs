defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase, async: false

  import SocialScribe.AccountsFixtures

  alias SocialScribe.SalesforceApi

  setup do
    prev_tesla_adapter = Application.get_env(:tesla, :adapter)
    prev_sf_config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    Application.put_env(:tesla, :adapter, Tesla.Mock)

    Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      site: "https://example.my.salesforce.com"
    )

    on_exit(fn ->
      if prev_tesla_adapter do
        Application.put_env(:tesla, :adapter, prev_tesla_adapter)
      else
        Application.delete_env(:tesla, :adapter)
      end

      Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, prev_sf_config)
    end)

    :ok
  end

  describe "search_contacts/2" do
    test "returns formatted Salesforce contacts from query endpoint" do
      credential = salesforce_credential_fixture()

      Tesla.Mock.mock(fn
        %{method: :get, url: url} ->
          assert String.contains?(url, "/services/data/v61.0/query")
          assert String.contains?(url, "SELECT")

          %Tesla.Env{
            status: 200,
            body: %{
              "records" => [
                %{
                  "Id" => "003ABC",
                  "FirstName" => "Ada",
                  "LastName" => "Lovelace",
                  "Email" => "ada@example.com",
                  "Phone" => "8885550000",
                  "Account" => %{"Name" => "Analytical Engines"}
                }
              ]
            }
          }
      end)

      assert {:ok, [contact]} = SalesforceApi.search_contacts(credential, "Ada")
      assert contact.id == "003ABC"
      assert contact.display_name == "Ada Lovelace"
      assert contact.company == "Analytical Engines"
    end
  end

  describe "get_contact/2" do
    test "returns not_found when Salesforce returns empty records" do
      credential = salesforce_credential_fixture()

      Tesla.Mock.mock(fn
        %{method: :get, url: url} ->
          assert String.contains?(url, "/services/data/v61.0/query")
          %Tesla.Env{status: 200, body: %{"records" => []}}
      end)

      assert {:error, :not_found} = SalesforceApi.get_contact(credential, "003MISSING")
    end
  end

  describe "update_contact/3" do
    test "maps challenge fields to Salesforce API field names" do
      credential = salesforce_credential_fixture()

      Tesla.Mock.mock(fn
        %{method: :patch, url: url, body: body} ->
          decoded_body = Jason.decode!(body)
          assert String.contains?(url, "/services/data/v61.0/sobjects/Contact/003ABC")
          assert decoded_body["Phone"] == "8885550000"
          assert decoded_body["Title"] == "CFO"
          %Tesla.Env{status: 204, body: ""}
      end)

      assert {:ok, response} =
               SalesforceApi.update_contact(credential, "003ABC", %{
                 "phone" => "8885550000",
                 "jobtitle" => "CFO"
               })

      assert response.id == "003ABC"
      assert response.updated_fields["Phone"] == "8885550000"
      assert response.updated_fields["Title"] == "CFO"
    end
  end

  describe "apply_updates/3" do
    test "returns :no_updates when all suggestions are skipped" do
      credential = salesforce_credential_fixture()

      updates = [
        %{field: "phone", new_value: "8885550000", apply: false},
        %{field: "jobtitle", new_value: "CFO", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003ABC", updates)
    end
  end
end
