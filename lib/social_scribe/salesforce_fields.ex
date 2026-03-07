defmodule SocialScribe.SalesforceFields do
  @moduledoc """
  Shared Salesforce contact field metadata for suggestion and mapping flows.
  """

  @allowed_fields [
    "firstname",
    "lastname",
    "email",
    "phone",
    "mobilephone",
    "jobtitle",
    "address",
    "city",
    "state",
    "zip",
    "country",
    "company"
  ]

  @field_labels %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "Mobile Phone",
    "jobtitle" => "Job Title",
    "address" => "Address",
    "city" => "City",
    "state" => "State",
    "zip" => "ZIP Code",
    "country" => "Country",
    "company" => "Company"
  }

  @allowed_field_set MapSet.new(@allowed_fields)

  def allowed_fields, do: @allowed_fields
  def labels, do: @field_labels

  def label(field) when is_binary(field), do: Map.get(@field_labels, field, field)

  def valid_field?(field) when is_binary(field), do: MapSet.member?(@allowed_field_set, field)
  def valid_field?(_), do: false

  def normalize_mappings(mappings) when is_map(mappings) do
    mappings
    |> Enum.reduce(%{}, fn
      {source, target}, acc when is_binary(source) and is_binary(target) ->
        if valid_field?(source) and valid_field?(target) do
          Map.put(acc, source, target)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  def normalize_mappings(_), do: %{}
end
