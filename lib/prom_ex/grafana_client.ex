defmodule PromEx.GrafanaClient do
  @moduledoc """
  This module is used by the Mix tasks that are available in PromEx to update
  dashboards in Grafana and also by the `PromEx.DashboardUpdater` to update
  dashboards automatically on application initialization.

  Dashboard models:
  https://grafana.com/docs/grafana/latest/dashboards/json-model/
  """

  require Logger

  alias PromEx.GrafanaClient.Connection

  @typep handler_respose ::
           {:ok, result :: map()} | {:error, reason :: atom()} | {:error, reason :: Mint.TransportError.t()}

  @doc """
  Used to create a new dashboard or update an existing dashboard.
  """
  @spec upload_dashboard(grafana_conn :: Connection.t(), dashboard_file_path :: String.t(), opts :: keyword()) ::
          handler_respose()
  def upload_dashboard(%Connection{} = grafana_conn, dashboard_file_path, opts \\ []) do
    case File.read(dashboard_file_path) do
      {:ok, dashboard_contents} ->
        headers = grafana_headers(:post, grafana_conn.auth_token)
        payload = generate_payload(dashboard_contents, Keyword.merge(opts, overwrite: true))

        :post
        |> Finch.build("#{grafana_conn.base_url}/api/dashboards/db", headers, payload)
        |> Finch.request(grafana_conn.finch_process)
        |> handle_create_dashboard_response()

      {:error, reason} ->
        Logger.warn("Failed to read file #{dashboard_file_path} because of reason: #{inspect(reason)}")
        {:error, :invalid_dashboard}
    end
  end

  @doc """
  Used to get the dashboard definition currently in Grafana for the provided dashboard file.
  If the ID does not exist in Grafana an error tuple will be returned.
  """
  @spec get_dashboard(grafana_conn :: Connection.t(), dashboard_file_path :: String.t()) :: handler_respose()
  def get_dashboard(%Connection{} = grafana_conn, dashboard_file_path) do
    case File.read(dashboard_file_path) do
      {:ok, dashboard_contents} ->
        headers = grafana_headers(:get, grafana_conn.auth_token)

        dashboard_uid =
          dashboard_contents
          |> Jason.decode!()
          |> Map.get("uid")

        :get
        |> Finch.build("#{grafana_conn.base_url}/api/dashboards/uid/#{dashboard_uid}", headers)
        |> Finch.request(grafana_conn.finch_process)
        |> handle_create_dashboard_response()

      {:error, reason} ->
        Logger.warn("Failed to read file #{dashboard_file_path} because of reason: #{inspect(reason)}")
        {:error, :invalid_dashboard}
    end
  end

  @doc """
  Used to create a new folder in Grafana
  """
  @spec create_folder(grafana_conn :: Connection.t(), folder_uid :: String.t(), title :: String.t()) ::
          handler_respose()
  def create_folder(%Connection{} = grafana_conn, folder_uid, title) do
    headers = grafana_headers(:post, grafana_conn.auth_token)

    payload =
      Jason.encode!(%{
        uid: folder_uid,
        title: title
      })

    :post
    |> Finch.build("#{grafana_conn.base_url}/api/folders", headers, payload)
    |> Finch.request(grafana_conn.finch_process)
    |> handle_create_dashboard_response()
  end

  @doc """
  Update an existing folder in Grafana
  """
  @spec update_folder(grafana_conn :: Connection.t(), folder_uid :: String.t(), new_title :: String.t()) ::
          handler_respose()
  def update_folder(%Connection{} = grafana_conn, folder_uid, new_title) do
    headers = grafana_headers(:put, grafana_conn.auth_token)

    payload =
      Jason.encode!(%{
        title: new_title,
        overwrite: true
      })

    :put
    |> Finch.build("#{grafana_conn.base_url}/api/folders/#{folder_uid}", headers, payload)
    |> Finch.request(grafana_conn.finch_process)
    |> handle_create_dashboard_response()
  end

  @doc """
  Used to fetch the details regarding a particular folder on Grafana
  """
  @spec get_folder(grafana_conn :: Connection.t(), folder_uid :: String.t()) :: handler_respose()
  def get_folder(%Connection{} = grafana_conn, folder_id) do
    headers = grafana_headers(:get, grafana_conn.auth_token)

    :get
    |> Finch.build("#{grafana_conn.base_url}/api/folders/#{folder_id}", headers)
    |> Finch.request(grafana_conn.finch_process)
    |> handle_create_dashboard_response()
  end

  @doc """
  Used to create annotations on dashboard panels
  """
  @spec create_annotation(grafana_conn :: Connection.t(), tags :: [String.t()], message :: String.t()) ::
          handler_respose()
  def create_annotation(%Connection{} = grafana_conn, tags, message) do
    headers = grafana_headers(:post, grafana_conn.auth_token)

    payload =
      Jason.encode!(%{
        tags: tags,
        text: message
      })

    :post
    |> Finch.build("#{grafana_conn.base_url}/api/annotations", headers, payload)
    |> Finch.request(grafana_conn.finch_process)
    |> handle_create_dashboard_response()
  end

  defp handle_create_dashboard_response(finch_response) do
    case finch_response do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Finch.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Finch.Response{status: 412}} ->
        {:error, :already_exists}

      {:error, _reason} = error ->
        error
    end
  end

  defp grafana_headers(:get, bearer_token) do
    [
      {"authorization", bearer_token},
      {"accept", "application/json"}
    ]
  end

  defp grafana_headers(action, bearer_token) when action in [:post, :put] do
    [
      {"authorization", bearer_token},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]
  end

  defp generate_payload(dashboard_definition, opts) do
    dashboard = Jason.decode!(dashboard_definition)

    opts
    |> Map.new()
    |> Map.put(:dashboard, dashboard)
    |> Jason.encode!()
  end
end
