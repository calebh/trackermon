defmodule Networking do
  use GenServer

  def start_link do
      GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def add_group(group_number, group_pid) do
      GenServer.cast(__MODULE__, {:add_group, group_number, group_pid})
  end

  def fresh_group_number() do
      GenServer.call(__MODULE__, :fresh_group_number)
  end

  def remove_group(group_number) do
      GenServer.call(__MODULE__, {:remove_group, group_number})
  end

  def lookup_group(group_number) do
      GenServer.call(__MODULE__, {:lookup_group, group_number})
  end

  def http_payload(content) do
      content2 = :erlang.iolist_to_binary(content)
      size = String.length(content2) |> to_string
      ("HTTP/1.1 200 OK\r\nConnection:close\r\nContent-Type: text/plain\r\nContent-Length: " <>
          size <> "\r\n\r\n" <> content2)
  end

  def listen_for_request(l_socket) do
      spawn(fn ->
          {:ok, socket} = :gen_tcp.accept(l_socket)
          listen_for_request(l_socket)
          handle_request(socket)
      end)
  end

  def handle_request(socket) do
      receive do
          # Path example: '/?group=41&lat=31.13245&long=141.44&id=785'
          {:http, _, {:http_request, :GET, {:abs_path, [_, _ | path]}, _}} ->
              get_params =
                  try do
                      to_string(path) |> String.split("&") |>
                          Enum.map(fn pair -> String.split(pair, "=") |> List.to_tuple end) |>
                          :maps.from_list
                  rescue
                      _ -> %{}
                  end
              :erlang.display(get_params)
              payload =
                  case get_params do
                      %{"request" => "newgroup"} ->
                          group_number = fresh_group_number()
                          group_pid = GroupSup.start_group(group_number)
                          add_group(group_number, group_pid)
                          player_id = Group.new_player_id(group_pid)
                          %{"id" => player_id, "group" => group_number}
                      %{"request" => "joingroup", "group" => group_number} ->
                          case lookup_group(group_number) do
                              {:ok, group_pid} ->
                                  player_id = Group.new_player_id(group_pid)
                                  %{"id" => player_id}
                               _ ->
                                  :gen_tcp.send(socket, http_payload("Unable to find group while requesting to join a group"))
                                  :gen_tcp.close(socket)
                                  :erlang.exit(:normal)
                          end
                      %{"request" => "update", "group" => group_number, "id" => _,
                            "latitude" => _, "longitude" => _, "distance" => _,
                            "message" => _} ->
                          group_pid =
                              case lookup_group(group_number) do
                                  {:ok, pid} -> pid
                                  _ ->
                                      :gen_tcp.send(socket, http_payload("Unable to find group while updating"))
                                      :gen_tcp.close(socket)
                                      :erlang.exit(:normal)
                              end
                           Group.get_update(group_pid, get_params)
                      _ ->
                          :gen_tcp.send(socket, http_payload("What the fuck"))
                          %{"error" => "Bad request", "query" => get_params}
                  end
              :gen_tcp.send(socket, http_payload(Poison.Encoder.encode(payload, [])))
              :gen_tcp.close(socket)
          {:tcp_closed, _} ->
              :erlang.display("tcp_closed")
              :ok
          _ ->
              :gen_tcp.send(socket, http_payload("Unknown request"))
              :gen_tcp.close(socket)
              :erlang.exit(:normal)
      after
          1000 ->
              :gen_tcp.send(socket, http_payload("Timeout"))
              :gen_tcp.close(socket)
      end
  end

  ## Server Callbacks

  def init(:ok) do
      port =
          case System.get_env("PORT") do
              nil -> 80
              number -> String.to_integer(number)
          end
      {:ok, l_socket} = :gen_tcp.listen(port, [{:packet, :http}])
      for _ <- 1..20, do: listen_for_request(l_socket)
      {:ok, {0, %{}}}
  end

  def handle_call({:lookup_group, group_number}, _from, {id, group_map}) do
      {:reply, Map.fetch(group_map, group_number), {id, group_map}}
  end

  def handle_call(:fresh_group_number, _from, {id, group_map}) do
      id_str = to_string(id)
      {:reply, id_str, {id + 1, group_map}}
  end

  def handle_call({:remove_group, group_number}, _from, {id, group_map}) do
      ret = Map.delete(group_map, group_number)
      {:reply, :ok, {id, ret}}
  end

  def handle_cast({:add_group, group_number, group_pid}, {id, group_map}) do
      {:noreply, {id, Map.put(group_map, group_number, group_pid)}}
  end
end
