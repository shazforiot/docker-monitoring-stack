"""Traffic generator: calls the demo app a few times per second, so the dashboards have something to show."""
import os, random, time, urllib.request

TARGET = os.environ.get("TARGET", "http://demo-app:8080")
RATE = float(os.environ.get("REQUESTS_PER_SECOND", "6"))
ROUTES = ["/api/products"] * 5 + ["/api/orders"] * 3 + ["/", "/api/missing"]

print("traffic generator: %s at about %s requests per second" % (TARGET, RATE), flush=True)
while True:
    try:
        urllib.request.urlopen(TARGET + random.choice(ROUTES), timeout=5).read()
    except Exception:
        pass                                  # 404s, 500s and a stopped app are all expected here
    time.sleep(random.expovariate(RATE))
