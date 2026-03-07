defmodule SocialScribe.ErrorMapper do
  @moduledoc """
  Normalizes error tuples from external integrations and validation layers.
  """

  def invalid_input(reason), do: {:invalid_input, reason}

  def api(status, body), do: {:api_error, status, body}

  def http(reason) do
    case reason do
      :timeout -> {:upstream_timeout, reason}
      {:timeout, _} -> {:upstream_timeout, reason}
      :connect_timeout -> {:upstream_timeout, reason}
      _ -> {:upstream_unavailable, reason}
    end
  end
end
