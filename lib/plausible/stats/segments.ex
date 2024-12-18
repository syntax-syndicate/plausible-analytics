defmodule Plausible.Stats.Segments do
  @moduledoc """
    This module contains functions for
    - validating segment related permissions
    - validating segment data
  """

  @spec can_view_segment_data?(Plausible.Site.t(), Plausible.Auth.User.t() | nil) :: boolean()
  def can_view_segment_data?(site, user) do
    Plausible.Teams.Memberships.site_member?(site, user)
  end

  @spec has_personal_segments?(Plausible.Site.t(), Plausible.Auth.User.t() | nil) :: boolean()
  def has_personal_segments?(site, user) do
    Plausible.Teams.Memberships.site_member?(site, user)
  end

  @spec has_site_segments?(Plausible.Site.t()) :: boolean()
  def has_site_segments?(site) do
    Plausible.Billing.Feature.Props.check_availability(site.team) == :ok
  end

  @spec can_manage_site_segments?(Plausible.Site.t(), Plausible.Auth.User.t() | nil) :: boolean()
  def can_manage_site_segments?(site, user) do
    valid_role? =
      case Plausible.Teams.Memberships.site_role(site, user) do
        {:ok, role} -> role in [:editor, :admin, :owner]
        _ -> false
      end

    has_site_segments?(site) and valid_role?
  end

  def validate_segment_data_if_exists(%Plausible.Site{} = _site, nil = _segment_data), do: :ok

  def validate_segment_data_if_exists(%Plausible.Site{} = site, segment_data),
    do: validate_segment_data(site, segment_data)

  def validate_segment_data(
        %Plausible.Site{} = site,
        %{"filters" => filters}
      ) do
    case build_naive_query_from_segment_data(site, filters) do
      {:ok, %Plausible.Stats.Query{filters: _filters}} ->
        :ok

      {:error, message} ->
        reformat_filters_errors(message)
    end
  end

  @doc """
    This function builds a simple query using the filters from Plausibe.Segment.segment_data
    to test whether the filters used in the segment stand as legitimate query filters.
    If they don't, it indicates an error with the filters that must be passed to the client,
    so they could reconfigure the filters.
  """
  def build_naive_query_from_segment_data(%Plausible.Site{} = site, filters),
    do:
      Plausible.Stats.Query.build(
        site,
        :internal,
        %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "7d",
          "filters" => filters
        },
        %{}
      )

  @doc """
    This function handles the error from building the naive query that is used to validate segment filters,
    collecting filter related errors into a list.
    If the error is not only about filters, the client can't do anything about the situation,
    and the error message is returned as-is.

    ### Examples
    iex> reformat_filters_errors(~s(#/metrics/0 Invalid metric "Visitors"\\n#/filters/0 Invalid filter "A"))
    {:error, ~s(#/metrics/0 Invalid metric "Visitors"\\n#/filters/0 Invalid filter "A")}

    iex> reformat_filters_errors(~s(#/filters/0 Invalid filter "A"\\n#/filters/1 Invalid filter "B"))
    {:error, [~s(#/filters/0 Invalid filter "A"), ~s(#/filters/1 Invalid filter "B")]}
  """
  def reformat_filters_errors(message) do
    lines = String.split(message, "\n")

    if Enum.all?(lines, fn m -> String.starts_with?(m, "#/filters/") end) do
      {:error, lines}
    else
      {:error, message}
    end
  end
end
