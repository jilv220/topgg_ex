defmodule TopggEx.WebhookTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias TopggEx.Webhook

  @valid_payload %{
    "user" => "123456789012345678",
    "type" => "upvote",
    "bot" => "987654321098765432",
    "isWeekend" => false,
    "query" => ""
  }

  @valid_payload_with_query %{
    "user" => "123456789012345678",
    "type" => "upvote",
    "bot" => "987654321098765432",
    "isWeekend" => true,
    "query" => "source=website&campaign=test"
  }

  @test_auth "test_webhook_auth_123"

  describe "verify_and_parse/2" do
    test "successfully parses valid webhook payload" do
      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)

      assert {:ok, payload} = Webhook.verify_and_parse(conn, @test_auth)
      assert payload["user"] == "123456789012345678"
      assert payload["type"] == "upvote"
      assert payload["bot"] == "987654321098765432"
      assert payload["isWeekend"] == false
    end

    test "parses query parameters when present" do
      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload_with_query))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)

      assert {:ok, payload} = Webhook.verify_and_parse(conn, @test_auth)
      assert payload["query"] == %{"source" => "website", "campaign" => "test"}
    end

    test "returns error for unauthorized request" do
      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "wrong_auth")

      assert {:error, :unauthorized} = Webhook.verify_and_parse(conn, @test_auth)
    end

    test "returns error for invalid JSON" do
      conn =
        conn(:post, "/webhook", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)

      assert {:error, :invalid_body} = Webhook.verify_and_parse(conn, @test_auth)
    end

    test "works without authorization check when none provided" do
      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")

      assert {:ok, payload} = Webhook.verify_and_parse(conn, nil)
      assert payload["user"] == "123456789012345678"
    end
  end

  describe "Plug behavior" do
    test "successfully processes webhook as plug" do
      defmodule TestRouterSuccess do
        use Plug.Router

        plug(Webhook, authorization: "test_auth_123")
        plug(:match)
        plug(:dispatch)

        post "/webhook" do
          payload = conn.assigns.topgg_payload
          send_resp(conn, 200, Jason.encode!(%{received: payload["user"]}))
        end
      end

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "test_auth_123")
        |> TestRouterSuccess.call(TestRouterSuccess.init([]))

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["received"] == "123456789012345678"
    end

    test "returns 403 for unauthorized requests" do
      # Test the webhook plug directly
      opts = Webhook.init(authorization: "test_auth_123")

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "wrong_auth")
        |> Webhook.call(opts)

      assert conn.status == 403
      assert conn.halted == true
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Unauthorized"
    end

    test "returns 400 for invalid JSON" do
      # Test the webhook plug directly
      opts = Webhook.init(authorization: "test_auth_123")

      conn =
        conn(:post, "/webhook", "invalid json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "test_auth_123")
        |> Webhook.call(opts)

      assert conn.status == 400
      assert conn.halted == true
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Invalid body"
    end
  end

  describe "listener/2" do
    test "successfully handles webhook with custom function" do
      handler =
        Webhook.listener(
          fn payload, conn ->
            assert payload["user"] == "123456789012345678"
            send_resp(conn, 200, "Vote received")
          end,
          authorization: @test_auth
        )

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)
        |> handler.([])

      assert conn.status == 200
      assert conn.resp_body == "Vote received"
    end

    test "sends 204 when handler doesn't send response" do
      handler =
        Webhook.listener(
          fn payload, conn ->
            assert payload["user"] == "123456789012345678"
            # Don't send response
            conn
          end,
          authorization: @test_auth
        )

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)
        |> handler.([])

      assert conn.status == 204
    end

    test "handles errors in handler function" do
      handler =
        Webhook.listener(
          fn _payload, _conn ->
            raise "Something went wrong"
          end,
          authorization: @test_auth
        )

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", @test_auth)
        |> handler.([])

      assert conn.status == 500
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "Internal server error"
    end
  end

  describe "custom assign key" do
    test "uses custom assign key" do
      # Test the webhook plug directly with custom assign key
      opts = Webhook.init(authorization: "test_auth", assign_key: :vote_data)

      conn =
        conn(:post, "/webhook", Jason.encode!(@valid_payload))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "test_auth")
        |> Webhook.call(opts)

      assert conn.assigns.vote_data["user"] == "123456789012345678"
      assert conn.assigns.vote_data["type"] == "upvote"
    end
  end
end
