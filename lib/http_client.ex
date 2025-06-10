defmodule TopggEx.HttpClient do
  @moduledoc """
  HTTP client for making requests to the Top.gg API using Finch.

  This module handles all HTTP communication with the Top.gg API,
  including request building, execution, and response parsing.
  """

  @behaviour TopggEx.HttpClientBehaviour

  @type request_options :: TopggEx.HttpClientBehaviour.request_options()

  @doc """
  Makes an HTTP request to the Top.gg API.

  ## Parameters

    * `options` - Request configuration containing token, finch_name, and base_url
    * `method` - HTTP method (:get, :post, etc.)
    * `path` - API endpoint path
    * `body` - Request body (optional)

  ## Examples

      iex> options = %{token: "token", finch_name: :topgg_finch, base_url: "https://top.gg/api"}
      iex> TopggEx.HttpClient.request(options, :get, "/bots/stats")
      {:ok, %{"server_count" => 100}}

  """
  @spec request(request_options(), atom(), String.t(), map() | nil) ::
          {:ok, any()} | {:error, any()}
  def request(
        %{token: token, finch_name: finch_name, base_url: base_url} = _options,
        method,
        path,
        body \\ nil
      ) do
    headers = build_headers(token, method)
    url = build_url(base_url, path, method, body)
    request_body = build_request_body(method, body)

    case Finch.build(method, url, headers, request_body)
         |> Finch.request(finch_name) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        parse_response_body(response_body)

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  @spec build_headers(String.t(), atom()) :: [{String.t(), String.t()}]
  defp build_headers(token, method) do
    headers = [{"authorization", token}]

    if method != :get do
      [{"content-type", "application/json"} | headers]
    else
      headers
    end
  end

  @spec build_url(String.t(), String.t(), atom(), map() | nil) :: String.t()
  defp build_url(base_url, path, :get, body) when is_map(body) do
    query_string = URI.encode_query(body)
    "#{base_url}#{path}?#{query_string}"
  end

  defp build_url(base_url, path, _method, _body) do
    "#{base_url}#{path}"
  end

  @spec build_request_body(atom(), map() | nil) :: String.t() | nil
  defp build_request_body(:get, _body), do: nil
  defp build_request_body(_method, nil), do: nil
  defp build_request_body(_method, body), do: Jason.encode!(body)

  @spec parse_response_body(String.t()) :: {:ok, any()} | {:error, any()}
  defp parse_response_body(""), do: {:ok, nil}

  defp parse_response_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:ok, body}
    end
  end
end
