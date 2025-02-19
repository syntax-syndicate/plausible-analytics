defmodule Locks do
  use GenServer

  @table __MODULE__
  @retry_interval 10
  @max_wait_time 500

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    @table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        write_concurrency: true,
        read_concurrency: true
      ])

    {:ok, @table}
  end

  def acquire_lock(resource, wait_time \\ 0)

  def acquire_lock(resource, wait_time) when wait_time < @max_wait_time do
    case :ets.insert_new(@table, {resource, self()}) do
      true ->
        monitor_process(self(), resource)
        :ok

      false ->
        receive do
          :lock_released ->
            acquire_lock(resource, wait_time + @retry_interval)
        after
          @retry_interval -> acquire_lock(resource, wait_time + @retry_interval)
        end
    end
  end

  def acquire_lock(_, _) do
    :timeout
  end

  def release_lock(resource) do
    case :ets.lookup(@table, resource) do
      [{^resource, owner}] when owner == self() ->
        :ets.delete(@table, resource)
        notify()
        :ok

      _ ->
        {:error, :not_owner}
    end
  end

  def with_lock(resource, f) do
    case acquire_lock(resource) do
      :ok ->
        result = f.()
        :ok = release_lock(resource)
        {:ok, result}

      :timeout ->
        :timeout
    end
  end

  defp notify() do
    send(self(), :lock_released)
  end

  def monitor_process(pid, resource) do
    Process.monitor(pid)

    spawn(fn ->
      receive do
        {:DOWN, _ref, :process, ^pid, _reason} ->
          :ets.delete(@table, resource)
          notify()
      end
    end)
  end
end
