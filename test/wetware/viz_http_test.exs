defmodule Wetware.VizHttpTest do
  use ExUnit.Case, async: false

  alias Wetware.{Resonance, Viz}

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  test "serve/1 responds to health and api endpoints" do
    port = free_port()

    server =
      Task.async(fn ->
        Viz.serve(port: port)
      end)

    on_exit(fn ->
      Process.exit(server.pid, :kill)
    end)

    wait_for_server(port)

    assert response_for(port, "GET /health HTTP/1.1\r\nhost: 127.0.0.1\r\n\r\n") =~
             "HTTP/1.1 200 OK"

    state_response = response_for(port, "GET /api/state HTTP/1.1\r\nhost: 127.0.0.1\r\n\r\n")
    assert state_response =~ "HTTP/1.1 200 OK"
    assert state_response =~ "\"step_count\""
  end

  defp response_for(port, request) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :raw], 2_000)

    :ok = :gen_tcp.send(socket, request)
    {:ok, response} = :gen_tcp.recv(socket, 0, 2_000)
    :ok = :gen_tcp.close(socket)
    response
  end

  defp wait_for_server(port, attempts \\ 30)

  defp wait_for_server(_port, attempts) when attempts <= 0, do: flunk("viz server did not start")

  defp wait_for_server(port, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :raw], 100) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        :ok

      _ ->
        Process.sleep(25)
        wait_for_server(port, attempts - 1)
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
