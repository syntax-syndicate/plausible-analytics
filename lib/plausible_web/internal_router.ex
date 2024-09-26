defmodule PlausibleWeb.InternalRouter do
  use PlausibleWeb, :router

  use Kaffy.Routes,
    scope: "/crm",
    pipe_through: [
      PlausibleWeb.Plugs.NoRobots,
      PlausibleWeb.AuthPlug,
      PlausibleWeb.SuperAdminOnlyPlug
    ]


    pipeline :flags do
      plug :accepts, ["html"]
      plug :put_secure_browser_headers
      plug PlausibleWeb.Plugs.NoRobots
      plug :fetch_session

      plug PlausibleWeb.AuthPlug
      plug PlausibleWeb.SuperAdminOnlyPlug
    end

    scope path: "/flags" do
      pipe_through :flags
      forward "/", FunWithFlags.UI.Router, namespace: "flags"
    end

  scope "/crm", PlausibleWeb do
    pipe_through :flags
    get "/auth/user/:user_id/usage", AdminController, :usage
    get "/billing/user/:user_id/current_plan", AdminController, :current_plan
  end
end
