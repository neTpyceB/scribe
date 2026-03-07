defmodule SocialScribe.RateLimiterTest do
  use ExUnit.Case, async: true

  alias SocialScribe.RateLimiter

  setup do
    prev = Application.get_env(:social_scribe, :limits)

    Application.put_env(:social_scribe, :limits, %{
      rate_limits: %{
        auth_start_window_ms: 60_000,
        auth_start_max_requests: 1
      }
    })

    RateLimiter.reset()

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:social_scribe, :limits)
      else
        Application.put_env(:social_scribe, :limits, prev)
      end

      RateLimiter.reset()
    end)

    :ok
  end

  test "allows first request and blocks second request in same window" do
    assert :ok = RateLimiter.allow(:auth_start, "user:1", 1_000)
    assert {:error, retry_after_ms} = RateLimiter.allow(:auth_start, "user:1", 1_500)
    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  test "allows requests again in next window" do
    assert :ok = RateLimiter.allow(:auth_start, "user:1", 1_000)
    assert {:error, _} = RateLimiter.allow(:auth_start, "user:1", 2_000)

    assert :ok = RateLimiter.allow(:auth_start, "user:1", 61_000)
  end
end
