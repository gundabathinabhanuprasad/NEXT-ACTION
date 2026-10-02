"""Performance verification script measuring representative API latencies against live server."""

import json
import time
import urllib.request
import uuid

BASE_URL = "http://127.0.0.1:8000"


def timed_request(method: str, path: str, payload: dict = None, headers: dict = None) -> tuple[int, float, dict, dict]:
    """Execute HTTP request and return (status_code, latency_ms, json_body, response_headers)."""
    url = f"{BASE_URL}{path}"
    req_headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        req_headers.update(headers)

    data = json.dumps(payload).encode("utf-8") if payload else None
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)

    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req) as resp:
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            body = json.loads(resp.read().decode("utf-8"))
            resp_headers = dict(resp.headers)
            return resp.status, elapsed_ms, body, resp_headers
    except urllib.error.HTTPError as e:
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        body = json.loads(e.read().decode("utf-8")) if e.fp else {}
        resp_headers = dict(e.headers)
        return e.code, elapsed_ms, body, resp_headers


def run_benchmark():
    results = {}

    # 1. /health
    st, lat, body, h = timed_request("GET", "/health")
    assert st == 200
    results["health_check_ms"] = round(lat, 2)
    req_id = h.get("X-Request-ID") or h.get("x-request-id")
    results["health_request_id"] = req_id

    # 2. /ready
    st, lat, body, h = timed_request("GET", "/ready")
    assert st == 200
    results["ready_check_ms"] = round(lat, 2)

    # 3. User Register & Login
    unique_suffix = uuid.uuid4().hex[:8]
    email = f"perf_user_{unique_suffix}@example.com"
    password = "PerfPassword123!"

    st, lat, body, _ = timed_request("POST", "/api/v1/auth/register", {"name": "Perf Operator", "email": email, "password": password})
    assert st == 201

    st, lat, body, h = timed_request("POST", "/api/v1/auth/login", {"email": email, "password": password})
    assert st == 200
    token = body["access_token"]
    results["login_latency_ms"] = round(lat, 2)
    auth_headers = {"Authorization": f"Bearer {token}"}

    # 4. Create sample task
    st, lat, body, _ = timed_request(
        "POST",
        "/api/v1/tasks",
        {"title": "Performance Benchmark Task", "priority": "high"},
        headers=auth_headers,
    )
    assert st == 201
    task_id = body["id"]
    results["task_create_latency_ms"] = round(lat, 2)

    # 5. Task List
    st, lat, body, _ = timed_request("GET", "/api/v1/tasks?page=1&page_size=20", headers=auth_headers)
    assert st == 200
    results["task_list_latency_ms"] = round(lat, 2)

    # 6. Task Detail
    st, lat, body, _ = timed_request("GET", f"/api/v1/tasks/{task_id}", headers=auth_headers)
    assert st == 200
    results["task_detail_latency_ms"] = round(lat, 2)

    # 7. Dashboard Summary
    st, lat, body, _ = timed_request("GET", "/api/v1/dashboard/summary?time_range=last_7_days", headers=auth_headers)
    assert st == 200
    results["dashboard_summary_latency_ms"] = round(lat, 2)

    # 8. Reports (Task Summary)
    st, lat, body, _ = timed_request("GET", "/api/v1/reports/task-summary", headers=auth_headers)
    assert st == 200
    results["reports_task_summary_latency_ms"] = round(lat, 2)

    # 9. Notifications List
    st, lat, body, _ = timed_request("GET", "/api/v1/notifications?unread_only=false&page=1&page_size=20", headers=auth_headers)
    assert st == 200
    results["notifications_list_latency_ms"] = round(lat, 2)

    # 10. Scheduler Evaluation
    st, lat, body, _ = timed_request("POST", "/api/v1/scheduler/evaluate", headers=auth_headers)
    assert st == 200
    results["scheduler_evaluate_latency_ms"] = round(lat, 2)

    print("=== PERFORMANCE BENCHMARK RESULTS ===")
    for k, v in results.items():
        print(f"  {k}: {v}")

    return results


if __name__ == "__main__":
    run_benchmark()
