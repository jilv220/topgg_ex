# Start Finch for testing
{:ok, _} = Finch.start_link(name: :test_finch)

ExUnit.start()
