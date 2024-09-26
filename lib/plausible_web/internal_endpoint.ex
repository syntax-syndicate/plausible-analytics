defmodule PlausibleWeb.InternalEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :plausible

  plug(PlausibleWeb.InternalRouter)

  plug(Plug.Static,
    at: "/kaffy",
    from: :kaffy,
    gzip: false,
    only: ~w(assets)
  )
end
