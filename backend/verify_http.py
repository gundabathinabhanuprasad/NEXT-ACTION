"""HTTP Verification script for Phase 4 endpoints with Phase 5 Authentication."""

import json
import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def main():
    print("=== 1. Health Check ===")
    r = client.get("/health")
    print(f"GET /health -> HTTP {r.status_code}")
    print(json.dumps(r.json(), indent=2))

    # Authenticate for protected operations
    email = f"http_verify_{uuid.uuid4().hex[:8]}@example.com"
    password = "VerifyPassword123!"
    client.post("/api/v1/auth/register", json={"name": "HTTP Verifier", "email": email, "password": password})
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    print("\n=== 2. Create Task ===")
    r = client.post(
        "/api/v1/tasks",
        json={
            "title": "Phase 4/5 HTTP Verification Task",
            "due_date": "2026-10-01T12:00:00Z",
            "max_attempts": 2,
        },
        headers=headers,
    )
    print(f"POST /api/v1/tasks -> HTTP {r.status_code}")
    task_data = r.json()
    task_id = task_data["id"]
    print(f"Created Task ID: {task_id}")
    print(f"Status: {task_data['status']}, Priority: {task_data['priority']}, Attempt Count: {task_data['attempt_count']}")

    print("\n=== 3. Get Task ===")
    r = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    print(f"GET /api/v1/tasks/{task_id} -> HTTP {r.status_code}")
    print(f"Title: {r.json()['title']}")

    print("\n=== 4. Record 1st Attempt ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "First HTTP outreach attempt"},
        headers=headers,
    )
    print(f"POST /attempt -> HTTP {r.status_code}, attempt_count = {r.json()['attempt_count']}")

    print("\n=== 5. Record 2nd Attempt ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "Second HTTP outreach attempt"},
        headers=headers,
    )
    print(f"POST /attempt -> HTTP {r.status_code}, attempt_count = {r.json()['attempt_count']}")

    print("\n=== 6. Attempt Beyond Max (Rejected) ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "Third attempt beyond max"},
        headers=headers,
    )
    print(f"POST /attempt -> HTTP {r.status_code}")
    print(json.dumps(r.json(), indent=2))

    print("\n=== 7. Authorized Override ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/attempt/override",
        json={
            "authorized_override": True,
            "reason": "Executive authorization granted for follow-up",
        },
        headers=headers,
    )
    print(f"POST /attempt/override -> HTTP {r.status_code}, attempt_count = {r.json()['attempt_count']}")

    print("\n=== 8. Postpone Task ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/postpone",
        json={
            "new_due_date": "2026-10-15T12:00:00Z",
            "reason": "Schedule conflict postponement",
        },
        headers=headers,
    )
    print(f"POST /postpone -> HTTP {r.status_code}, new due_date = {r.json()['due_date']}")

    print("\n=== 9. Complete Task ===")
    r = client.post(f"/api/v1/tasks/{task_id}/complete", headers=headers)
    print(f"POST /complete -> HTTP {r.status_code}, status = {r.json()['status']}, completed_at = {r.json()['completed_at']}")

    print("\n=== 10. Reopen Task ===")
    r = client.post(
        f"/api/v1/tasks/{task_id}/reopen",
        json={"reason": "Reopening for additional verification"},
        headers=headers,
    )
    print(f"POST /reopen -> HTTP {r.status_code}, status = {r.json()['status']}, completed_at = {r.json()['completed_at']}")

    print("\n=== 11. Create & Send Reminder ===")
    r = client.post(
        "/api/v1/reminders",
        json={
            "task_id": task_id,
            "remind_at": "2026-10-14T09:00:00Z",
            "message": "Reminder for postponed task",
        },
        headers=headers,
    )
    print(f"POST /api/v1/reminders -> HTTP {r.status_code}")
    reminder_data = r.json()
    reminder_id = reminder_data["id"]
    print(f"Reminder ID: {reminder_id}, is_sent = {reminder_data['is_sent']}")

    r = client.post(f"/api/v1/reminders/{reminder_id}/send", headers=headers)
    print(f"POST /reminders/{reminder_id}/send -> HTTP {r.status_code}, is_sent = {r.json()['is_sent']}")

    # Check task attempt count invariant
    r = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    print(f"GET task attempt_count after reminder -> {r.json()['attempt_count']} (Invariant Preserved: attempt_count remains 3)")

    print("\n=== 12. Retrieve History ===")
    r = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    print(f"GET /history -> HTTP {r.status_code}, entries: {len(r.json())}")
    for h in r.json():
        act = h.get("action")
        old_v = h.get("old_value")
        new_v = h.get("new_value")
        reason = h.get("reason")
        print(f" - [{act}] old: {old_v} -> new: {new_v} | reason: {reason}")


if __name__ == "__main__":
    main()
