defmodule GroupSup do
    use Supervisor

    def start_link do
      Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    def init(:ok) do
        children = [
            worker(Group, [], restart: :temporary)
        ]

        supervise(children, strategy: :simple_one_for_one)
    end

    def start_group(group_number) do
        {:ok, group} = Supervisor.start_child(__MODULE__, [group_number])
        group
    end
end
