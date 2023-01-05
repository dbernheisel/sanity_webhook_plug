defmodule SanityWebhookPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :sanity_webhook_plug,
      version: "0.1.0",
      elixir: "~> 1.14",
      preferred_cli_env: [dialyzer: :test, credo: :test, tests: :test],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
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
