defmodule SanityWebhookPlug.MixProject do
  use Mix.Project
  @version "0.1.0"

  def project do
    [
      app: :sanity_webhook_plug,
      version: @version,
      elixir: "~> 1.14",
      preferred_cli_env: [dialyzer: :test, credo: :test, tests: :test],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      source_ref: @version,
      extras: ["CHANGELOG.md", "LICENSE"]
    ]
  end

  defp package do
    %{
      maintainers: ["David Bernheisel"],
      licenses: ["Apache-2.0"],
      files: [
        "lib",
        "mix.exs",
        "CHANGELOG*",
        "README*",
        "LICENSE*"
      ],
      links: %{
        "GitHub" => "https://github.com/bitfo/sanity_webhook_plug",
        "Readme" => "https://github.com/bitfo/sanity_webhook_plug/blob/#{@version}/README.md",
        "Changelog" =>
          "https://github.com/bitfo/sanity_webhook_plug/blob/#{@version}/CHANGELOG.md"
      }
    }
  end

  defp deps do
    [
      {:plug, "~> 1.0"},
      # dev/test
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      tests: ["test", "dialyzer", "credo", "format --check-formatted"]
    ]
  end
end
