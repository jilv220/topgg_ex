defmodule TopggEx.Api do
  @moduledoc """
  Top.gg API Client for posting stats and fetching data.

  This module provides a comprehensive client for interacting with the Top.gg API,
  allowing you to post bot statistics, retrieve bot information, check votes, and more.

  ## Examples

      iex> {:ok, api} = TopggEx.Api.new("your_topgg_token_here")
      iex> {:ok, _stats} = TopggEx.Api.post_stats(api, %{server_count: 100})
      {:ok, %{server_count: 100}}

  ## Configuration

  Before using this module, ensure you have a Finch instance running in your
  application supervision tree:

      children = [
        {Finch, name: :topgg_finch}
      ]

  ## See also

  - [Top.gg API Documentation](https://docs.top.gg)
  - [Top.gg Library Documentation](https://topgg.js.org)
  """

  require Logger

  @type snowflake :: String.t()
  @type api_options :: %{
          optional(:finch_name) => atom(),
          optional(:base_url) => String.t()
        }

  @type post_stats_body :: %{
          required(:server_count) => non_neg_integer() | [non_neg_integer()],
          optional(:shard_count) => non_neg_integer(),
          optional(:shards) => [non_neg_integer()],
          optional(:shard_id) => non_neg_integer()
        }

  @type bot_stats_response :: %{
          optional(:server_count) => non_neg_integer(),
          required(:shards) => [non_neg_integer()],
          optional(:shard_count) => non_neg_integer()
        }

  @type bot_info :: map()
  @type user_info :: map()
  @type short_user :: %{
          username: String.t(),
          id: snowflake(),
          avatar: String.t()
        }

  @type bots_response :: %{
          results: [bot_info()],
          limit: non_neg_integer(),
          offset: non_neg_integer(),
          count: non_neg_integer(),
          total: non_neg_integer()
        }

  @type bots_query :: %{
          optional(:limit) => non_neg_integer(),
          optional(:offset) => non_neg_integer(),
          optional(:search) => String.t() | map(),
          optional(:sort) => String.t(),
          optional(:fields) => [String.t()] | String.t()
        }

  defstruct [:token, :finch_name, :base_url]

  @type t :: %__MODULE__{
          token: String.t(),
          finch_name: atom(),
          base_url: String.t()
        }

  @doc """
  Creates a new Top.gg API client instance.

  Returns `:ok` with the API client struct, or `{:error, reason}` if the token is malformed.

  ## Parameters

    * `token` - Your Top.gg API token
    * `options` - Optional configuration map

  ## Options

    * `:finch_name` - Name of the Finch instance to use (default: `:topgg_finch`)
    * `:base_url` - Base URL for the API (default: `"https://top.gg/api"`)

  ## Examples

      iex> {:ok, api} = TopggEx.Api.new("your_token_here")
      iex> {:ok, api} = TopggEx.Api.new("your_token_here", %{finch_name: :my_finch})

  """
  @spec new(String.t(), api_options()) :: {:ok, t()} | {:error, String.t()}
  def new(token, options \\ %{}) when is_binary(token) do
    with :ok <- validate_token(token) do
      api = %__MODULE__{
        token: token,
        finch_name: Map.get(options, :finch_name, :topgg_finch),
        base_url: Map.get(options, :base_url, "https://top.gg/api")
      }

      {:ok, api}
    end
  end

  @doc """
  Posts bot statistics to Top.gg.

  Returns `{:ok, stats}` on success, or `{:error, reason}` if the server count
  is missing, invalid, or the API request fails.

  ## Parameters

    * `api` - API client instance
    * `stats` - Stats map containing at least `:server_count`

  ## Examples

      # Posting server count as an integer
      iex> {:ok, stats} = TopggEx.Api.post_stats(api, %{server_count: 28199})
      {:ok, %{server_count: 28199}}

      # Posting with shards (server_count as array)
      iex> {:ok, stats} = TopggEx.Api.post_stats(api, %{server_count: [1000, 2000, 3000]})
      {:ok, %{server_count: [1000, 2000, 3000]}}

      # Posting with additional shard information
      iex> {:ok, stats} = TopggEx.Api.post_stats(api, %{
      ...>   server_count: 500,
      ...>   shard_id: 0,
      ...>   shard_count: 5
      ...> })
      {:ok, %{server_count: 500, shard_id: 0, shard_count: 5}}

  """
  @spec post_stats(t(), post_stats_body()) :: {:ok, post_stats_body()} | {:error, any()}
  def post_stats(%__MODULE__{} = api, %{server_count: server_count} = stats)
      when (is_integer(server_count) and server_count > 0) or
             (is_list(server_count) and length(server_count) > 0) do
    body =
      %{server_count: server_count}
      |> maybe_add_field(stats, :shard_count)
      |> maybe_add_field(stats, :shards)
      |> maybe_add_field(stats, :shard_id)

    case http_request(api, :post, "/bots/stats", body) do
      {:ok, _response} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  def post_stats(_api, _stats) do
    {:error, "Missing or invalid server count"}
  end

  @doc """
  Gets your bot's statistics from Top.gg.

  Returns `{:ok, stats}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance

  ## Examples

      iex> {:ok, stats} = TopggEx.Api.get_stats(api)
      {:ok, %{server_count: 28199, shard_count: 5, shards: [5000, 5000, 5000, 5000, 8199]}}

  """
  @spec get_stats(t()) :: {:ok, bot_stats_response()} | {:error, any()}
  def get_stats(%__MODULE__{} = api) do
    case http_request(api, :get, "/bots/stats") do
      {:ok, response} ->
        stats =
          %{shards: Map.get(response, "shards", [])}
          |> maybe_add_response_field(response, "server_count", :server_count)
          |> maybe_add_response_field(response, "shard_count", :shard_count)

        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets bot information from Top.gg.

  Returns `{:ok, bot_info}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance
    * `id` - Bot ID (snowflake)

  ## Examples

      iex> {:ok, bot} = TopggEx.Api.get_bot(api, "461521980492087297")
      {:ok, %{"id" => "461521980492087297", "username" => "Shiro", ...}}

  """
  @spec get_bot(t(), snowflake()) :: {:ok, bot_info()} | {:error, any()}
  def get_bot(%__MODULE__{} = api, id) when is_binary(id) and id != "" do
    http_request(api, :get, "/bots/#{id}")
  end

  def get_bot(_api, _id) do
    {:error, "ID missing"}
  end

  @doc """
  Gets user information from Top.gg.

  Returns `{:ok, user_info}` on success, or `{:error, reason}` on failure.

  > #### Deprecated {: .warning}
  >
  > This function is deprecated and no longer supported by Top.gg API v0.

  ## Parameters

    * `api` - API client instance
    * `id` - User ID (snowflake)

  ## Examples

      iex> {:ok, user} = TopggEx.Api.get_user(api, "205680187394752512")
      {:ok, %{"id" => "205680187394752512", "username" => "Xignotic", ...}}

  """
  @spec get_user(t(), snowflake()) :: {:ok, user_info()} | {:error, any()}
  def get_user(%__MODULE__{} = api, id) when is_binary(id) and id != "" do
    Logger.warning("[DeprecationWarning] get_user is no longer supported by Top.gg API v0.")
    http_request(api, :get, "/users/#{id}")
  end

  def get_user(_api, _id) do
    {:error, "ID missing"}
  end

  @doc """
  Gets a list of bots from Top.gg.

  Returns `{:ok, bots_response}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance
    * `query` - Optional query parameters

  ## Examples

      # Finding by properties
      iex> {:ok, response} = TopggEx.Api.get_bots(api, %{
      ...>   search: %{username: "shiro"}
      ...> })
      {:ok, %{results: [%{"id" => "461521980492087297", "username" => "Shiro", ...}], ...}}

      # Restricting fields
      iex> {:ok, response} = TopggEx.Api.get_bots(api, %{
      ...>   fields: ["id", "username"]
      ...> })
      {:ok, %{results: [%{"id" => "461521980492087297", "username" => "Shiro"}], ...}}

  """
  @spec get_bots(t(), bots_query() | nil) :: {:ok, bots_response()} | {:error, any()}
  def get_bots(%__MODULE__{} = api, query \\ nil) do
    processed_query = process_bots_query(query)
    http_request(api, :get, "/bots", processed_query)
  end

  @doc """
  Gets recent unique users who have voted for your bot.

  Returns `{:ok, [users]}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance
    * `page` - Optional page number (each page has at most 100 voters)

  ## Examples

      iex> {:ok, voters} = TopggEx.Api.get_votes(api)
      {:ok, [%{username: "Xignotic", id: "205680187394752512", avatar: "https://..."}, ...]}

      iex> {:ok, voters} = TopggEx.Api.get_votes(api, 2)
      {:ok, [%{username: "iara", id: "395526710101278721", avatar: "https://..."}, ...]}

  """
  @spec get_votes(t(), non_neg_integer() | nil) :: {:ok, [short_user()]} | {:error, any()}
  def get_votes(%__MODULE__{} = api, page \\ nil) do
    query = if page, do: %{page: page}, else: %{page: 1}
    http_request(api, :get, "/bots/votes", query)
  end

  @doc """
  Checks whether or not a user has voted in the last 12 hours.

  Returns `{:ok, boolean}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance
    * `id` - User ID (snowflake)

  ## Examples

      iex> {:ok, voted?} = TopggEx.Api.has_voted(api, "205680187394752512")
      {:ok, true}

  """
  @spec has_voted(t(), snowflake()) :: {:ok, boolean()} | {:error, any()}
  def has_voted(%__MODULE__{} = api, id) when is_binary(id) and id != "" do
    case http_request(api, :get, "/bots/check", %{userId: id}) do
      {:ok, %{"voted" => voted}} -> {:ok, !!voted}
      {:error, reason} -> {:error, reason}
    end
  end

  def has_voted(_api, _id) do
    {:error, "Missing ID"}
  end

  @doc """
  Checks whether or not the weekend multiplier is active.

  Returns `{:ok, boolean}` on success, or `{:error, reason}` on failure.

  ## Parameters

    * `api` - API client instance

  ## Examples

      iex> {:ok, is_weekend?} = TopggEx.Api.is_weekend(api)
      {:ok, false}

  """
  @spec is_weekend(t()) :: {:ok, boolean()} | {:error, any()}
  def is_weekend(%__MODULE__{} = api) do
    case http_request(api, :get, "/weekend") do
      {:ok, %{"is_weekend" => is_weekend}} -> {:ok, is_weekend}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  @spec http_request(t(), atom(), String.t(), map() | nil) :: {:ok, any()} | {:error, any()}
  defp http_request(
         %__MODULE__{token: token, finch_name: finch_name, base_url: base_url},
         method,
         path,
         body \\ nil
       ) do
    options = %{
      token: token,
      finch_name: finch_name,
      base_url: base_url
    }

    TopggEx.HttpClient.request(options, method, path, body)
  end

  @spec validate_token(String.t()) :: :ok | {:error, String.t()}
  defp validate_token(token) when is_binary(token) do
    token_segments = String.split(token, ".")

    case length(token_segments) do
      3 ->
        try do
          token_data = Base.decode64!(Enum.at(token_segments, 1), padding: false)
          Jason.decode!(token_data)
          :ok
        rescue
          _ -> {:error, "Invalid API token state, this should not happen! Please report!"}
        end

      _ ->
        {:error, "Got a malformed API token."}
    end
  end

  @spec process_bots_query(bots_query() | nil) :: map() | nil
  defp process_bots_query(nil), do: nil

  defp process_bots_query(query) when is_map(query) do
    query
    |> process_fields()
    |> process_search()
  end

  defp process_fields(%{fields: fields} = query) when is_list(fields) do
    %{query | fields: Enum.join(fields, ", ")}
  end

  defp process_fields(query), do: query

  defp process_search(%{search: search} = query) when is_map(search) do
    search_string =
      search
      |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
      |> Enum.join(" ")

    %{query | search: search_string}
  end

  defp process_search(query), do: query

  @spec maybe_add_field(map(), map(), atom()) :: map()
  defp maybe_add_field(body, stats, field) do
    case Map.get(stats, field) do
      nil -> body
      value -> Map.put(body, field, value)
    end
  end

  @spec maybe_add_response_field(map(), map(), String.t(), atom()) :: map()
  defp maybe_add_response_field(stats, response, response_key, stats_key) do
    case Map.get(response, response_key) do
      nil -> stats
      value -> Map.put(stats, stats_key, value)
    end
  end
end
