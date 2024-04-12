defmodule Difflib.MixProject do
  use Mix.Project

  def project do
    [
      app: :difflib,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Difflib",
      source_url: "https://github.com/gschro/difflib",
      description: "A set of helpers for computing deltas between objects.",
      docs: [
        main: "Difflib",
        extras: ["README.md", "LICENSE"]
      ],
      package: [
        name: :difflib,
        licenses: ["MIT"],
        maintainers: ["gschro"],
        links: %{"GitHub" => "https://github.com/gschro/difflib"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
