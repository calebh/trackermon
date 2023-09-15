defmodule Trackermon do
    use Application

    def start(_type, _args) do
        RootSup.start_link()
    end
end
