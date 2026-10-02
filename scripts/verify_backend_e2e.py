"""E2E Verification of backend connection flows for Phase 32."""

import json
import urllib.request
import uuid

BASE = "http://127.0.0.1:8000/api/v1"
uid = uuid.uuid4().hex[:6]
email = f"e2e_user_{uid}@example.com"
password = "TestPassword123!"


def req(url, method="GET", data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode("utf-8") if data else None
    r = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(r) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    print(f"--- Starting NextAction E2E Connection Verification ---")

    # 1. Register
    reg = req(
        f"{BASE}/auth/register",
        "POST",
        {"name": "E2E Test User", "email": email, "password": password},
    )
    print(f"[1] Registered user: {reg['email']} (ID: {reg['id']})")

    # 2. Login
    login = req(
        f"{BASE}/auth/login", "POST", {"email": email, "password": password}
    )
    access_token = login["access_token"]
    refresh_token = login["refresh_token"]
    print(f"[2] Logged in successfully: received access_token and refresh_token")

    # 3. Auth Me
    me = req(f"{BASE}/auth/me", "GET", token=access_token)
    print(f"[3] Current user verified: {me['name']} ({me['email']})")

    # 4. Create Client
    client = req(
        f"{BASE}/clients", "POST", {"name": f"E2E Client {uid}"}, token=access_token
    )
    print(f"[4] Created Client: {client['name']} (ID: {client['id']})")

    # 5. Create Workflow
    workflow = req(
        f"{BASE}/workflows",
        "POST",
        {"name": f"E2E Workflow {uid}"},
        token=access_token,
    )
    print(f"[5] Created Workflow: {workflow['name']} (ID: {workflow['id']})")

    # 6. Create Task with reminder and follow-up
    task = req(
        f"{BASE}/tasks",
        "POST",
        {
            "title": f"E2E Deployment Task {uid}",
            "description": "End-to-end deployment verification task",
            "priority": "high",
            "client_id": client["id"],
            "workflow_id": workflow["id"],
            "reminders": [
                {"remind_at": "2026-10-01T10:00:00Z", "notes": "Test reminder"}
            ],
            "follow_ups": [
                {
                    "follow_up_date": "2026-10-02T10:00:00Z",
                    "notes": "Test follow-up",
                }
            ],
        },
        token=access_token,
    )
    task_id = task["id"]
    print(
        f"[6] Created Task: {task['title']} (ID: {task_id}, reminders: {len(task.get('reminders', []))}, follow_ups: {len(task.get('follow_ups', []))})"
    )

    # 7. List Tasks
    tasks = req(f"{BASE}/tasks", "GET", token=access_token)
    print(f"[7] Listed Tasks: found {tasks['total']} tasks for user")

    # 8. Update Task
    updated = req(
        f"{BASE}/tasks/{task_id}",
        "PATCH",
        {"title": f"Updated Task Title {uid}"},
        token=access_token,
    )
    print(f"[8] Updated Task: new title = '{updated['title']}'")

    # 9. Complete Task
    completed = req(
        f"{BASE}/tasks/{task_id}/complete", "POST", token=access_token
    )
    print(
        f"[9] Completed Task: status = {completed['status']}, completed_at = {completed['completed_at']}"
    )

    # 10. Refresh Token Flow
    refreshed = req(
        f"{BASE}/auth/refresh", "POST", {"refresh_token": refresh_token}
    )
    new_access = refreshed["access_token"]
    new_refresh = refreshed["refresh_token"]
    print(f"[10] Token rotated: new access_token & new refresh_token issued")

    # 11. Logout & Revocation
    logout = req(
        f"{BASE}/auth/logout",
        "POST",
        {"refresh_token": new_refresh},
        token=new_access,
    )
    print(f"[11] Logged out: {logout}")

    print("\n>>> ALL 11 BACKEND CONNECTION STEPS PASSED SUCCESSFULLY! <<<")


if __name__ == "__main__":
    main()
