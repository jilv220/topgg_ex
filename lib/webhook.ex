defmodule TopggEx.Webhook do
  @moduledoc """
  Top.gg Webhook handler for Plug-based HTTP servers.

  This module provides webhook handling functionality for receiving vote notifications
  from Top.gg, compatible with Phoenix and other Plug-based HTTP servers.

  ## Examples

      # In your Phoenix router or Plug router:
      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import TopggEx.Webhook

        pipeline :webhook do
          plug :accepts, ["json"]
          plug TopggEx.Webhook, authorization: "your_webhook_auth_token"
        end

        scope "/webhooks" do
          pipe_through :webhook
          post "/topgg", YourController, :handle_vote
        end
      end

      # In your controller:
      defmodule YourController do
        use MyAppWeb, :controller

                def handle_vote(conn, _params) do
          case conn.assigns.topgg_payload do
            %{"user" => user_id, "type" => "upvote"} ->
              # Handle the vote
              IO.puts("User \#{user_id} voted!")
              send_resp(conn, 204, "")

            %{"user" => user_id, "type" => "test"} ->
              # Handle test webhook
              IO.puts("Test webhook from user \#{user_id}")
              send_resp(conn, 204, "")

            _ ->
              send_resp(conn, 400, "Invalid payload")
          end
        end
      end

  ## Functional API

  You can also use the functional API for more control:

      # Verify and parse a webhook request
      case TopggEx.Webhook.verify_and_parse(conn, "your_auth_token") do
        {:ok, payload} ->
          # Handle the vote payload
          IO.inspect(payload)

        {:error, :unauthorized} ->
          # Handle unauthorized request
          send_resp(conn, 403, Jason.encode!(%{error: "Unauthorized"}))

        {:error, :invalid_body} ->
          # Handle malformed request
          send_resp(conn, 400, Jason.encode!(%{error: "Invalid body"}))
      end

  ## Webhook Data Schema

  The webhook payload typically contains:
  - `user` - The ID of the user who voted
  - `type` - The type of vote ("upvote" or "test")
  - `bot` - The ID of the bot that was voted for
  - `isWeekend` - Whether the vote was cast on a weekend (counts as 2 votes)
  - `query` - Query parameters from the vote page (if any)

  ## Links

  - [Top.gg Webhook Documentation](https://docs.top.gg/resources/webhooks/)
  - [Top.gg Webhook Schema](https://docs.top.gg/resources/webhooks/#schema)
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @type webhook_payload :: %{
          String.t() => String.t() | boolean() | map()
        }

  @type webhook_options :: [
          authorization: String.t(),
          error_handler: (any() -> any()),
          assign_key: atom()
        ]

  defstruct [:authorization, :error_handler, :assign_key]

  @impl Plug
  def init(opts) do
    %__MODULE__{
      authorization: Keyword.get(opts, :authorization),
      error_handler: Keyword.get(opts, :error_handler, :default),
      assign_key: Keyword.get(opts, :assign_key, :topgg_payload)
    }
  end

  @impl Plug
  def call(conn, %__MODULE__{} = options) do
    # Skip processing if response has already been sent
    if response_sent?(conn) do
      conn
    else
      case verify_and_parse(conn, options.authorization) do
        {:ok, payload} ->
          assign(conn, options.assign_key, payload)

        {:error, :unauthorized} ->
          conn
          |> send_error_response(403, "Unauthorized")
          |> halt()

        {:error, :invalid_body} ->
          conn
          |> send_error_response(400, "Invalid body")
          |> halt()

        {:error, :malformed_request} ->
          conn
          |> send_error_response(422, "Malformed request")
          |> halt()

        {:error, :invalid_payload_format} ->
          conn
          |> send_error_response(400, "Invalid payload format")
          |> halt()

        {:error, {:missing_fields, fields}} ->
          conn
          |> send_error_response(400, "Missing required fields: #{Enum.join(fields, ", ")}")
          |> halt()

        {:error, {:invalid_field_type, field}} ->
          conn
          |> send_error_response(400, "Invalid type for field: #{field}")
          |> halt()
      end
    end
  end

  @doc """
  Verifies the authorization header and parses the webhook payload.

  ## Parameters

    * `conn` - The Plug connection
    * `expected_auth` - The expected authorization token (optional)

  ## Returns

    * `{:ok, payload}` - Successfully parsed and validated webhook payload
    * `{:error, :unauthorized}` - Authorization header doesn't match
    * `{:error, :invalid_body}` - Request body is not valid JSON
    * `{:error, :malformed_request}` - Error reading request body
    * `{:error, :invalid_payload_format}` - Payload is not a map
    * `{:error, {:missing_fields, fields}}` - Required fields are missing
    * `{:error, {:invalid_field_type, field}}` - Field has incorrect type

  ## Examples

             case TopggEx.Webhook.verify_and_parse(conn, "my_auth_token") do
         {:ok, payload} ->
           IO.puts("Received vote from user: \#{payload["user"]}")

         {:error, reason} ->
           IO.puts("Webhook error: \#{inspect(reason)}")
       end

  """
  @spec verify_and_parse(Plug.Conn.t(), String.t() | nil) ::
          {:ok, webhook_payload()}
          | {:error, :unauthorized | :invalid_body | :malformed_request | :invalid_payload_format}
          | {:error, {:missing_fields, [String.t()]}}
          | {:error, {:invalid_field_type, String.t()}}
  def verify_and_parse(conn, expected_auth \\ nil) do
    with :ok <- verify_authorization(conn, expected_auth),
         {:ok, body} <- read_request_body(conn),
         {:ok, payload} <- parse_body(body),
         {:ok, validated_payload} <- validate_payload(payload) do
      formatted_payload = format_incoming(validated_payload)
      {:ok, formatted_payload}
    end
  end

  @doc """
  Creates a functional webhook handler that can be used in controllers or other contexts.

  ## Parameters

    * `handler_fun` - Function that takes the payload and connection
    * `opts` - Options including `:authorization` and `:error_handler`

  ## Returns

  A function that can be used as a Plug or called directly.

  ## Examples

             webhook_handler = TopggEx.Webhook.listener(fn payload, conn ->
         IO.puts("User \#{payload["user"]} voted!")
         send_resp(conn, 204, "")
       end, authorization: "my_auth_token")

      # Use in a router
      post "/webhook", webhook_handler

  """
  @spec listener((webhook_payload(), Plug.Conn.t() -> Plug.Conn.t()), webhook_options()) ::
          (Plug.Conn.t(), any() -> Plug.Conn.t())
  def listener(handler_fun, opts \\ []) when is_function(handler_fun, 2) do
    authorization = Keyword.get(opts, :authorization)
    error_handler = Keyword.get(opts, :error_handler, :default)

    fn conn, _opts ->
      case verify_and_parse(conn, authorization) do
        {:ok, payload} ->
          try do
            conn = handler_fun.(payload, conn)

            # Send default response safely
            send_default_response(conn)
          rescue
            error ->
              handle_error(error_handler, error)

              # Send error response safely
              send_error_response(conn, 500, "Internal server error")
          end

        {:error, :unauthorized} ->
          send_error_response(conn, 403, "Unauthorized")

        {:error, :invalid_body} ->
          send_error_response(conn, 400, "Invalid body")

        {:error, :malformed_request} ->
          send_error_response(conn, 422, "Malformed request")

        {:error, :invalid_payload_format} ->
          send_error_response(conn, 400, "Invalid payload format")

        {:error, {:missing_fields, fields}} ->
          send_error_response(conn, 400, "Missing required fields: #{Enum.join(fields, ", ")}")

        {:error, {:invalid_field_type, field}} ->
          send_error_response(conn, 400, "Invalid type for field: #{field}")
      end
    end
  end

  # Private helper functions

  defp verify_authorization(_conn, nil), do: :ok

  defp verify_authorization(conn, expected_auth) do
    case get_req_header(conn, "authorization") do
      [^expected_auth] -> :ok
      _other -> {:error, :unauthorized}
    end
  end

  defp read_request_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> {:ok, body}
      {:more, _partial, _conn} -> {:error, :malformed_request}
      {:error, _reason} -> {:error, :malformed_request}
    end
  end

  defp parse_body(body) do
    case Jason.decode(body) do
      {:ok, payload} -> {:ok, payload}
      {:error, _reason} -> {:error, :invalid_body}
    end
  end

  defp validate_payload(payload) when is_map(payload) do
    required_fields = ["bot", "user", "type"]

    with :ok <- validate_required_fields(payload, required_fields),
         :ok <- validate_field_types(payload) do
      {:ok, payload}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_payload(_payload), do: {:error, :invalid_payload_format}

  defp validate_required_fields(payload, required_fields) do
    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(payload, &1))

    case missing_fields do
      [] -> :ok
      missing -> {:error, {:missing_fields, missing}}
    end
  end

  defp validate_field_types(payload) do
    validations = [
      {"bot", &is_binary/1},
      {"user", &is_binary/1},
      {"type", &is_binary/1},
      {"isWeekend", &is_boolean/1, :optional},
      {"query", &(is_binary(&1) or is_map(&1)), :optional}
    ]

    case validate_types(payload, validations) do
      :ok -> :ok
      {:error, field} -> {:error, {:invalid_field_type, field}}
    end
  end

  defp validate_types(_payload, []), do: :ok

  defp validate_types(payload, [{field, validator} | rest]) do
    case Map.get(payload, field) do
      nil ->
        {:error, field}

      value ->
        if validator.(value) do
          validate_types(payload, rest)
        else
          {:error, field}
        end
    end
  end

  defp validate_types(payload, [{field, validator, :optional} | rest]) do
    case Map.get(payload, field) do
      nil ->
        validate_types(payload, rest)

      value ->
        if validator.(value) do
          validate_types(payload, rest)
        else
          {:error, field}
        end
    end
  end

  defp format_incoming(payload) when is_map(payload) do
    case Map.get(payload, "query") do
      query when is_binary(query) and byte_size(query) > 0 ->
        parsed_query = URI.decode_query(query)
        Map.put(payload, "query", parsed_query)

      _other ->
        payload
    end
  end

  defp handle_error(:default, error), do: default_error_handler(error)
  defp handle_error(handler, error) when is_function(handler, 1), do: handler.(error)

  defp default_error_handler(error) do
    Logger.error("TopggEx.Webhook error: #{inspect(error)}")
  end

  # Helper function to safely send JSON error responses
  defp send_error_response(conn, status, error_message) do
    if response_sent?(conn) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(%{error: error_message}))
    end
  end

  # Helper function to safely send a default response
  defp send_default_response(conn) do
    if response_sent?(conn) do
      conn
    else
      send_resp(conn, 204, "")
    end
  end

  # Helper function to check if response has been sent
  # This works across different Plug versions
  defp response_sent?(conn) do
    conn.state in [:sent, :chunked]
  end
end
