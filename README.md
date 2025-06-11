# TopggEx

[![Hex.pm](https://img.shields.io/hexpm/v/topgg_ex.svg)](https://hex.pm/packages/topgg_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/topgg_ex/)
[![License](https://img.shields.io/hexpm/l/topgg_ex.svg)](https://github.com/jilv220/topgg_ex/blob/master/LICENSE)

A community Elixir SDK for the [Top.gg](https://top.gg) API, allowing you to interact with Discord bot statistics, user votes, and bot information.

## Features

- 🚀 **Complete API Coverage**: All Top.gg API endpoints supported
- 🎯 **Webhook Support**: Built-in webhook handler for vote notifications
- 🔒 **Type Safety**: Full typespecs and structured data
- ⚡ **HTTP/2 Support**: Built on Finch for modern HTTP performance
- 🧪 **Well Tested**: Comprehensive test suite with 95%+ coverage
- 📚 **Excellent Documentation**: Detailed docs with examples
- 🏗️ **Clean Architecture**: Separated HTTP client for maintainability

## Installation

Add `topgg_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:topgg_ex, "~> 0.1.0"},
    {:finch, "~> 0.19"}  # Required HTTP client
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Setup

First, add Finch to your application's supervision tree:

```elixir
# In your application.ex
children = [
  {Finch, name: :topgg_finch}
]
```

### 2. Create API Client

```elixir
# Get your token from https://top.gg/api/docs#mybots
{:ok, api} = TopggEx.Api.new("your_topgg_token_here")
```

### 3. Post Bot Statistics

```elixir
# Update your bot's server count
{:ok, stats} = TopggEx.Api.post_stats(api, %{server_count: 1250})
```

## Usage Examples

### Bot Statistics

```elixir
# Post bot stats
{:ok, _} = TopggEx.Api.post_stats(api, %{
  server_count: 1250,
  shard_count: 2,
  shards: [625, 625]
})

# Get your bot's current stats
{:ok, stats} = TopggEx.Api.get_stats(api)
# => %{server_count: 1250, shard_count: 2, shards: [625, 625]}
```

### Bot Information

```elixir
# Get information about any bot
{:ok, bot} = TopggEx.Api.get_bot(api, "461521980492087297")
# => %{"id" => "461521980492087297", "username" => "Shiro", ...}

# Search for bots
{:ok, results} = TopggEx.Api.get_bots(api, %{
  search: %{username: "music"},
  limit: 10,
  fields: ["id", "username", "short_description"]
})
```

### Vote Checking

```elixir
# Check if a user has voted
{:ok, has_voted?} = TopggEx.Api.has_voted(api, "205680187394752512")
# => true or false

# Get recent voters
{:ok, voters} = TopggEx.Api.get_votes(api)
# => [%{"username" => "Example", "id" => "123...", "avatar" => "https://..."}, ...]

# Check weekend multiplier status
{:ok, is_weekend?} = TopggEx.Api.is_weekend(api)
# => true or false
```

### Webhook Handling

TopggEx includes a built-in webhook handler for receiving vote notifications from Top.gg.

#### Using the Functional Listener (Recommended)

The easiest way to handle webhooks is using the `listener` function:

```elixir
# In your Phoenix router
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Create the webhook handler
  webhook_handler = TopggEx.Webhook.listener(fn payload, conn ->
    case payload do
      %{"user" => user_id, "type" => "upvote", "bot" => bot_id} ->
        # Handle the vote
        MyApp.handle_user_vote(user_id, bot_id)
        IO.puts("User #{user_id} voted for bot #{bot_id}!")

      %{"user" => user_id, "type" => "test"} ->
        # Handle test webhook
        IO.puts("Test webhook from user: #{user_id}")
    end

    # Response is handled automatically by the listener
  end, authorization: "your_webhook_auth_token")

  scope "/webhooks" do
    pipe_through :api
    post "/topgg", webhook_handler
  end
end
```

#### Using as Plug Middleware (Alternative)

You can also use the webhook handler as Plug middleware:

```elixir
# In your Phoenix router
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :webhook do
    plug :accepts, ["json"]
    plug TopggEx.Webhook, authorization: "your_webhook_auth_token"
  end

  scope "/webhooks" do
    pipe_through :webhook
    post "/topgg", MyAppWeb.WebhookController, :handle_vote
  end
end

# In your controller
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  def handle_vote(conn, _params) do
    case conn.assigns.topgg_payload do
      %{"user" => user_id, "type" => "upvote", "bot" => bot_id} ->
        # Handle the vote
        MyApp.handle_user_vote(user_id, bot_id)
        send_resp(conn, 204, "")

      %{"user" => user_id, "type" => "test"} ->
        # Handle test webhook
        IO.puts("Test webhook from user: #{user_id}")
        send_resp(conn, 204, "")
    end
  end
end
```

#### Manual Webhook Processing

For maximum control, you can use the functional API to manually parse webhooks:

```elixir
def handle_webhook(conn) do
  case TopggEx.Webhook.verify_and_parse(conn, "your_auth_token") do
    {:ok, payload} ->
      case payload do
        %{"user" => user_id, "type" => "upvote", "bot" => bot_id} ->
          MyApp.process_vote(user_id, bot_id)
          send_resp(conn, 204, "")

        %{"user" => user_id, "type" => "test"} ->
          IO.puts("Test webhook from user: #{user_id}")
          send_resp(conn, 204, "")


      end

    {:error, :unauthorized} ->
      send_resp(conn, 403, Jason.encode!(%{error: "Unauthorized"}))

    {:error, :invalid_body} ->
      send_resp(conn, 400, Jason.encode!(%{error: "Invalid body"}))

    {:error, reason} ->
      send_resp(conn, 400, Jason.encode!(%{error: "Webhook error: #{inspect(reason)}"}))
  end
end
```

#### Advanced Listener Usage

You can create more sophisticated webhook handlers with error handling and custom logic:

```elixir
webhook_handler = TopggEx.Webhook.listener(fn payload, conn ->
  %{"user" => user_id, "type" => vote_type, "bot" => bot_id} = payload

  case vote_type do
    "upvote" ->
      # Record the vote and handle weekend multiplier
      is_weekend = Map.get(payload, "isWeekend", false)
      vote_count = if is_weekend, do: 2, else: 1

      MyApp.record_vote(user_id, bot_id, vote_count)
      MyApp.send_thank_you(user_id)

      IO.puts("User #{user_id} voted! (#{vote_count} votes)")

    "test" ->
      IO.puts("Test webhook received from user #{user_id}!")


  end

  # Response is handled automatically by the listener
  # No need to call send_resp/3
end, authorization: "your_webhook_auth_token")

# Use in router
post "/webhook", webhook_handler
```

### Advanced Usage

```elixir
# Custom Finch instance
{:ok, api} = TopggEx.Api.new("your_token", %{
  finch_name: :my_custom_finch,
  base_url: "https://top.gg/api"  # Optional custom base URL
})

# Complex bot search
{:ok, results} = TopggEx.Api.get_bots(api, %{
  search: %{
    username: "music bot",
    tags: "music"
  },
  sort: "server_count",
  limit: 50,
  fields: ["id", "username", "short_description", "server_count"]
})
```

## API Reference

### Core Functions

#### API Client (`TopggEx.Api`)

| Function       | Description              | Parameters         |
| -------------- | ------------------------ | ------------------ |
| `new/2`        | Create API client        | `token`, `options` |
| `post_stats/2` | Update bot statistics    | `api`, `stats`     |
| `get_stats/1`  | Get bot statistics       | `api`              |
| `get_bot/2`    | Get bot information      | `api`, `bot_id`    |
| `get_bots/2`   | Search bots              | `api`, `query`     |
| `get_votes/2`  | Get recent voters        | `api`, `page`      |
| `has_voted/2`  | Check user vote status   | `api`, `user_id`   |
| `is_weekend/1` | Check weekend multiplier | `api`              |

#### Webhook Handler (`TopggEx.Webhook`)

| Function             | Description                    | Parameters              |
| -------------------- | ------------------------------ | ----------------------- |
| `verify_and_parse/2` | Parse webhook payload          | `conn`, `auth_token`    |
| `listener/2`         | Create functional handler      | `handler_fun`, `opts`   |
| Plug behavior        | Use as Phoenix/Plug middleware | `authorization`, `opts` |

### Error Handling

All functions return `{:ok, result}` on success or `{:error, reason}` on failure:

```elixir
case TopggEx.Api.post_stats(api, %{server_count: 100}) do
  {:ok, stats} ->
    IO.puts("Stats updated successfully!")
  {:error, %{status: 401}} ->
    IO.puts("Invalid API token")
  {:error, %{status: 429}} ->
    IO.puts("Rate limited - try again later")
  {:error, reason} ->
    IO.puts("Network error: #{inspect(reason)}")
end
```

## Configuration

### Environment Variables

You can set your Top.gg token via environment variables:

```elixir
# config/runtime.exs
config :my_app, :topgg_token, System.get_env("TOPGG_TOKEN")

# In your application
token = Application.get_env(:my_app, :topgg_token)
{:ok, api} = TopggEx.Api.new(token)
```

### Custom HTTP Client Options

```elixir
{:ok, api} = TopggEx.Api.new("your_token", %{
  finch_name: :my_finch,      # Custom Finch instance name
  base_url: "https://top.gg/api"  # Custom API base URL
})
```

## Rate Limiting

Top.gg API has rate limits. The library will return appropriate errors:

- **429 Too Many Requests**: You've hit the rate limit
- **403 Forbidden**: Invalid token or insufficient permissions

Implement exponential backoff for production applications:

```elixir
defmodule MyBot.Stats do
  def update_stats_with_retry(api, stats, retries \\ 3) do
    case TopggEx.Api.post_stats(api, stats) do
      {:ok, result} -> {:ok, result}
      {:error, %{status: 429}} when retries > 0 ->
        Process.sleep(1000 * (4 - retries))  # Exponential backoff
        update_stats_with_retry(api, stats, retries - 1)
      error -> error
    end
  end
end
```

## Testing

The library includes comprehensive tests. Run them with:

```bash
mix test
```

For testing your own applications, you can mock the HTTP client:

```elixir
# In your tests
setup do
  bypass = Bypass.open()

  {:ok, api} = TopggEx.Api.new("test_token", %{
    base_url: "http://localhost:#{bypass.port}/api"
  })

  {:ok, %{bypass: bypass, api: api}}
end
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Generate documentation
mix docs

# Check formatting
mix format --check-formatted

# Run static analysis
mix dialyzer
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- [Top.gg API Documentation](https://docs.top.gg)
- [Hex Package](https://hex.pm/packages/topgg_ex)
- [Documentation](https://hexdocs.pm/topgg_ex/)
- [GitHub Repository](https://github.com/jilv220/topgg_ex)

## Acknowledgments

- Thanks to the [Top.gg](https://top.gg) team for providing the API
- Built with [Finch](https://github.com/sneako/finch) for modern HTTP performance
- Inspired by the JavaScript [topgg.js](https://github.com/top-gg/node-sdk) library
