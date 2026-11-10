"""Demo shop API: a tiny web app that exposes Prometheus metrics and writes JSON logs.

No dependencies (Python standard library only), so it runs in the stock python image.
  GET /              home page
  GET /api/products  fast endpoint
  GET /api/orders    slower endpoint, fails now and then
  GET /healthz       health check
  GET /metrics       Prometheus metrics (text format)
  GET /chaos?mode=errors|slow|off   make the app misbehave on purpose (used by scripts/break)
"""
import json, os, random, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("PORT", "8080"))
VERSION = os.environ.get("APP_VERSION", "1.0.0")
BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
START = time.time()
LOCK = threading.Lock()

requests_total = {}                    # (route, method, status) -> count
duration_buckets = {}                  # route -> [count per bucket]
duration_sum = {}                      # route -> seconds
duration_count = {}                    # route -> observations
orders_total = 0
in_flight = 0
chaos = "off"                          # off | errors | slow


def log(level, msg, **fields):
    """One JSON object per line on stdout: Docker captures it, Alloy ships it to Loki."""
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "level": level, "msg": msg, "app": "demo-app"}
    rec.update(fields)
    sys.stdout.write(json.dumps(rec) + "\n")
    sys.stdout.flush()


def observe(route, method, status, seconds):
    with LOCK:
        key = (route, method, str(status))
        requests_total[key] = requests_total.get(key, 0) + 1
        b = duration_buckets.setdefault(route, [0] * len(BUCKETS))
        for i, le in enumerate(BUCKETS):
            if seconds <= le:
                b[i] += 1
        duration_sum[route] = duration_sum.get(route, 0.0) + seconds
        duration_count[route] = duration_count.get(route, 0) + 1


def render_metrics():
    out = []
    with LOCK:
        out.append("# HELP demo_http_requests_total HTTP requests handled, by route, method and status code.")
        out.append("# TYPE demo_http_requests_total counter")
        for (route, method, status), n in sorted(requests_total.items()):
            out.append('demo_http_requests_total{route="%s",method="%s",status="%s"} %d' % (route, method, status, n))
        out.append("# HELP demo_http_request_duration_seconds Time spent handling a request.")
        out.append("# TYPE demo_http_request_duration_seconds histogram")
        for route in sorted(duration_buckets):
            for le, n in zip(BUCKETS, duration_buckets[route]):
                out.append('demo_http_request_duration_seconds_bucket{route="%s",le="%s"} %d' % (route, le, n))
            out.append('demo_http_request_duration_seconds_bucket{route="%s",le="+Inf"} %d' % (route, duration_count[route]))
            out.append('demo_http_request_duration_seconds_sum{route="%s"} %.6f' % (route, duration_sum[route]))
            out.append('demo_http_request_duration_seconds_count{route="%s"} %d' % (route, duration_count[route]))
        out.append("# HELP demo_http_in_flight_requests Requests being handled right now.")
        out.append("# TYPE demo_http_in_flight_requests gauge")
        out.append("demo_http_in_flight_requests %d" % in_flight)
        out.append("# HELP demo_orders_total Orders created successfully.")
        out.append("# TYPE demo_orders_total counter")
        out.append("demo_orders_total %d" % orders_total)
        out.append("# HELP demo_chaos_mode 1 for the active chaos mode (off, errors, slow).")
        out.append("# TYPE demo_chaos_mode gauge")
        for m in ("off", "errors", "slow"):
            out.append('demo_chaos_mode{mode="%s"} %d' % (m, 1 if chaos == m else 0))
        out.append("# HELP demo_app_info Build information.")
        out.append("# TYPE demo_app_info gauge")
        out.append('demo_app_info{version="%s"} 1' % VERSION)
        out.append("# HELP demo_app_uptime_seconds Seconds since the app started.")
        out.append("# TYPE demo_app_uptime_seconds gauge")
        out.append("demo_app_uptime_seconds %.0f" % (time.time() - START))
    return "\n".join(out) + "\n"


HOME = """<!doctype html><title>Demo shop API</title>
<body style="font-family:system-ui;max-width:640px;margin:60px auto;line-height:1.6">
<h1>Demo shop API</h1><p>This little app exists to be monitored.</p>
<ul><li><a href="/api/products">/api/products</a></li><li><a href="/api/orders">/api/orders</a></li>
<li><a href="/metrics">/metrics</a> (what Prometheus reads)</li><li><a href="/healthz">/healthz</a></li></ul>
<p>Chaos mode: <b>%s</b></p></body>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "demo-app/" + VERSION

    def log_message(self, *args):          # silence the default access log; we write JSON instead
        pass

    def send(self, status, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global in_flight, orders_total, chaos
        url = urlparse(self.path)
        route = url.path
        if route == "/metrics":
            return self.send(200, render_metrics(), "text/plain; version=0.0.4")
        if route == "/healthz":
            return self.send(200, '{"status":"ok"}')
        if route == "/chaos":
            mode = parse_qs(url.query).get("mode", ["off"])[0]
            if mode in ("off", "errors", "slow"):
                chaos = mode
                log("warning", "chaos mode changed", mode=mode)
                return self.send(200, json.dumps({"chaos": chaos}))
            return self.send(400, '{"error":"mode must be off, errors or slow"}')

        t0 = time.time()
        with LOCK:
            in_flight += 1
        try:
            status, body = 200, ""
            if route == "/":
                body, ctype = HOME % chaos, "text/html"
            elif route == "/api/products":
                time.sleep(random.uniform(0.004, 0.03))
                body, ctype = json.dumps({"products": ["keyboard", "mouse", "monitor", "webcam"]}), "application/json"
            elif route == "/api/orders":
                time.sleep(random.uniform(0.02, 0.18) + (random.uniform(0.6, 1.4) if chaos == "slow" else 0))
                fail = random.random() < (0.6 if chaos == "errors" else 0.02)
                if fail:
                    status, body, ctype = 500, '{"error":"payment service timeout"}', "application/json"
                else:
                    with LOCK:
                        orders_total += 1
                    body, ctype = json.dumps({"order_id": random.randint(10000, 99999), "status": "created"}), "application/json"
            else:
                status, body, ctype = 404, '{"error":"not found"}', "application/json"
            self.send(status, body, ctype)
        finally:
            with LOCK:
                in_flight -= 1
        took = time.time() - t0
        label = route if route in ("/", "/api/products", "/api/orders") else "other"
        observe(label, "GET", status, took)
        level = "error" if status >= 500 else "warning" if status >= 400 else "info"
        msg = "payment service timeout" if status >= 500 else "request handled"
        log(level, msg, route=label, status=status, duration_ms=round(took * 1000, 1))


if __name__ == "__main__":
    log("info", "demo-app started", port=PORT, version=VERSION)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
