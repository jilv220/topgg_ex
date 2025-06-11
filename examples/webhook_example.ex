defmodule WebhookExample do
  @moduledoc """
  Example demonstrating how to use TopggEx.Webhook in different scenarios.

  This module shows various ways to integrate the webhook handler
  with Phoenix applications or other Plug-based HTTP servers.
  """

  # Example 1: Using as a Plug in Phoenix router
  defmodule Phoenix.Router.Example do
    @moduledoc """
    Example Phoenix router configuration with TopggEx.Webhook
    """

    # In your Phoenix router file (e.g., lib/my_app_web/router.ex)
    def example_router_setup do
      quote do
        pipeline :webhook do
          plug :accepts, ["json"]
          plug TopggEx.Webhook, authorization: "your_webhook_auth_token_here"
        end

        scope "/webhooks" do
          pipe_through :webhook
          post "/topgg", MyAppWeb.WebhookController, :handle_vote
        end
      end
    end
  end

  # Example 2: Controller handling the webhook
  defmodule Phoenix.Controller.Example do
    @moduledoc """
    Example controller for handling Top.gg webhooks
    """

    def handle_vote(conn, _params) do
      # The webhook payload is automatically parsed and available in conn.assigns
      case conn.assigns.topgg_payload do
        %{"user" => user_id, "type" => "upvote", "bot" => bot_id} ->
          # Handle upvote
          handle_user_vote(user_id, bot_id, false)
          send_resp(conn, 204, "")

        %{"user" => user_id, "type" => "upvote", "bot" => bot_id, "isWeekend" => true} ->
          # Handle weekend vote (counts as 2 votes)
          handle_user_vote(user_id, bot_id, true)
          send_resp(conn, 204, "")

        %{"user" => user_id, "type" => "test"} ->
          # Handle test webhook
          IO.puts("Test webhook received from user: #{user_id}")
          send_resp(conn, 204, "")

        payload ->
          # Handle unexpected payload
          IO.warn("Unexpected webhook payload: #{inspect(payload)}")
          send_resp(conn, 400, Jason.encode!(%{error: "Invalid payload"}))
      end
    end

    defp handle_user_vote(user_id, bot_id, is_weekend) do
      vote_count = if is_weekend, do: 2, else: 1

      # Your vote handling logic here
      IO.puts("User #{user_id} voted for bot #{bot_id} (#{vote_count} votes)")

      # Example: Update database, send notifications, etc.
      # MyApp.Votes.record_vote(user_id, bot_id, vote_count)
      # MyApp.Notifications.send_vote_notification(user_id, bot_id)
    end
  end

  # Example 3: Using the functional API
  defmodule Functional.API.Example do
    @moduledoc """
    Example using the functional API for more control
    """

    def handle_webhook_manually(conn) do
      case TopggEx.Webhook.verify_and_parse(conn, "your_auth_token") do
        {:ok, payload} ->
          process_vote(payload)
          send_resp(conn, 204, "")

        {:error, :unauthorized} ->
          send_resp(conn, 403, Jason.encode!(%{error: "Unauthorized"}))

        {:error, :invalid_body} ->
          send_resp(conn, 400, Jason.encode!(%{error: "Invalid body"}))

        {:error, :malformed_request} ->
          send_resp(conn, 422, Jason.encode!(%{error: "Malformed request"}))

        {:error, reason} ->
          IO.error("Webhook processing error: #{inspect(reason)}")
          send_resp(conn, 500, Jason.encode!(%{error: "Internal server error"}))
      end
    end

    defp process_vote(%{"user" => user_id, "type" => type} = payload) do
      IO.puts("Processing #{type} from user #{user_id}")

      # Handle query parameters if present
      case Map.get(payload, "query") do
        %{} = query_params when map_size(query_params) > 0 ->
          IO.puts("Query parameters: #{inspect(query_params)}")

        _ ->
          :ok
      end
    end
  end

  # Example 4: Using the listener function
  defmodule Listener.Example do
    @moduledoc """
    Example using TopggEx.Webhook.listener/2 for custom handling
    """

    def create_webhook_handler do
      TopggEx.Webhook.listener(
        &handle_vote_payload/2,
        authorization: "your_webhook_auth_token",
        error_handler: &handle_webhook_error/1
      )
    end

    defp handle_vote_payload(payload, conn) do
      %{"user" => user_id, "type" => vote_type} = payload

      # Your custom vote processing logic
      case vote_type do
        "upvote" ->
          record_vote(user_id, payload)
          maybe_send_thank_you(user_id)

        "test" ->
          IO.puts("Test webhook - everything working!")

        unknown ->
          IO.warn("Unknown vote type: #{unknown}")
      end

      # Return the connection (response will be sent automatically)
      conn
    end

    defp handle_webhook_error(error) do
      # Custom error handling
      IO.error("Webhook error occurred: #{inspect(error)}")

      # You could send notifications, log to external service, etc.
      # ErrorReporter.report(error)
    end

    defp record_vote(user_id, payload) do
      # Your vote recording logic
      IO.puts("Recording vote from user #{user_id}")
      IO.inspect(payload, label: "Full payload")
    end

    defp maybe_send_thank_you(user_id) do
      # Optional: Send a thank you message to the user
      IO.puts("Sending thank you to user #{user_id}")
    end
  end

  # Example 5: Standalone Plug application
  defmodule Standalone.Example do
    @moduledoc """
    Example of using TopggEx.Webhook in a standalone Plug application
    """

    use Plug.Router

    plug :match
    plug :dispatch

    # Using the webhook as a plug with custom assignment key
    plug TopggEx.Webhook,
         authorization: "your_webhook_auth_token",
         assign_key: :vote_data

    post "/webhook" do
      case conn.assigns.vote_data do
        %{"user" => user_id} ->
          IO.puts("Received vote from #{user_id}")
          send_resp(conn, 204, "")

        _ ->
          send_resp(conn, 400, "Invalid vote data")
      end
    end

    match _ do
      send_resp(conn, 404, "Not found")
    end
  end
end
