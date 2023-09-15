defmodule Group do
  use GenServer

  # Heroku only supports Elixir 1.2.6 which doesn't have the option for :pop
  def get_and_update(%{} = map, key, fun) when is_function(fun, 1) do
    current =
      case :maps.find(key, map) do
        {:ok, value} -> value
        :error -> nil
      end

    case fun.(current) do
      {get, update} ->
        {get, :maps.put(key, update, map)}
      :pop ->
        {current, :maps.remove(key, map)}
      other ->
        raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
    end
  end

  def start_link(group_number) do
      GenServer.start_link(__MODULE__, group_number, [])
  end

  def new_player_id(server) do
      GenServer.call(server, :new_player_id)
  end

  def get_update(server, get_params) do
      GenServer.call(server, {:get_update, get_params})
  end

  ## Server Callbacks

  def init(group_number) do
      :erlang.send_after(10000, self(), :clean)
      {:ok, {group_number, 0, :erlang.monotonic_time(:seconds), %{"players" => %{},
                                                                  "latest_message" => "",
                                                                  "older_message" => ""}}}
  end

  def handle_info(:clean, {group_number, fresh_id, last_update_time, group_info}) do
      id_map = Map.get(group_info, "players")
      player_id_keys = Map.keys(id_map)
      id_map3 =
          List.foldl(player_id_keys, id_map, fn (key, id_map1) ->
              {_, id_map2} =
                  get_and_update(id_map1, key, fn player_info ->
                      %{"last_refresh" => last_refresh} = player_info
                      # 12 seconds have passed since the last client updated
                      if (:erlang.monotonic_time(:seconds) - last_refresh) > 12 do
                          :pop
                      else
                          {player_info, player_info}
                      end
                  end)
              id_map2
          end)
      new_group_info = Map.put(group_info, "players", id_map3)
      # No players are left in the group 15 minutes after the last update
      if id_map3 == %{} and (:erlang.monotonic_time(:seconds) - last_update_time) > 900 do
          Networking.remove_group(group_number)
          {:stop, :normal, {group_number, fresh_id, last_update_time, new_group_info}}
      else
          # Trigger cleaning again in 5 seconds
          :erlang.send_after(5000, self(), :clean)
          {:noreply, {group_number, fresh_id, last_update_time, new_group_info}}
      end
  end

  def handle_call(:new_player_id, _from, {group_number, fresh_id, last_update_time, group_info}) do
      {:reply, to_string(fresh_id), {group_number, fresh_id + 1, last_update_time, group_info}}
  end

  def handle_call({:get_update, get_params}, _from, {group_number, fresh_id, last_update_time, group_info}) do
      %{"id" => player_id, "latitude" => latitude,
        "longitude" => longitude, "distance" => distance,
        "message" => message} = get_params
      message2 = to_string(:http_uri.decode(to_char_list(message)))
      group_info2 =
          if message2 != "" do
              Map.put(group_info, "older_message", Map.get(group_info, "latest_message")) |>
                Map.put("latest_message", message2)
          else
              group_info
          end
      time = :erlang.monotonic_time(:seconds)
      id_map = Map.get(group_info2, "players")
      id_map2 = Map.put(id_map, player_id, %{"latitude"  => latitude,
                                            "longitude" => longitude,
                                            "distance"  => distance,
                                            "last_refresh" => time})
      group_info3 = Map.put(group_info2, "players", id_map2)
      {:reply, group_info3, {group_number, fresh_id, time, group_info3}}
  end
end
