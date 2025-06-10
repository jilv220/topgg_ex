defmodule TopggEx.ApiTest do
  use ExUnit.Case

  alias TopggEx.Api

  setup do
    bypass = Bypass.open()

    # Valid JWT-like token structure (base64 encoded JSON)
    header =
      %{"alg" => "HS256", "typ" => "JWT"} |> Jason.encode!() |> Base.encode64(padding: false)

    payload =
      %{"sub" => "test", "iat" => 1_234_567_890}
      |> Jason.encode!()
      |> Base.encode64(padding: false)

    signature = "test_signature"
    valid_token = "#{header}.#{payload}.#{signature}"

    {:ok, api} =
      Api.new(valid_token, %{
        finch_name: :test_finch,
        base_url: "http://localhost:#{bypass.port}/api"
      })

    {:ok, %{bypass: bypass, api: api, valid_token: valid_token}}
  end

  describe "new/2" do
    test "creates API client with valid token" do
      header = %{"alg" => "HS256"} |> Jason.encode!() |> Base.encode64(padding: false)
      payload = %{"sub" => "test"} |> Jason.encode!() |> Base.encode64(padding: false)
      signature = "signature"
      token = "#{header}.#{payload}.#{signature}"

      assert {:ok, %Api{token: ^token}} = Api.new(token)
    end

    test "returns error for malformed token" do
      assert {:error, "Got a malformed API token."} = Api.new("invalid.token")
      assert {:error, "Got a malformed API token."} = Api.new("invalid")
    end

    test "returns error for invalid token structure" do
      # Valid structure but invalid base64 content
      assert {:error, "Invalid API token state, this should not happen! Please report!"} =
               Api.new("header.invalid_base64.signature")
    end

    test "accepts custom options" do
      header = %{"alg" => "HS256"} |> Jason.encode!() |> Base.encode64(padding: false)
      payload = %{"sub" => "test"} |> Jason.encode!() |> Base.encode64(padding: false)
      token = "#{header}.#{payload}.signature"

      {:ok, api} = Api.new(token, %{finch_name: :custom_finch, base_url: "https://custom.api"})

      assert api.finch_name == :custom_finch
      assert api.base_url == "https://custom.api"
    end
  end

  describe "post_stats/2" do
    test "posts bot statistics successfully", %{bypass: bypass, api: api} do
      stats = %{server_count: 100}

      Bypass.expect_once(bypass, "POST", "/api/bots/stats", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"server_count" => 100}
        assert {"authorization", _} = List.keyfind(conn.req_headers, "authorization", 0)

        conn |> Plug.Conn.resp(200, "{}")
      end)

      assert {:ok, ^stats} = Api.post_stats(api, stats)
    end

    test "returns error for missing server count", %{api: api} do
      assert {:error, "Missing or invalid server count"} = Api.post_stats(api, %{})

      assert {:error, "Missing or invalid server count"} =
               Api.post_stats(api, %{server_count: "invalid"})

      assert {:error, "Missing or invalid server count"} =
               Api.post_stats(api, %{server_count: -1})
    end

    test "returns error on API failure", %{bypass: bypass, api: api} do
      stats = %{server_count: 100}

      Bypass.expect_once(bypass, "POST", "/api/bots/stats", fn conn ->
        conn |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Internal server error"}))
      end)

      assert {:error, %{status: 500}} = Api.post_stats(api, stats)
    end
  end

  describe "get_stats/1" do
    test "gets bot statistics successfully", %{bypass: bypass, api: api} do
      response = %{
        "server_count" => 1000,
        "shard_count" => 2,
        "shards" => [500, 500]
      }

      Bypass.expect_once(bypass, "GET", "/api/bots/stats", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, stats} = Api.get_stats(api)
      assert stats.server_count == 1000
      assert stats.shard_count == 2
      assert stats.shards == [500, 500]
    end

    test "handles missing optional fields", %{bypass: bypass, api: api} do
      response = %{"server_count" => 1000}

      Bypass.expect_once(bypass, "GET", "/api/bots/stats", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, stats} = Api.get_stats(api)
      assert stats.server_count == 1000
      assert stats.shard_count == nil
      assert stats.shards == []
    end
  end

  describe "get_bot/2" do
    test "gets bot information successfully", %{bypass: bypass, api: api} do
      bot_id = "461521980492087297"

      response = %{
        "id" => bot_id,
        "username" => "Shiro",
        "discriminator" => "0000"
      }

      Bypass.expect_once(bypass, "GET", "/api/bots/#{bot_id}", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, ^response} = Api.get_bot(api, bot_id)
    end

    test "returns error for missing ID", %{api: api} do
      assert {:error, "ID missing"} = Api.get_bot(api, "")
      assert {:error, "ID missing"} = Api.get_bot(api, nil)
    end
  end

  describe "get_user/2" do
    test "gets user information with deprecation warning", %{bypass: bypass, api: api} do
      user_id = "205680187394752512"

      response = %{
        "id" => user_id,
        "username" => "Xignotic"
      }

      Bypass.expect_once(bypass, "GET", "/api/users/#{user_id}", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      # Capture the warning log
      assert ExUnit.CaptureLog.capture_log(fn ->
               assert {:ok, ^response} = Api.get_user(api, user_id)
             end) =~ "[DeprecationWarning] get_user is no longer supported by Top.gg API v0."
    end
  end

  describe "get_bots/2" do
    test "gets bots list successfully", %{bypass: bypass, api: api} do
      response = %{
        "results" => [
          %{"id" => "461521980492087297", "username" => "Shiro"}
        ],
        "limit" => 10,
        "offset" => 0,
        "count" => 1,
        "total" => 1
      }

      Bypass.expect_once(bypass, "GET", "/api/bots", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, ^response} = Api.get_bots(api)
    end

    test "processes search query correctly", %{bypass: bypass, api: api} do
      query = %{search: %{username: "shiro"}}

      Bypass.expect_once(bypass, "GET", "/api/bots", fn conn ->
        assert conn.query_string == "search=username%3A+shiro"
        conn |> Plug.Conn.resp(200, Jason.encode!(%{"results" => []}))
      end)

      Api.get_bots(api, query)
    end

    test "processes fields query correctly", %{bypass: bypass, api: api} do
      query = %{fields: ["id", "username"]}

      Bypass.expect_once(bypass, "GET", "/api/bots", fn conn ->
        assert conn.query_string == "fields=id%2C+username"
        conn |> Plug.Conn.resp(200, Jason.encode!(%{"results" => []}))
      end)

      Api.get_bots(api, query)
    end
  end

  describe "get_votes/2" do
    test "gets votes successfully with default page", %{bypass: bypass, api: api} do
      response = [
        %{
          "username" => "Xignotic",
          "id" => "205680187394752512",
          "avatar" => "https://example.com/avatar.png"
        }
      ]

      Bypass.expect_once(bypass, "GET", "/api/bots/votes", fn conn ->
        assert conn.query_string == "page=1"
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, ^response} = Api.get_votes(api)
    end

    test "gets votes with custom page", %{bypass: bypass, api: api} do
      response = []

      Bypass.expect_once(bypass, "GET", "/api/bots/votes", fn conn ->
        assert conn.query_string == "page=2"
        conn |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, ^response} = Api.get_votes(api, 2)
    end
  end

  describe "has_voted/2" do
    test "returns true when user has voted", %{bypass: bypass, api: api} do
      user_id = "205680187394752512"

      Bypass.expect_once(bypass, "GET", "/api/bots/check", fn conn ->
        assert conn.query_string == "userId=#{user_id}"
        conn |> Plug.Conn.resp(200, Jason.encode!(%{"voted" => 1}))
      end)

      assert {:ok, true} = Api.has_voted(api, user_id)
    end

    test "returns false when user has not voted", %{bypass: bypass, api: api} do
      user_id = "205680187394752512"

      Bypass.expect_once(bypass, "GET", "/api/bots/check", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(%{"voted" => false}))
      end)

      assert {:ok, false} = Api.has_voted(api, user_id)
    end

    test "returns error for missing ID", %{api: api} do
      assert {:error, "Missing ID"} = Api.has_voted(api, "")
    end
  end

  describe "is_weekend/1" do
    test "returns weekend status", %{bypass: bypass, api: api} do
      Bypass.expect_once(bypass, "GET", "/api/weekend", fn conn ->
        conn |> Plug.Conn.resp(200, Jason.encode!(%{"is_weekend" => true}))
      end)

      assert {:ok, true} = Api.is_weekend(api)
    end
  end
end
