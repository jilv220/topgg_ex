defmodule TopggEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jilv220/topgg_ex"

  def project do
    [
      app: :topgg_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:finch, "~> 0.19"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp description do
    """
    A comprehensive Elixir client for the Top.gg API, allowing you to interact with
    Discord bot statistics, user votes, and bot information with full type safety
    and excellent documentation.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Joshua Ji"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/topgg_ex",
        "Top.gg" => "https://top.gg"
      }
    ]
  end

  defp docs do
    [
      main: "TopggEx.Api",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        "Core API": [TopggEx.Api],
        "HTTP Client": [TopggEx.HttpClient, TopggEx.HttpClientBehaviour]
      ]
    ]
  end
end
