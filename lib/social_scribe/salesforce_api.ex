defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contact operations.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.ErrorMapper
  alias SocialScribe.InputGuard
  alias SocialScribe.Limits

  @api_version "v61.0"
  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Account.Name"
  ]

  # Contact-updatable fields only. "company" maps to Account.Name in reads,
  # but Account.Name is not patchable through Contact update payloads.
  @updatable_field_map %{
    "firstname" => "FirstName",
    "lastname" => "LastName",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "MobilePhone",
    "jobtitle" => "Title",
    "address" => "MailingStreet",
    "city" => "MailingCity",
    "state" => "MailingState",
    "zip" => "MailingPostalCode",
    "country" => "MailingCountry"
  }

  def allowed_update_fields, do: Map.keys(@updatable_field_map)

  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with {:ok, trimmed_query} <- InputGuard.validate_crm_search_query(query, min_len: 1) do
      if trimmed_query == "" do
        {:ok, []}
      else
        soql = search_soql(trimmed_query)
        url = "/services/data/#{@api_version}/query?q=#{URI.encode_www_form(soql)}"

        case Tesla.get(client(credential.token), url) do
          {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
            contacts =
              records
              |> Enum.map(&format_contact/1)
              |> Enum.reject(&is_nil/1)

            {:ok, contacts}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, ErrorMapper.api(status, body)}

          {:error, reason} ->
            {:error, ErrorMapper.http(reason)}
        end
      end
    else
      {:error, reason} -> {:error, ErrorMapper.invalid_input(reason)}
    end
  end

  def get_contact(%UserCredential{} = credential, contact_id) when is_binary(contact_id) do
    soql = contact_soql(contact_id)
    url = "/services/data/#{@api_version}/query?q=#{URI.encode_www_form(soql)}"

    case Tesla.get(client(credential.token), url) do
      {:ok, %Tesla.Env{status: 200, body: %{"records" => [record | _]}}} ->
        {:ok, format_contact(record)}

      {:ok, %Tesla.Env{status: 200, body: %{"records" => []}}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, ErrorMapper.api(status, body)}

      {:error, reason} ->
        {:error, ErrorMapper.http(reason)}
    end
  end

  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_binary(contact_id) and is_map(updates) do
    with {:ok, sanitized_updates} <-
           InputGuard.sanitize_crm_updates(updates, allowed_update_fields()),
         update_body <- normalize_updates(sanitized_updates),
         false <- map_size(update_body) == 0 do
      case Tesla.patch(
             client(credential.token),
             "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}",
             update_body
           ) do
        {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
          {:ok, %{id: contact_id, updated_fields: update_body}}

        {:ok, %Tesla.Env{status: 404}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, ErrorMapper.api(status, body)}

        {:error, reason} ->
          {:error, ErrorMapper.http(reason)}
      end
    else
      true ->
        {:ok, :no_updates}

      {:error, reason} ->
        {:error, ErrorMapper.invalid_input(reason)}
    end
  end

  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_binary(contact_id) and is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(&(&1[:apply] == true))
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) == 0 do
      {:ok, :no_updates}
    else
      update_contact(credential, contact_id, updates_map)
    end
  end

  defp client(access_token) do
    recv_timeout = Limits.http(:default_recv_timeout_ms)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, salesforce_site()},
      {Tesla.Middleware.Retry,
       max_retries: Limits.http(:retry_attempts),
       delay: Limits.http(:retry_backoff_base_ms),
       max_delay: Limits.http(:retry_backoff_max_ms),
       should_retry: &should_retry?/3},
      {Tesla.Middleware.Timeout, timeout: recv_timeout},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  defp salesforce_site do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    Keyword.get(config, :site, "https://login.salesforce.com")
  end

  defp search_soql(query) do
    escaped_query = escape_like(query)
    escaped_id = escape_id(query)
    id_clause = if salesforce_id?(query), do: " OR Id = '#{escaped_id}'", else: ""

    """
    SELECT #{Enum.join(@contact_fields, ", ")}
    FROM Contact
    WHERE Name LIKE '%#{escaped_query}%'
      OR Email LIKE '%#{escaped_query}%'
      OR Phone LIKE '%#{escaped_query}%'
      #{id_clause}
    ORDER BY LastModifiedDate DESC
    LIMIT 10
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp contact_soql(contact_id) do
    escaped_id = escape_id(contact_id)

    """
    SELECT #{Enum.join(@contact_fields, ", ")}
    FROM Contact
    WHERE Id = '#{escaped_id}'
    LIMIT 1
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_updates(updates) do
    updates
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = key |> to_string() |> String.downcase()

      case Map.get(@updatable_field_map, key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
  end

  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status in [408, 429], do: true
  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status >= 500, do: true
  defp should_retry?({:error, :timeout}, _env, _ctx), do: true
  defp should_retry?({:error, :econnrefused}, _env, _ctx), do: true
  defp should_retry?({:error, :closed}, _env, _ctx), do: true
  defp should_retry?(_, _, _), do: false

  defp format_contact(%{"Id" => id} = record) do
    %{
      id: id,
      firstname: record["FirstName"],
      lastname: record["LastName"],
      email: record["Email"],
      phone: record["Phone"],
      mobilephone: record["MobilePhone"],
      company: get_in(record, ["Account", "Name"]),
      jobtitle: record["Title"],
      address: record["MailingStreet"],
      city: record["MailingCity"],
      state: record["MailingState"],
      zip: record["MailingPostalCode"],
      country: record["MailingCountry"],
      display_name: format_display_name(record)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(record) do
    firstname = record["FirstName"] || ""
    lastname = record["LastName"] || ""
    email = record["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")
    if name == "", do: email, else: name
  end

  defp escape_id(value) when is_binary(value), do: String.replace(value, "'", "\\\\'")

  defp escape_like(value) when is_binary(value),
    do: escape_id(value) |> String.replace("%", "\\%")

  defp salesforce_id?(value) when is_binary(value) do
    String.match?(value, ~r/^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/)
  end
end
