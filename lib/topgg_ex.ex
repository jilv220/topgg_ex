defmodule TopggEx do
  @moduledoc """
  A comprehensive Elixir client for the Top.gg API.

  TopggEx provides a complete client for interacting with the Top.gg API,
  allowing you to post bot statistics, retrieve bot information, check votes,
  and handle webhooks with full type safety and excellent documentation.

  ## Main Modules

  - `TopggEx.Api` - Client for interacting with the Top.gg REST API
  - `TopggEx.Webhook` - Webhook handler for receiving vote notifications

  ## Quick Start

  ### API Client

      # Create a new API client
      {:ok, api} = TopggEx.Api.new("your_topgg_token_here")

      # Post bot statistics
      {:ok, _stats} = TopggEx.Api.post_stats(api, %{server_count: 100})

      # Get bot information
      {:ok, bot} = TopggEx.Api.get_bot(api, "bot_id")

  ### Webhook Handler

      # In your Phoenix router
      pipeline :webhook do
        plug :accepts, ["json"]
        plug TopggEx.Webhook, authorization: "your_webhook_auth_token"
      end

      scope "/webhooks" do
        pipe_through :webhook
        post "/topgg", YourController, :handle_vote
      end

  ## Configuration

  Before using the API client, ensure you have a Finch instance running
  in your application supervision tree:

      children = [
        {Finch, name: :topgg_finch}
      ]

  ## Links

  - [Top.gg API Documentation](https://docs.top.gg)
  - [Top.gg Webhook Documentation](https://docs.top.gg/resources/webhooks/)
  """
end
