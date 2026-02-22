defmodule Wetware.Viz do
  alias Wetware.Util

  @moduledoc """
  Lightweight local HTTP server for live gel visualization.

  Uses plain TCP + HTTP/1.1 and polling (`/api/state`) to avoid external deps.
  """

  alias Wetware.{Associations, Cell, Concept, Gel, Introspect, Util}

  @default_port 4157
  @max_cells 6_000

  @spec default_port() :: pos_integer()
  def default_port, do: @default_port

  @spec serve(keyword()) :: :ok | {:error, term()}
  def serve(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)

    case :gen_tcp.listen(port, [
           :binary,
           {:ip, {127, 0, 0, 1}},
           packet: :raw,
           active: false,
           reuseaddr: true
         ]) do
      {:ok, listener} ->
        IO.puts("Wetware viz listening on http://127.0.0.1:#{port}")
        accept_loop(listener)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec state_snapshot() :: map()
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
        charge = Util.safe_exit(fn -> Concept.charge(name) end, 0.0)
        %{name: name, cx: cx, cy: cy, r: r, tags: tags, charge: Float.round(charge, 4)}
      end)
      |> Enum.sort_by(& &1.name)

    associations =
      Util.safe_exit(fn -> Associations.all(0.01) end, [])
      |> Enum.map(fn {a, b, weight} -> %{from: a, to: b, weight: weight} end)
      |> Enum.take(30)

    %{
      step_count: Gel.step_count(),
      bounds: Gel.bounds(),
      cells: cells,
      concepts: concepts,
      associations: associations,
      cell_count: Registry.count(Wetware.CellRegistry),
      max_cells: @max_cells,
      timestamp_ms: System.system_time(:millisecond)
    }
  end

  @spec state_json() :: String.t()
  def state_json do
    state_snapshot()
    |> Jason.encode!()
  end

  @spec constellation_snapshot() :: map()
  def constellation_snapshot do
    report = Introspect.report()

    concept_data =
      Gel.concepts()
      |> Enum.map(fn {name, %{center: {cx, cy}, r: r}} ->
        charge = Util.safe_exit(fn -> Concept.charge(name) end, 0.0)
        %{name: name, charge: Float.round(charge, 4), cx: cx, cy: cy, r: r}
      end)
      |> Enum.sort_by(& &1.name)

    %{
      concepts: concept_data,
      associations: report.associations,
      crystals: report.crystals,
      crystallization: report.concept_crystallization,
      topology: report.topology,
      timestamp_ms: System.system_time(:millisecond)
    }
  end

  @spec constellation_json() :: String.t()
  def constellation_json do
    constellation_snapshot()
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
        {:ok, %{method: "GET", path: "/constellation"}} -> http_ok("text/html; charset=utf-8", constellation_html())
        {:ok, %{method: "GET", path: "/api/state"}} -> http_ok("application/json", state_json())
        {:ok, %{method: "GET", path: "/api/constellation"}} -> http_ok("application/json", constellation_json())
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
    Util.safe_exit(fn -> Cell.get_state(pid) end, %{})
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
        .shell { display: grid; grid-template-columns: 300px 1fr; height: 100%; }
        .panel { padding: 16px 14px; border-right: 1px solid rgba(180,220,220,0.16); background: linear-gradient(180deg, rgba(11,24,31,0.94), rgba(9,18,24,0.86)); backdrop-filter: blur(6px); overflow-y: auto; display: flex; flex-direction: column; }
        .title { font-size: 1.2rem; letter-spacing: 0.08em; text-transform: uppercase; margin: 0 0 4px; }
        .subtitle { margin: 0 0 12px; color: var(--muted); font-size: 0.82rem; }
        .stats-row { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin-bottom: 10px; }
        .stat { padding: 8px 10px; border: 1px solid rgba(180,220,220,0.14); border-radius: 8px; background: rgba(9,16,20,0.55); }
        .label { color: var(--muted); font-size: 0.72rem; letter-spacing: 0.08em; text-transform: uppercase; }
        .value { font-size: 1rem; margin-top: 1px; }
        .section-title { color: var(--muted); font-size: 0.72rem; letter-spacing: 0.1em; text-transform: uppercase; margin: 12px 0 6px; }
        .concept-list { flex: 1; min-height: 0; overflow-y: auto; }
        .concept-row { display: flex; align-items: center; padding: 3px 0; font-size: 0.82rem; cursor: default; }
        .concept-row:hover { background: rgba(110,240,205,0.06); }
        .concept-row.highlighted { background: rgba(110,240,205,0.12); }
        .concept-bar { height: 3px; border-radius: 1.5px; margin-right: 8px; min-width: 2px; transition: width 0.3s ease; }
        .concept-name { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .concept-charge { color: var(--muted); font-size: 0.72rem; margin-left: 6px; font-variant-numeric: tabular-nums; }
        .legend { margin-top: 10px; display: grid; gap: 5px; font-size: 0.78rem; color: var(--muted); }
        .dot { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 5px; transform: translateY(1px); }
        .line-dot { display: inline-block; width: 16px; height: 2px; border-radius: 1px; margin-right: 5px; transform: translateY(-2px); }
        .stage { position: relative; overflow: hidden; }
        canvas { width: 100%; height: 100%; display: block; }
        .pulse { position: absolute; right: 16px; bottom: 14px; color: var(--muted); font-size: 0.72rem; letter-spacing: 0.05em; }
        .controls { position: absolute; left: 16px; bottom: 14px; display: flex; gap: 8px; }
        .toggle { background: rgba(9,16,20,0.7); border: 1px solid rgba(180,220,220,0.2); color: var(--muted); font-size: 0.72rem; padding: 4px 10px; border-radius: 6px; cursor: pointer; letter-spacing: 0.05em; text-transform: uppercase; }
        .toggle.active { color: var(--accent); border-color: rgba(110,240,205,0.4); }
        @media (max-width: 880px) {
          .shell { grid-template-columns: 1fr; grid-template-rows: auto 1fr; }
          .panel { border-right: 0; border-bottom: 1px solid rgba(180,220,220,0.16); max-height: 40vh; }
        }
      </style>
    </head>
    <body>
      <div class="shell">
        <aside class="panel">
          <h1 class="title">Wetware</h1>
          <p class="subtitle">Live resonance gel</p>
          <div class="stats-row">
            <div class="stat"><div class="label">Step</div><div class="value" id="step">-</div></div>
            <div class="stat"><div class="label">Cells</div><div class="value" id="cells">-</div></div>
            <div class="stat"><div class="label">Concepts</div><div class="value" id="concepts">-</div></div>
            <div class="stat"><div class="label">Bonds</div><div class="value" id="bonds">-</div></div>
          </div>
          <div class="section-title">Resonance</div>
          <div class="concept-list" id="concept-list"></div>
          <div class="legend">
            <div><span class="dot" style="background:#6ef0cd"></span>concept cells</div>
            <div><span class="dot" style="background:#4e6b86"></span>interstitial</div>
            <div><span class="dot" style="background:#ff7d57"></span>high activation</div>
            <div><span class="line-dot" style="background:rgba(110,240,205,0.5)"></span>association</div>
          </div>
        </aside>
        <main class="stage">
          <canvas id="viz"></canvas>
          <div class="controls">
            <button class="toggle active" id="toggleCells" onclick="toggleLayer('cells')">Cells</button>
            <button class="toggle active" id="toggleBonds" onclick="toggleLayer('bonds')">Bonds</button>
            <button class="toggle active" id="toggleLabels" onclick="toggleLayer('labels')">Labels</button>
          </div>
          <a href="/constellation" style="position:absolute;top:14px;right:16px;color:var(--muted);font-size:0.78rem;text-decoration:none;letter-spacing:0.05em;border:1px solid rgba(180,220,220,0.2);padding:4px 10px;border-radius:6px;background:rgba(9,16,20,0.7);" onmouseover="this.style.color='#6ef0cd';this.style.borderColor='rgba(110,240,205,0.4)'" onmouseout="this.style.color='#a7c9be';this.style.borderColor='rgba(180,220,220,0.2)'">CONSTELLATION ↗</a>
          <div class="pulse" id="pulse">Polling...</div>
        </main>
      </div>
      <script>
        const canvas = document.getElementById('viz');
        const ctx = canvas.getContext('2d');
        const conceptListEl = document.getElementById('concept-list');

        const prevCharge = new Map();
        let lastTick = performance.now();
        let highlightedConcept = null;
        let latestState = null;

        const layers = { cells: true, bonds: true, labels: true };

        function toggleLayer(name) {
          layers[name] = !layers[name];
          document.getElementById('toggle' + name.charAt(0).toUpperCase() + name.slice(1))
            .classList.toggle('active', layers[name]);
          if (latestState) draw(latestState);
        }

        function resize() {
          const dpr = window.devicePixelRatio || 1;
          canvas.width = Math.floor(canvas.clientWidth * dpr);
          canvas.height = Math.floor(canvas.clientHeight * dpr);
          ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        function chargeColor(charge) {
          if (charge > 0.4) return '#6ef0cd';
          if (charge > 0.2) return '#4db89e';
          if (charge > 0.05) return '#357a69';
          return '#2a4a42';
        }

        function cellColor(cell) {
          if (cell.charge > 0.75) return '#ff7d57';
          if (cell.kind === 'concept') return '#6ef0cd';
          if (cell.charge > 0.25) return '#9dc7ff';
          return '#4e6b86';
        }

        function buildConceptList(concepts) {
          const sorted = [...concepts].sort((a, b) => b.charge - a.charge);
          const maxCharge = Math.max(0.01, sorted[0]?.charge || 0.5);

          // Only rebuild DOM if concept count changed
          if (conceptListEl.childElementCount !== sorted.length) {
            conceptListEl.innerHTML = '';
            sorted.forEach(c => {
              const row = document.createElement('div');
              row.className = 'concept-row';
              row.dataset.name = c.name;
              row.innerHTML = `
                <div class="concept-bar" style="width:0px;background:${chargeColor(c.charge)}"></div>
                <span class="concept-name">${c.name}</span>
                <span class="concept-charge">${c.charge.toFixed(3)}</span>
              `;
              row.addEventListener('mouseenter', () => { highlightedConcept = c.name; if (latestState) draw(latestState); });
              row.addEventListener('mouseleave', () => { highlightedConcept = null; if (latestState) draw(latestState); });
              conceptListEl.appendChild(row);
            });
          } else {
            sorted.forEach((c, i) => {
              const row = conceptListEl.children[i];
              if (row) {
                const bar = row.querySelector('.concept-bar');
                const barWidth = Math.max(2, (c.charge / maxCharge) * 80);
                bar.style.width = barWidth + 'px';
                bar.style.background = chargeColor(c.charge);
                row.querySelector('.concept-charge').textContent = c.charge.toFixed(3);
                row.querySelector('.concept-name').textContent = c.name;
                row.dataset.name = c.name;
                row.classList.toggle('highlighted', c.name === highlightedConcept);
              }
            });
          }
        }

        function draw(state) {
          const w = canvas.clientWidth;
          const h = canvas.clientHeight;
          ctx.clearRect(0, 0, w, h);

          const b = state.bounds || {min_x: 0, max_x: 0, min_y: 0, max_y: 0};
          const spanX = Math.max(1, (b.max_x - b.min_x + 1));
          const spanY = Math.max(1, (b.max_y - b.min_y + 1));
          const pad = 36;
          const scale = Math.max(1.2, Math.min((w - pad * 2) / spanX, (h - pad * 2) / spanY));

          const worldToScreen = (x, y) => ({
            x: pad + (x - b.min_x + 0.5) * scale,
            y: pad + (y - b.min_y + 0.5) * scale
          });

          // Build concept position lookup
          const conceptPos = {};
          for (const c of state.concepts || []) {
            conceptPos[c.name] = worldToScreen(c.cx, c.cy);
          }

          // Subtle grid
          ctx.strokeStyle = 'rgba(180, 220, 220, 0.06)';
          ctx.lineWidth = 0.5;
          for (let gx = 0; gx <= spanX; gx += Math.max(1, Math.floor(spanX / 20))) {
            const px = pad + gx * scale;
            ctx.beginPath(); ctx.moveTo(px, pad); ctx.lineTo(px, pad + spanY * scale); ctx.stroke();
          }
          for (let gy = 0; gy <= spanY; gy += Math.max(1, Math.floor(spanY / 16))) {
            const py = pad + gy * scale;
            ctx.beginPath(); ctx.moveTo(pad, py); ctx.lineTo(pad + spanX * scale, py); ctx.stroke();
          }

          // Draw association bonds
          if (layers.bonds) {
            for (const assoc of state.associations || []) {
              const from = conceptPos[assoc.from];
              const to = conceptPos[assoc.to];
              if (!from || !to) continue;

              const isHighlighted = highlightedConcept &&
                (assoc.from === highlightedConcept || assoc.to === highlightedConcept);
              const isDimmed = highlightedConcept && !isHighlighted;

              // Quadratic curve for visual interest — offset perpendicular to the line
              const mx = (from.x + to.x) / 2;
              const my = (from.y + to.y) / 2;
              const dx = to.x - from.x;
              const dy = to.y - from.y;
              const len = Math.sqrt(dx * dx + dy * dy);
              // Perpendicular offset proportional to distance, capped
              const curveAmount = Math.min(20, len * 0.12);
              const cpx = mx + (-dy / len) * curveAmount;
              const cpy = my + (dx / len) * curveAmount;

              const weight = assoc.weight;
              const lineWidth = isHighlighted ? 1.2 + weight * 3.5 : 0.6 + weight * 2.5;
              const alpha = isDimmed ? 0.04 : isHighlighted ? 0.3 + weight * 0.6 : 0.08 + weight * 0.35;

              ctx.beginPath();
              ctx.moveTo(from.x, from.y);
              ctx.quadraticCurveTo(cpx, cpy, to.x, to.y);
              ctx.strokeStyle = isHighlighted
                ? `rgba(110, 240, 205, ${alpha})`
                : `rgba(110, 200, 200, ${alpha})`;
              ctx.lineWidth = lineWidth;
              ctx.stroke();
            }
          }

          // Draw cells
          if (layers.cells) {
            for (const cell of state.cells || []) {
              const p = worldToScreen(cell.x, cell.y);
              const cellSize = Math.max(2, Math.min(8, scale * 0.7));
              const key = `${cell.x}:${cell.y}`;
              const prev = prevCharge.get(key) || 0;
              const delta = cell.charge - prev;
              prevCharge.set(key, cell.charge);

              ctx.fillStyle = cellColor(cell);
              ctx.globalAlpha = Math.max(0.18, Math.min(1, cell.charge + 0.1));
              ctx.fillRect(p.x - cellSize / 2, p.y - cellSize / 2, cellSize, cellSize);

              if (delta > 0.08) {
                ctx.globalAlpha = Math.min(0.7, delta * 2);
                ctx.strokeStyle = '#ffb26b';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.arc(p.x, p.y, Math.max(3, cellSize + delta * 18), 0, Math.PI * 2);
                ctx.stroke();
              }
            }
            ctx.globalAlpha = 1;
          }

          // Draw concept regions and labels
          for (const concept of state.concepts || []) {
            const c = worldToScreen(concept.cx, concept.cy);
            const isHighlighted = concept.name === highlightedConcept;
            const isDimmed = highlightedConcept && !isHighlighted;

            // Region circle — glow based on charge
            const regionAlpha = isDimmed ? 0.12 : isHighlighted ? 0.7 : 0.15 + concept.charge * 0.5;
            ctx.strokeStyle = isHighlighted
              ? `rgba(110, 240, 205, ${regionAlpha})`
              : `rgba(110, 240, 205, ${regionAlpha})`;
            ctx.lineWidth = isHighlighted ? 2.5 : 1.2;
            ctx.beginPath();
            ctx.arc(c.x, c.y, Math.max(5, concept.r * scale), 0, Math.PI * 2);
            ctx.stroke();

            // Subtle fill for active concepts
            if (concept.charge > 0.1 && !isDimmed) {
              ctx.fillStyle = `rgba(110, 240, 205, ${concept.charge * 0.06})`;
              ctx.beginPath();
              ctx.arc(c.x, c.y, Math.max(5, concept.r * scale), 0, Math.PI * 2);
              ctx.fill();
            }

            // Label
            if (layers.labels) {
              const labelAlpha = isDimmed ? 0.2 : isHighlighted ? 1.0 : 0.5 + concept.charge * 0.5;
              ctx.fillStyle = `rgba(219, 239, 232, ${labelAlpha})`;
              ctx.font = isHighlighted
                ? 'bold 13px "Avenir Next", "Trebuchet MS", sans-serif'
                : '11px "Avenir Next", "Trebuchet MS", sans-serif';
              ctx.fillText(concept.name, c.x + concept.r * scale + 4, c.y + 4);
            }
          }

          // Update stats
          document.getElementById('step').textContent = state.step_count;
          document.getElementById('cells').textContent = state.cell_count;
          document.getElementById('concepts').textContent = (state.concepts || []).length;
          document.getElementById('bonds').textContent = (state.associations || []).length;
        }

        async function tick() {
          try {
            const res = await fetch(`/api/state?t=${Date.now()}`, { cache: 'no-store' });
            const state = await res.json();
            latestState = state;
            draw(state);
            buildConceptList(state.concepts || []);
            const now = performance.now();
            document.getElementById('pulse').textContent = `${Math.round(now - lastTick)}ms`;
            lastTick = now;
          } catch (_err) {
            document.getElementById('pulse').textContent = 'Waiting for gel...';
          }
        }

        window.addEventListener('resize', () => { resize(); if (latestState) draw(latestState); });
        resize();
        tick();
        setInterval(tick, 400);
      </script>
    </body>
    </html>
    """
  end

  defp constellation_html do
    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>Concept Constellation — Wetware</title>
    <style>
    :root {
      --bg: #060d12;
      --ink: #d8ece5;
      --muted: #6a8f83;
      --accent: #6ef0cd;
      --warm: #ffb26b;
      --hot: #ff7d57;
    }
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{height:100%;background:var(--bg);color:var(--ink);font-family:"Avenir Next","Segoe UI",sans-serif;overflow:hidden}
    canvas{display:block;width:100%;height:100%}
    #tooltip{position:fixed;pointer-events:none;background:rgba(8,19,24,0.94);border:1px solid rgba(110,240,205,0.3);border-radius:8px;padding:12px 16px;font-size:13px;line-height:1.5;max-width:320px;display:none;z-index:10;backdrop-filter:blur(8px)}
    #tooltip .name{font-size:15px;font-weight:600;color:var(--accent);margin-bottom:4px}
    #tooltip .stat{color:var(--muted);font-size:12px}
    #tooltip .bonds{margin-top:6px;font-size:11px;color:var(--muted)}
    #tooltip .bonds span{color:var(--ink)}
    #legend{position:fixed;bottom:16px;left:16px;font-size:12px;color:var(--muted);line-height:1.8;background:rgba(8,19,24,0.7);padding:12px 16px;border-radius:8px;border:1px solid rgba(110,240,205,0.12)}
    #legend .row{display:flex;align-items:center;gap:8px}
    #legend .swatch{width:24px;height:3px;border-radius:2px}
    #legend .dot{width:10px;height:10px;border-radius:50%}
    #title{position:fixed;top:16px;left:16px}
    #title h1{font-size:20px;letter-spacing:0.1em;text-transform:uppercase;color:var(--accent);opacity:0.7;margin:0}
    #title .sub{font-size:11px;color:var(--muted);margin-top:2px}
    #stats{position:fixed;top:16px;right:16px;font-size:12px;color:var(--muted);text-align:right;line-height:1.6}
    #nav-back{position:fixed;top:50px;left:16px}
    #nav-back a{color:var(--muted);font-size:12px;text-decoration:none;letter-spacing:0.05em;border:1px solid rgba(180,220,220,0.2);padding:4px 10px;border-radius:6px;background:rgba(9,16,20,0.7)}
    #nav-back a:hover{color:var(--accent);border-color:rgba(110,240,205,0.4)}
    #pulse{position:fixed;bottom:16px;right:16px;font-size:11px;color:var(--muted);letter-spacing:0.05em}
    </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <div id="tooltip"></div>
    <div id="title">
      <h1>Concept Constellation</h1>
      <div class="sub">Wetware gel · live associative structure</div>
    </div>
    <div id="nav-back"><a href="/">← GEL VIEW</a></div>
    <div id="stats"></div>
    <div id="pulse">Loading...</div>
    <div id="legend">
      <div class="row"><div class="swatch" style="background:rgba(110,240,205,0.6)"></div> Crystal bonds (deep structure)</div>
      <div class="row"><div class="swatch" style="background:rgba(160,180,255,0.5);height:2px;border-top:1px dashed rgba(160,180,255,0.5)"></div> Association bonds (current)</div>
      <div class="row"><div class="dot" style="background:#6ef0cd"></div> Active concept</div>
      <div class="row"><div class="dot" style="background:#ffb26b"></div> Warm concept</div>
      <div class="row"><div class="dot" style="background:#3a5a52"></div> Dormant concept</div>
    </div>
    <script>
    let concepts = {}, conceptList = [], ASSOCIATIONS = [], CRYSTALS = [], CRYSTALLIZATION = [], TOPOLOGY = {};
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    const tooltip = document.getElementById('tooltip');
    const statsEl = document.getElementById('stats');
    const pulseEl = document.getElementById('pulse');
    let W, H, dpr, hovered = null, time = 0, lastFetch = 0;

    function resize() {
      dpr = window.devicePixelRatio || 1;
      W = window.innerWidth; H = window.innerHeight;
      canvas.width = W * dpr; canvas.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      initPositions();
    }

    const pad = 120;
    function initPositions() {
      if (!conceptList.length) return;
      const allCx = conceptList.map(c => c.cx);
      const allCy = conceptList.map(c => c.cy);
      const minCx = Math.min(...allCx), maxCx = Math.max(...allCx);
      const minCy = Math.min(...allCy), maxCy = Math.max(...allCy);
      const spanCx = maxCx - minCx || 1;
      const spanCy = maxCy - minCy || 1;
      conceptList.forEach(c => {
        const tx = pad + ((c.cx - minCx) / spanCx) * (W - pad * 2);
        const ty = pad + ((c.cy - minCy) / spanCy) * (H - pad * 2);
        // Gentle move toward target if already positioned
        if (c.x === 0 && c.y === 0) { c.x = tx; c.y = ty; }
        c.targetX = tx; c.targetY = ty;
      });
    }

    function simulate() {
      // Repulsion between close nodes
      for (let i = 0; i < conceptList.length; i++) {
        for (let j = i + 1; j < conceptList.length; j++) {
          const a = conceptList[i], b = conceptList[j];
          let dx = b.x - a.x, dy = b.y - a.y;
          let dist = Math.sqrt(dx * dx + dy * dy) || 1;
          if (dist < 55) {
            let force = (55 - dist) / dist * 0.4;
            a.vx -= dx * force; a.vy -= dy * force;
            b.vx += dx * force; b.vy += dy * force;
          }
        }
      }
      // Spring back to gel-derived positions
      conceptList.forEach(c => {
        if (c.targetX !== undefined) {
          c.vx += (c.targetX - c.x) * 0.003;
          c.vy += (c.targetY - c.y) * 0.003;
        }
        c.vx *= 0.85; c.vy *= 0.85;
        c.x += c.vx; c.y += c.vy;
      });
    }

    function nodeColor(c) {
      if (c.charge > 0.3) return '#6ef0cd';
      if (c.charge > 0.05) return '#ffb26b';
      return '#3a5a52';
    }

    function nodeGlow(c) {
      if (c.charge > 0.3) return 'rgba(110,240,205,0.3)';
      if (c.charge > 0.05) return 'rgba(255,178,107,0.2)';
      return 'rgba(58,90,82,0.08)';
    }

    function nodeRadius(c) {
      return Math.max(4, 6 + c.charge * 18 + (c.crystal_bonds / 8000) * 8);
    }

    function draw() {
      time += 0.008;
      simulate();
      ctx.clearRect(0, 0, W, H);

      // Subtle grid
      ctx.strokeStyle = 'rgba(110,240,205,0.025)';
      ctx.lineWidth = 0.5;
      for (let x = 0; x < W; x += 80) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); }
      for (let y = 0; y < H; y += 80) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }

      // Crystal bonds
      CRYSTALS.forEach(bond => {
        const a = concepts[bond.from], b = concepts[bond.to];
        if (!a || !b) return;
        const thickness = Math.max(0.5, Math.min(6, bond.crystal_count / 1500));
        const alpha = Math.max(0.08, Math.min(0.5, bond.crystal_count / 8000));
        const pulse = 1 + Math.sin(time * 1.5 + bond.crystal_count * 0.001) * 0.12;
        ctx.strokeStyle = `rgba(110,240,205,${alpha * pulse})`;
        ctx.lineWidth = thickness;
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        if (bond.crystal_count > 2000) {
          ctx.strokeStyle = `rgba(110,240,205,${alpha * 0.25 * pulse})`;
          ctx.lineWidth = thickness * 3;
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        }
      });

      // Association bonds (dashed)
      ASSOCIATIONS.forEach(bond => {
        const a = concepts[bond.from], b = concepts[bond.to];
        if (!a || !b) return;
        const alpha = Math.max(0.06, Math.min(0.4, bond.weight * 3));
        ctx.strokeStyle = `rgba(160,180,255,${alpha})`;
        ctx.lineWidth = Math.max(0.5, bond.weight * 8);
        ctx.setLineDash([4, 6]);
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        ctx.setLineDash([]);
      });

      // Highlight hovered
      if (hovered) {
        CRYSTALS.forEach(bond => {
          if (bond.from !== hovered.name && bond.to !== hovered.name) return;
          const a = concepts[bond.from], b = concepts[bond.to];
          if (!a || !b) return;
          ctx.strokeStyle = 'rgba(110,240,205,0.6)';
          ctx.lineWidth = Math.max(1, bond.crystal_count / 800);
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        });
        ASSOCIATIONS.forEach(bond => {
          if (bond.from !== hovered.name && bond.to !== hovered.name) return;
          const a = concepts[bond.from], b = concepts[bond.to];
          if (!a || !b) return;
          ctx.strokeStyle = 'rgba(160,180,255,0.6)';
          ctx.lineWidth = Math.max(1, bond.weight * 12);
          ctx.setLineDash([4, 6]);
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
          ctx.setLineDash([]);
        });
      }

      // Concept nodes
      conceptList.forEach(c => {
        const r = nodeRadius(c);
        const isH = hovered === c;

        // Glow
        const glowR = r * (isH ? 4 : 2.5);
        const grad = ctx.createRadialGradient(c.x, c.y, r * 0.5, c.x, c.y, glowR);
        grad.addColorStop(0, nodeGlow(c));
        grad.addColorStop(1, 'transparent');
        ctx.fillStyle = grad;
        ctx.beginPath(); ctx.arc(c.x, c.y, glowR, 0, Math.PI * 2); ctx.fill();

        // Core
        ctx.fillStyle = nodeColor(c);
        ctx.globalAlpha = isH ? 1 : Math.max(0.4, c.charge + 0.2);
        ctx.beginPath(); ctx.arc(c.x, c.y, r, 0, Math.PI * 2); ctx.fill();
        ctx.globalAlpha = 1;

        // Crystallization ring
        if (c.crystal_ratio > 0.1) {
          ctx.strokeStyle = `rgba(255,255,255,${c.crystal_ratio * 0.3})`;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(c.x, c.y, r + 3, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * c.crystal_ratio);
          ctx.stroke();
        }

        // Label
        const fs = isH ? 14 : (c.charge > 0.3 ? 12 : 10);
        ctx.font = `${isH ? '600' : '400'} ${fs}px "Avenir Next","Segoe UI",sans-serif`;
        ctx.fillStyle = isH ? '#fff' : (c.charge > 0.3 ? 'rgba(219,239,232,0.9)' : 'rgba(160,200,190,0.45)');
        ctx.textAlign = 'center';
        ctx.fillText(c.name, c.x, c.y - r - 6);
      });

      // Stats
      if (TOPOLOGY.step_count !== undefined) {
        const active = conceptList.filter(c => c.charge > 0.3).length;
        const warm = conceptList.filter(c => c.charge > 0.05 && c.charge <= 0.3).length;
        const dormant = conceptList.filter(c => c.charge <= 0.05).length;
        const totalCrystal = CRYSTALS.reduce((s, b) => s + b.crystal_count, 0);
        statsEl.innerHTML = `
          Step ${TOPOLOGY.step_count.toLocaleString()}<br>
          ${active} active · ${warm} warm · ${dormant} dormant<br>
          ${CRYSTALS.length} crystal pathways (${totalCrystal.toLocaleString()} bonds)<br>
          ${ASSOCIATIONS.length} association bonds<br>
          ${TOPOLOGY.total_cells.toLocaleString()} cells (${TOPOLOGY.active_cells} active)
        `;
      }

      requestAnimationFrame(draw);
    }

    // Mouse interaction
    canvas.addEventListener('mousemove', e => {
      const mx = e.clientX, my = e.clientY;
      let closest = null, closestDist = 30;
      conceptList.forEach(c => {
        const d = Math.sqrt((c.x - mx) ** 2 + (c.y - my) ** 2);
        if (d < closestDist) { closest = c; closestDist = d; }
      });
      hovered = closest;

      if (closest) {
        canvas.style.cursor = 'pointer';
        const crystalConns = CRYSTALS.filter(b => b.from === closest.name || b.to === closest.name)
          .sort((a, b) => b.crystal_count - a.crystal_count);
        const assocConns = ASSOCIATIONS.filter(b => b.from === closest.name || b.to === closest.name)
          .sort((a, b) => b.weight - a.weight);

        let html = `<div class="name">${closest.name}</div>`;
        html += `<div class="stat">Charge: ${closest.charge.toFixed(4)} · Crystal: ${(closest.crystal_ratio * 100).toFixed(0)}%</div>`;
        html += `<div class="stat">Bonds: ${closest.total_bonds.toLocaleString()} (${closest.crystal_bonds.toLocaleString()} crystallized)</div>`;
        if (crystalConns.length) {
          html += `<div class="bonds"><strong>Crystal:</strong>`;
          crystalConns.slice(0, 5).forEach(b => {
            const other = b.from === closest.name ? b.to : b.from;
            html += `<br>&nbsp;&nbsp;<span>${other}</span> · ${b.crystal_count.toLocaleString()} bonds`;
          });
          html += `</div>`;
        }
        if (assocConns.length) {
          html += `<div class="bonds"><strong>Associations:</strong>`;
          assocConns.slice(0, 5).forEach(b => {
            const other = b.from === closest.name ? b.to : b.from;
            html += `<br>&nbsp;&nbsp;<span>${other}</span> · ${(b.weight * 100).toFixed(1)}%`;
          });
          html += `</div>`;
        }
        tooltip.innerHTML = html;
        tooltip.style.display = 'block';
        let tx = mx + 16, ty = my - 10;
        if (tx + 320 > W) tx = mx - 336;
        if (ty + 200 > H) ty = H - 210;
        tooltip.style.left = tx + 'px'; tooltip.style.top = ty + 'px';
      } else {
        canvas.style.cursor = 'default';
        tooltip.style.display = 'none';
      }
    });

    function processData(data) {
      concepts = {};
      data.concepts.forEach(c => {
        const existing = concepts[c.name];
        concepts[c.name] = {
          name: c.name, charge: c.charge,
          cx: c.cx, cy: c.cy, r: c.r,
          x: existing ? existing.x : 0,
          y: existing ? existing.y : 0,
          vx: existing ? existing.vx : 0,
          vy: existing ? existing.vy : 0,
          crystal_bonds: 0, crystal_ratio: 0, total_bonds: 0
        };
      });
      (data.crystallization || []).forEach(c => {
        if (concepts[c.name]) {
          concepts[c.name].crystal_bonds = c.crystal_bonds;
          concepts[c.name].crystal_ratio = c.crystal_ratio;
          concepts[c.name].total_bonds = c.total_bonds;
        }
      });
      conceptList = Object.values(concepts);
      ASSOCIATIONS = data.associations || [];
      CRYSTALS = data.crystals || [];
      CRYSTALLIZATION = data.crystallization || [];
      TOPOLOGY = data.topology || {};
      initPositions();
    }

    async function fetchData() {
      try {
        const res = await fetch(`/api/constellation?t=${Date.now()}`, { cache: 'no-store' });
        const data = await res.json();
        processData(data);
        lastFetch = performance.now();
        pulseEl.textContent = `Live · ${new Date().toLocaleTimeString()}`;
      } catch (_err) {
        pulseEl.textContent = 'Waiting for gel...';
      }
    }

    resize();
    window.addEventListener('resize', resize);

    // Initial fetch then poll every 3s (constellation is heavier than cell state)
    fetchData().then(() => {
      draw();
      setInterval(fetchData, 3000);
    });
    </script>
    </body>
    </html>
    """
  end
end
