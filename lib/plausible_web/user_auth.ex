defmodule PlausibleWeb.UserAuth do
  @moduledoc """
  Functions for managing user authentication.
  """

  import Phoenix.Controller
  import Plug.Conn
  import PlausibleWeb.ControllerHelpers

  alias Plausible.Auth
  alias Plausible.RateLimit
  alias PlausibleWeb.TwoFactor

  alias PlausibleWeb.Router.Helpers, as: Routes

  require Logger

  @login_interval 60_000
  @login_limit 5

  def login_user(conn, email, password) do
    with :ok <- check_ip_rate_limit(conn),
         {:ok, user} <- find_user(email),
         :ok <- check_user_rate_limit(user),
         :ok <- check_password(user, password) do
      {:ok, user}
    else
      {:error, :wrong_password} ->
        maybe_log_failed_login_attempts("wrong password for #{email}")

        render(conn, "login_form.html",
          error: "Wrong email or password. Please try again.",
          layout: {PlausibleWeb.LayoutView, "focus.html"}
        )

      {:error, :not_found} ->
        maybe_log_failed_login_attempts("user not found for #{email}")
        Auth.Password.dummy_calculation()

        render(conn, "login_form.html",
          error: "Wrong email or password. Please try again.",
          layout: {PlausibleWeb.LayoutView, "focus.html"}
        )

      {:rate_limit, _} ->
        maybe_log_failed_login_attempts("too many logging attempts for #{email}")

        render_error(
          conn,
          429,
          "Too many login attempts. Wait a minute before trying again."
        )
    end
  end

  def check_ip_rate_limit(conn) do
    ip_address = PlausibleWeb.RemoteIP.get(conn)

    case RateLimit.check_rate("login:ip:#{ip_address}", @login_interval, @login_limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:rate_limit, :ip_address}
    end
  end

  def check_user_rate_limit(user) do
    case RateLimit.check_rate("login:user:#{user.id}", @login_interval, @login_limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:rate_limit, :user}
    end
  end

  def set_user_session_and_redirect(conn, user) do
    login_dest = get_session(conn, :login_dest) || Routes.site_path(conn, :index)

    conn
    |> set_user_session(user)
    |> put_session(:login_dest, nil)
    |> redirect(external: login_dest)
  end

  def set_user_session(conn, user) do
    conn
    |> TwoFactor.Session.clear_2fa_user()
    |> put_session(:current_user_id, user.id)
    |> put_resp_cookie("logged_in", "true",
      http_only: false,
      max_age: 60 * 60 * 24 * 365 * 5000
    )
  end

  def maybe_log_failed_login_attempts(message) do
    if Application.get_env(:plausible, :log_failed_login_attempts) do
      Logger.warning("[login] #{message}")
    end
  end

  defp check_password(user, password) do
    if Auth.Password.match?(password, user.password_hash || "") do
      :ok
    else
      {:error, :wrong_password}
    end
  end

  defp find_user(email) do
    if user = Auth.find_user_by(email: email) do
      {:ok, user}
    else
      {:error, :not_found}
    end
  end
end
