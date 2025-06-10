defmodule TopggEx.HttpClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This behaviour defines the contract for HTTP clients used by the TopggEx API.
  It enables dependency injection and mocking for testing purposes.
  """

  @type request_options :: %{
          token: String.t(),
          finch_name: atom(),
          base_url: String.t()
        }

  @callback request(request_options(), atom(), String.t(), map() | nil) ::
              {:ok, any()} | {:error, any()}
end
