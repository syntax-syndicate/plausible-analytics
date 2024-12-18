defmodule PlausibleWeb.Api.Internal.SegmentsController do
  use Plausible
  use PlausibleWeb, :controller
  use Plausible.Repo
  use PlausibleWeb.Plugs.ErrorHandler
  alias PlausibleWeb.Api.Helpers, as: H

  import Plausible.Stats.Segments,
    only: [
      has_personal_segments?: 2,
      has_site_segments?: 1,
      can_manage_site_segments?: 2,
      can_view_segment_data?: 2,
      validate_segment_data_if_exists: 2,
      validate_segment_data: 2
    ]

  @fields_in_index_query [
    :id,
    :name,
    :type,
    :inserted_at,
    :updated_at,
    :owner_id
  ]

  @doc """
    This function Plug halts connection with 404 error if user or site do not have the expected feature flag.
  """
  def segments_feature_gate_plug(%Plug.Conn{} = conn, _opts) do
    flag = :saved_segments

    enabled =
      FunWithFlags.enabled?(flag, for: conn.assigns[:current_user]) ||
        FunWithFlags.enabled?(flag, for: conn.assigns[:site])

    if !enabled do
      H.not_found(conn, "Oops! There's nothing here")
    else
      conn
    end
  end

  def get_all_segments(conn, _params) do
    site = conn.assigns.site
    user = conn.assigns[:current_user]

    publicly_visible_fields = @fields_in_index_query -- [:owner_id]

    query =
      case {has_site_segments?(site), has_personal_segments?(site, user)} do
        {true, true} ->
          get_mixed_segments_query(user.id, site.id, @fields_in_index_query)

        {true, false} ->
          get_site_segments_only_query(site.id, publicly_visible_fields)

        {false, true} ->
          get_personal_segments_only_query(user.id, site.id, @fields_in_index_query)

        _ ->
          :no_permissions
      end

    if query == :no_permissions do
      H.not_enough_permissions(conn, "Not enough permissions to get segments")
    else
      json(conn, Repo.all(query))
    end
  end

  def get_segment(conn, params) do
    site = conn.assigns.site
    user = conn.assigns[:current_user]

    if can_view_segment_data?(site, user) do
      segment_id = normalize_segment_id_param(params["segment_id"])

      result = get_one_segment(user.id, site.id, segment_id)

      case result do
        nil -> H.not_found(conn, "Segment not found with ID #{inspect(params["segment_id"])}")
        %{} -> json(conn, result)
      end
    else
      H.not_enough_permissions(conn, "Not enough permissions to get segment data")
    end
  end

  def create_segment(conn, %{"type" => "site"} = params) do
    if can_manage_site_segments?(conn.assigns.site, conn.assigns[:current_user]) do
      do_insert_segment(conn, params)
    else
      H.not_enough_permissions(conn, "Not enough permissions to create segment")
    end
  end

  def create_segment(conn, %{"type" => "personal"} = params) do
    if has_personal_segments?(conn.assigns.site, conn.assigns[:current_user]) do
      do_insert_segment(conn, params)
    else
      H.not_enough_permissions(conn, "Not enough permissions to create segment")
    end
  end

  def update_segment(%{assigns: %{current_user: user}} = conn, params) do
    site = conn.assigns.site

    segment_id = normalize_segment_id_param(params["segment_id"])

    existing_segment = get_one_segment(user.id, site.id, segment_id)

    cond do
      is_nil(existing_segment) ->
        H.not_found(conn, "Segment not found with ID #{inspect(params["segment_id"])}")

      existing_segment.type == :personal and
        has_personal_segments?(site, user) and
          params["type"] !== "site" ->
        do_update_segment(conn, params, existing_segment, user.id)

      existing_segment.type == :site and can_manage_site_segments?(site, user) ->
        do_update_segment(conn, params, existing_segment, user.id)

      true ->
        H.not_enough_permissions(conn, "Not enough permissions to edit segment")
    end
  end

  def delete_segment(%{assigns: %{current_user: user}} = conn, params) do
    site = conn.assigns.site
    segment_id = normalize_segment_id_param(params["segment_id"])

    existing_segment = get_one_segment(user.id, site.id, segment_id)

    cond do
      is_nil(existing_segment) ->
        H.not_found(conn, "Segment not found with ID #{inspect(params["segment_id"])}")

      existing_segment.type == :personal and has_personal_segments?(site, user) ->
        do_delete_segment(conn, existing_segment)

      existing_segment.type == :site and can_manage_site_segments?(site, user) ->
        do_delete_segment(conn, existing_segment)

      true ->
        H.not_enough_permissions(conn, "Not enough permissions to delete segment")
    end
  end

  defp get_site_segments_only_query(site_id, fields) do
    from(segment in Plausible.Segment,
      select: ^fields,
      where: segment.site_id == ^site_id,
      where: segment.type == :site,
      order_by: [desc: segment.updated_at, desc: segment.id]
    )
  end

  defp get_personal_segments_only_query(user_id, site_id, fields) do
    from(segment in Plausible.Segment,
      select: ^fields,
      where: segment.site_id == ^site_id,
      where: segment.type == :personal and segment.owner_id == ^user_id,
      order_by: [desc: segment.updated_at, desc: segment.id]
    )
  end

  defp get_mixed_segments_query(user_id, site_id, fields) do
    from(segment in Plausible.Segment,
      select: ^fields,
      where: segment.site_id == ^site_id,
      where:
        segment.type == :site or (segment.type == :personal and segment.owner_id == ^user_id),
      order_by: [desc: segment.updated_at, desc: segment.id]
    )
  end

  defp normalize_segment_id_param(input) do
    case Integer.parse(input) do
      {int_value, ""} when int_value > 0 -> int_value
      _ -> nil
    end
  end

  defp get_one_segment(_user_id, _site_id, nil) do
    nil
  end

  defp get_one_segment(user_id, site_id, segment_id) do
    query =
      from(segment in Plausible.Segment,
        where: segment.site_id == ^site_id,
        where: segment.id == ^segment_id,
        where: segment.type == :site or segment.owner_id == ^user_id
      )

    Repo.one(query)
  end

  defp do_insert_segment(%{assigns: %{current_user: user}} = conn, params) do
    site = conn.assigns.site

    segment_definition = Map.merge(params, %{"site_id" => site.id, "owner_id" => user.id})

    with %{valid?: true} = changeset <-
           Plausible.Segment.changeset(
             %Plausible.Segment{},
             segment_definition
           ),
         :ok <- validate_segment_data(site, params["segment_data"]) do
      segment = Repo.insert!(changeset)
      json(conn, segment)
    else
      %{valid?: false, errors: errors} ->
        conn |> put_status(400) |> json(%{errors: errors})

      {:error, error_messages} when is_list(error_messages) ->
        conn |> put_status(400) |> json(%{errors: error_messages})

      _unknown_error ->
        conn |> put_status(400) |> json(%{error: "Failed to update segment"})
    end
  end

  defp do_update_segment(conn, params, %Plausible.Segment{} = existing_segment, owner_override) do
    partial_segment_definition = Map.merge(params, %{"owner_id" => owner_override})

    with %{valid?: true} = changeset <-
           Plausible.Segment.changeset(
             existing_segment,
             partial_segment_definition
           ),
         :ok <-
           validate_segment_data_if_exists(conn.assigns.site, params["segment_data"]) do
      json(
        conn,
        Repo.update!(
          changeset,
          returning: true
        )
      )
    else
      %{valid?: false, errors: errors} ->
        conn |> put_status(400) |> json(%{errors: errors})

      {:error, error_messages} when is_list(error_messages) ->
        conn |> put_status(400) |> json(%{errors: error_messages})

      _unknown_error ->
        conn |> put_status(400) |> json(%{error: "Failed to update segment"})
    end
  end

  defp do_delete_segment(
         %Plug.Conn{} = conn,
         %Plausible.Segment{} = existing_segment
       ) do
    Repo.delete!(existing_segment)
    json(conn, existing_segment)
  end
end
