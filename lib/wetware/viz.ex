defmodule Wetware.Viz do
  @moduledoc """
  Lightweight local HTTP server for live gel visualization.

  Uses plain TCP + HTTP/1.1 and polling (`/api/state`) to avoid external deps.
  """

  alias Wetware.{Cell, Gel}

  @default_port 4157
  @max_cells 6_000

  def default_port, do: @default_port

  def serve(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)

    case :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true]) do
      {:ok, listener} ->
        IO.puts("Wetware viz listening on http://127.0.0.1:#{port}")
        accept_loop(listener)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def state_snapshot do
    cells =
      Wetware.Gel.Index.list_cells()
      |> Enum.map(fn {{x, y}, pid} ->
        state = safe_cell_state(pid)

        %{
          x: x,
          y: y,
          charge: Map.get(state, :charge, 0.0),
          kind: Map.get(state, :kind, :interstitial)
        }
      end)
      |> Enum.sort_by(& &1.charge, :desc)
      |> Enum.take(@max_cells)

    concepts =
      Gel.concepts()
      |> Enum.map(fn {name, %{center: {cx, cy}, r: r, tags: tags}} ->
        %{name: name, cx: cx, cy: cy, r: r, tags: tags}
      end)
      |> Enum.sort_by(& &1.name)

    %{
      step_count: Gel.step_count(),
      bounds: Gel.bounds(),
      cells: cells,
      concepts: concepts,
      cell_count: Registry.count(Wetware.CellRegistry),
      max_cells: @max_cells,
      timestamp_ms: System.system_time(:millisecond)
    }
  end

  def state_json do
    state_snapshot()
    |> Jason.encode!()
  end

  defp accept_loop(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        Task.start(fn -> handle_client(socket) end)
        accept_loop(listener)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listener)
    end
  end

  defp handle_client(socket) do
    response =
      case read_request(socket) do
        {:ok, %{method: "GET", path: "/"}} -> http_ok("text/html; charset=utf-8", html())
        {:ok, %{method: "GET", path: "/api/state"}} -> http_ok("application/json", state_json())
        {:ok, %{method: "GET", path: "/health"}} -> http_ok("text/plain; charset=utf-8", "ok\n")
        {:ok, _} -> http_not_found()
        {:error, _} -> http_bad_request()
      end

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp read_request(socket) do
    with {:ok, data} <- :gen_tcp.recv(socket, 0, 5_000),
         [line | _] <- String.split(data, "\r\n"),
         [method, target, _version] <- String.split(line, " ", parts: 3) do
      path =
        case String.split(target, "?", parts: 2) do
          [p | _] -> p
          _ -> target
        end

      {:ok, %{method: method, path: path}}
    else
      _ -> {:error, :bad_request}
    end
  end

  defp http_ok(content_type, body) do
    [
      "HTTP/1.1 200 OK\r\n",
      "content-type: #{content_type}\r\n",
      "cache-control: no-store\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n",
      "\r\n",
      body
    ]
  end

  defp http_not_found do
    body = "not found\n"

    [
      "HTTP/1.1 404 Not Found\r\n",
      "content-type: text/plain; charset=utf-8\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n",
      "\r\n",
      body
    ]
  end

  defp http_bad_request do
    body = "bad request\n"

    [
      "HTTP/1.1 400 Bad Request\r\n",
      "content-type: text/plain; charset=utf-8\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n",
      "\r\n",
      body
    ]
  end

  defp safe_cell_state(pid) do
    try do
      Cell.get_state(pid)
    catch
      :exit, _ -> %{}
    end
  end

  defp html do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Wetware Viz</title>
      <style>
        :root {
          --bg-deep: #081318;
          --bg-mid: #11242d;
          --grid: rgba(180, 220, 220, 0.12);
          --ink: #dbefe8;
          --muted: #a7c9be;
          --accent: #6ef0cd;
          --warm: #ffb26b;
          --hot: #ff7d57;
        }
        * { box-sizing: border-box; }
        html, body { margin: 0; height: 100%; background: radial-gradient(1200px 800px at 80% -20%, #183744 0%, var(--bg-deep) 45%, #050d11 100%); color: var(--ink); font-family: "Avenir Next", "Trebuchet MS", "Segoe UI", sans-serif; }
        .shell { display: grid; grid-template-columns: 320px 1fr; height: 100%; }
        .panel { padding: 18px 16px; border-right: 1px solid rgba(180,220,220,0.16); background: linear-gradient(180deg, rgba(11,24,31,0.94), rgba(9,18,24,0.86)); backdrop-filter: blur(6px); overflow: auto; }
        .title { font-size: 1.25rem; letter-spacing: 0.08em; text-transform: uppercase; margin: 0 0 8px; }
        .subtitle { margin: 0 0 16px; color: var(--muted); font-size: 0.86rem; }
        .stat { margin: 10px 0; padding: 10px 12px; border: 1px solid rgba(180,220,220,0.16); border-radius: 10px; background: rgba(9,16,20,0.55); }
        .label { color: var(--muted); font-size: 0.78rem; letter-spacing: 0.08em; text-transform: uppercase; }
        .value { font-size: 1.14rem; margin-top: 2px; }
        .legend { margin-top: 16px; display: grid; gap: 8px; font-size: 0.84rem; color: var(--muted); }
        .dot { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 6px; transform: translateY(1px); }
        .stage { position: relative; overflow: hidden; }
        canvas { width: 100%; height: 100%; display: block; }
        .pulse { position: absolute; right: 16px; bottom: 14px; color: var(--muted); font-size: 0.78rem; letter-spacing: 0.05em; }
        @media (max-width: 880px) {
          .shell { grid-template-columns: 1fr; grid-template-rows: auto 1fr; }
          .panel { border-right: 0; border-bottom: 1px solid rgba(180,220,220,0.16); }
        }
      </style>
    </head>
    <body>
      <div class="shell">
        <aside class="panel">
          <h1 class="title">Wetware Viz</h1>
          <p class="subtitle">Live gel state via HTTP polling</p>
          <div class="stat"><div class="label">Step</div><div class="value" id="step">-</div></div>
          <div class="stat"><div class="label">Cells (registry)</div><div class="value" id="cells">-</div></div>
          <div class="stat"><div class="label">Rendered</div><div class="value" id="rendered">-</div></div>
          <div class="stat"><div class="label">Concepts</div><div class="value" id="concepts">-</div></div>
          <div class="stat"><div class="label">Bounds</div><div class="value" id="bounds">-</div></div>
          <div class="legend">
            <div><span class="dot" style="background:#6ef0cd"></span>concept cells</div>
            <div><span class="dot" style="background:#84a8ff"></span>interstitial cells</div>
            <div><span class="dot" style="background:#ff7d57"></span>high activation</div>
            <div><span class="dot" style="background:#ffb26b"></span>charge pulse</div>
          </div>
        </aside>
        <main class="stage">
          <canvas id="viz"></canvas>
          <div class="pulse" id="pulse">Polling...</div>
        </main>
      </div>
      <script>
        const canvas = document.getElementById('viz');
        const ctx = canvas.getContext('2d');
        const labels = {
          step: document.getElementById('step'),
          cells: document.getElementById('cells'),
          rendered: document.getElementById('rendered'),
          concepts: document.getElementById('concepts'),
          bounds: document.getElementById('bounds'),
          pulse: document.getElementById('pulse')
        };

        const prevCharge = new Map();
        let lastTick = performance.now();

        function resize() {
          const dpr = window.devicePixelRatio || 1;
          canvas.width = Math.floor(canvas.clientWidth * dpr);
          canvas.height = Math.floor(canvas.clientHeight * dpr);
          ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        function colorFor(cell) {
          if (cell.charge > 0.75) return '#ff7d57';
          if (cell.kind === 'concept') return '#6ef0cd';
          if (cell.charge > 0.25) return '#9dc7ff';
          return '#4e6b86';
        }

        function draw(state) {
          const w = canvas.clientWidth;
          const h = canvas.clientHeight;
          ctx.clearRect(0, 0, w, h);

          const b = state.bounds || {min_x: 0, max_x: 0, min_y: 0, max_y: 0};
          const spanX = Math.max(1, (b.max_x - b.min_x + 1));
          const spanY = Math.max(1, (b.max_y - b.min_y + 1));
          const pad = 28;
          const scale = Math.max(1.2, Math.min((w - pad * 2) / spanX, (h - pad * 2) / spanY));

          const worldToScreen = (x, y) => ({
            x: pad + (x - b.min_x + 0.5) * scale,
            y: pad + (y - b.min_y + 0.5) * scale
          });

          ctx.strokeStyle = 'rgba(180, 220, 220, 0.12)';
          ctx.lineWidth = 1;
          for (let gx = 0; gx <= spanX; gx += Math.max(1, Math.floor(spanX / 28))) {
            const px = pad + gx * scale;
            ctx.beginPath();
            ctx.moveTo(px, pad);
            ctx.lineTo(px, pad + spanY * scale);
            ctx.stroke();
          }
          for (let gy = 0; gy <= spanY; gy += Math.max(1, Math.floor(spanY / 24))) {
            const py = pad + gy * scale;
            ctx.beginPath();
            ctx.moveTo(pad, py);
            ctx.lineTo(pad + spanX * scale, py);
            ctx.stroke();
          }

          for (const concept of state.concepts || []) {
            const c = worldToScreen(concept.cx, concept.cy);
            ctx.strokeStyle = 'rgba(110, 240, 205, 0.55)';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(c.x, c.y, Math.max(5, concept.r * scale), 0, Math.PI * 2);
            ctx.stroke();

            ctx.fillStyle = 'rgba(219, 239, 232, 0.88)';
            ctx.font = '12px "Avenir Next", "Trebuchet MS", sans-serif';
            ctx.fillText(concept.name, c.x + 6, c.y - 8);
          }

          for (const cell of state.cells || []) {
            const p = worldToScreen(cell.x, cell.y);
            const cellSize = Math.max(2, Math.min(10, scale * 0.8));
            const key = `${cell.x}:${cell.y}`;
            const prev = prevCharge.get(key) || 0;
            const delta = cell.charge - prev;
            prevCharge.set(key, cell.charge);

            ctx.fillStyle = colorFor(cell);
            ctx.globalAlpha = Math.max(0.22, Math.min(1, cell.charge + 0.15));
            ctx.fillRect(p.x - cellSize / 2, p.y - cellSize / 2, cellSize, cellSize);

            if (delta > 0.08) {
              ctx.globalAlpha = Math.min(0.85, delta * 2.2);
              ctx.strokeStyle = '#ffb26b';
              ctx.lineWidth = 1.2;
              ctx.beginPath();
              ctx.arc(p.x, p.y, Math.max(4, cellSize + delta * 22), 0, Math.PI * 2);
              ctx.stroke();
            }
          }

          ctx.globalAlpha = 1;
          labels.step.textContent = state.step_count;
          labels.cells.textContent = state.cell_count;
          labels.rendered.textContent = `${(state.cells || []).length} / ${state.max_cells}`;
          labels.concepts.textContent = (state.concepts || []).length;
          labels.bounds.textContent = `${b.min_x},${b.min_y} -> ${b.max_x},${b.max_y}`;
        }

        async function tick() {
          try {
            const res = await fetch(`/api/state?t=${Date.now()}`, { cache: 'no-store' });
            const state = await res.json();
            draw(state);
            const now = performance.now();
            labels.pulse.textContent = `Polling ${Math.round(now - lastTick)}ms`;
            lastTick = now;
          } catch (_err) {
            labels.pulse.textContent = 'Waiting for gel...';
          }
        }

        window.addEventListener('resize', resize);
        resize();
        tick();
        setInterval(tick, 300);
      </script>
    </body>
    </html>
    """
  end
end
