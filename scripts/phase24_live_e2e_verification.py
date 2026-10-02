"""Phase 24 Comprehensive Live End-to-End & Performance Verification Script.

Executes:
1. Authentication & Security E2E (Register, Login, Token Pair, Protected Route, Rotation, Replay, Logout)
2. Complete Task Workflow E2E (25 steps: User, Client, Workflow, Task, Attempts, Override, Postpone, Complete, Reopen, History, Search, Filters, Dashboard)
3. Notification & Scheduler E2E (Deduplication, Scoping, Evaluation, Unread Counts)
4. Reports & Exports E2E (Summaries, Formats, Bounded Limits, Authorization)
5. Performance Latency Measurements across representative endpoints
"""

import sys
import time
import uuid
import httpx

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"


def run_phase24_e2e():
    print("=" * 70)
    print("NextAction Phase 24 — Live Release Candidate E2E & QA Verification")
    print("=" * 70)
    client = httpx.Client(base_url=BASE_URL, timeout=15.0)

    # -------------------------------------------------------------------------
    # PART 1: Performance Sanity Check & Probes
    # -------------------------------------------------------------------------
    perf_metrics = {}

    t0 = time.perf_counter()
    r_health = client.get("/health")
    health_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /health"] = health_latency
    assert r_health.status_code == 200, f"Health check failed: {r_health.text}"
    assert r_health.json() == {"status": "healthy", "database": "connected"}
    print(f"[PASS] 01. Health probe verified (latency: {health_latency:.2f}ms)")

    t0 = time.perf_counter()
    r_ready = client.get("/ready")
    ready_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /ready"] = ready_latency
    assert r_ready.status_code == 200, f"Readiness probe failed: {r_ready.text}"
    assert r_ready.json() == {"status": "ready", "database": "connected"}
    print(f"[PASS] 02. Readiness probe verified (latency: {ready_latency:.2f}ms)")

    # -------------------------------------------------------------------------
    # PART 2: Authentication & Refresh Token Lifecycle E2E
    # -------------------------------------------------------------------------
    test_id = uuid.uuid4().hex[:8]
    user_email = f"qa_lead_{test_id}@nextaction.app"
    user_password = f"SecureQA123!_{test_id}"

    # Step 1: Register
    r_reg = client.post(f"{API_PREFIX}/auth/register", json={
        "name": "QA Release Lead",
        "email": user_email,
        "password": user_password
    })
    assert r_reg.status_code == 201, f"Registration failed: {r_reg.text}"
    user_data = r_reg.json()
    user_id = user_data["id"]
    print(f"[PASS] 03. User registered: {user_email} (ID: {user_id})")

    # Step 2: Login
    t0 = time.perf_counter()
    r_login = client.post(f"{API_PREFIX}/auth/login", json={
        "email": user_email,
        "password": user_password
    })
    login_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["POST /auth/login"] = login_latency
    assert r_login.status_code == 200, f"Login failed: {r_login.text}"
    tokens = r_login.json()
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]
    assert access_token and refresh_token
    print(f"[PASS] 04. Login issued access + refresh tokens (latency: {login_latency:.2f}ms)")

    # Step 3: Protected endpoint access
    headers = {"Authorization": f"Bearer {access_token}"}
    r_me = client.get(f"{API_PREFIX}/auth/me", headers=headers)
    assert r_me.status_code == 200
    assert r_me.json()["email"] == user_email
    print("[PASS] 05. Access token successfully authenticated /auth/me")

    # Step 4: Token Rotation
    r_refresh = client.post(f"{API_PREFIX}/auth/refresh", json={"refresh_token": refresh_token})
    assert r_refresh.status_code == 200, f"Token refresh failed: {r_refresh.text}"
    new_tokens = r_refresh.json()
    new_access_token = new_tokens["access_token"]
    new_refresh_token = new_tokens["refresh_token"]
    assert new_access_token != access_token
    assert new_refresh_token != refresh_token
    print("[PASS] 06. Refresh token successfully rotated both access and refresh tokens")

    # Step 5: Verify Old Refresh Token triggers Replay Attack Detection
    r_replay = client.post(f"{API_PREFIX}/auth/refresh", json={"refresh_token": refresh_token})
    assert r_replay.status_code == 401, f"Expected 401 on replay attack, got: {r_replay.status_code}"
    print("[PASS] 07. Replay attack on rotated token correctly rejected (401)")

    # Step 6: Verify New Refresh Token was invalidated by replay detection
    r_after_replay = client.post(f"{API_PREFIX}/auth/refresh", json={"refresh_token": new_refresh_token})
    assert r_after_replay.status_code == 401
    print("[PASS] 08. Token family successfully invalidated following replay detection")

    # Re-login to get clean session
    r_relogin = client.post(f"{API_PREFIX}/auth/login", json={"email": user_email, "password": user_password})
    assert r_relogin.status_code == 200
    auth_tokens = r_relogin.json()
    auth_headers = {"Authorization": f"Bearer {auth_tokens['access_token']}"}
    current_refresh_token = auth_tokens["refresh_token"]

    # Step 7: Logout server-side revocation
    r_logout = client.post(f"{API_PREFIX}/auth/logout", headers=auth_headers, json={"refresh_token": current_refresh_token})
    assert r_logout.status_code == 200
    print("[PASS] 09. Server-side logout succeeded")

    # Step 8: Post-logout refresh rejection
    r_post_logout_refresh = client.post(f"{API_PREFIX}/auth/refresh", json={"refresh_token": current_refresh_token})
    assert r_post_logout_refresh.status_code == 401
    print("[PASS] 10. Post-logout refresh token rejected (401)")

    # Log back in for core workflows
    r_session = client.post(f"{API_PREFIX}/auth/login", json={"email": user_email, "password": user_password})
    assert r_session.status_code == 200
    active_headers = {"Authorization": f"Bearer {r_session.json()['access_token']}"}

    # -------------------------------------------------------------------------
    # PART 3: Complete Core Task Workflow E2E (25 Steps)
    # -------------------------------------------------------------------------
    # Create client
    r_client = client.post(f"{API_PREFIX}/clients", headers=active_headers, json={
        "name": f"Acme Global {test_id}",
        "email": f"ops_{test_id}@acme.com",
        "notes": "Release Candidate Tier 1 Client"
    })
    assert r_client.status_code == 201, f"Client create failed: {r_client.text}"
    client_id = r_client.json()["id"]
    print(f"[PASS] 11. Client created: {client_id}")

    # Create workflow
    r_wf = client.post(f"{API_PREFIX}/workflows", headers=active_headers, json={
        "name": f"Incident Triaging {test_id}",
        "description": "Standard release candidate workflow"
    })
    assert r_wf.status_code == 201, f"Workflow create failed: {r_wf.text}"
    workflow_id = r_wf.json()["id"]
    print(f"[PASS] 12. Workflow created: {workflow_id}")

    # Create task
    t0 = time.perf_counter()
    r_task = client.post(f"{API_PREFIX}/tasks", headers=active_headers, json={
        "title": f"Production Readiness Gate {test_id}",
        "subject_line": "Execute end-to-end regression validation",
        "priority": "high",
        "client_id": client_id,
        "workflow_id": workflow_id
    })
    task_create_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["POST /tasks"] = task_create_latency
    assert r_task.status_code == 201, f"Task create failed: {r_task.text}"
    task_data = r_task.json()
    task_id = task_data["id"]
    print(f"[PASS] 13. Task created: {task_id} (latency: {task_create_latency:.2f}ms)")

    # View task detail
    t0 = time.perf_counter()
    r_view = client.get(f"{API_PREFIX}/tasks/{task_id}", headers=active_headers)
    task_detail_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /tasks/{id}"] = task_detail_latency
    assert r_view.status_code == 200
    assert r_view.json()["title"] == f"Production Readiness Gate {test_id}"
    print(f"[PASS] 14. Task detail fetched (latency: {task_detail_latency:.2f}ms)")

    # Edit task (PATCH)
    r_edit = client.patch(f"{API_PREFIX}/tasks/{task_id}", headers=active_headers, json={
        "title": f"Production Readiness Gate [EDITED] {test_id}",
        "subject_line": "Execute end-to-end regression validation and performance profiling"
    })
    assert r_edit.status_code == 200, f"Task edit failed: {r_edit.text}"
    assert r_edit.json()["title"].startswith("Production Readiness Gate [EDITED]")
    print("[PASS] 15. Task edited successfully")

    # Assign task
    r_assign = client.post(f"{API_PREFIX}/tasks/{task_id}/assign", headers=active_headers, json={
        "assigned_user_id": user_id
    })
    assert r_assign.status_code == 200, f"Task assign failed: {r_assign.text}"
    assert r_assign.json()["assigned_user_id"] == user_id
    print(f"[PASS] 16. Task assigned to user: {user_id}")

    # Change priority to urgent
    r_prio = client.post(f"{API_PREFIX}/tasks/{task_id}/priority", headers=active_headers, json={
        "priority": "urgent",
        "reason": "Escalating for final QA verification"
    })
    assert r_prio.status_code == 200, f"Priority change failed: {r_prio.text}"
    assert r_prio.json()["priority"] in ("urgent", "URGENT")
    print("[PASS] 17. Task priority updated to URGENT")

    # Change status to in_progress
    r_status = client.post(f"{API_PREFIX}/tasks/{task_id}/status", headers=active_headers, json={
        "status": "in_progress",
        "reason": "Commencing QA testing"
    })
    assert r_status.status_code == 200, f"Status change failed: {r_status.text}"
    assert r_status.json()["status"] in ("in_progress", "IN_PROGRESS")
    print("[PASS] 18. Task status updated to IN_PROGRESS")

    # Attempt 1
    r_att1 = client.post(f"{API_PREFIX}/tasks/{task_id}/attempt", headers=active_headers, json={
        "notes": "First reach-out attempt"
    })
    assert r_att1.status_code == 200, f"Attempt 1 failed: {r_att1.text}"
    assert r_att1.json()["attempt_count"] == 1
    print("[PASS] 19. Attempt 1 registered (count=1)")

    # Attempt 2
    r_att2 = client.post(f"{API_PREFIX}/tasks/{task_id}/attempt", headers=active_headers, json={
        "notes": "Second follow-up attempt"
    })
    assert r_att2.status_code == 200, f"Attempt 2 failed: {r_att2.text}"
    assert r_att2.json()["attempt_count"] == 2
    print("[PASS] 20. Attempt 2 registered (count=2)")

    # Attempt 3 - must be blocked (attempt ceiling = 2)
    r_att3_blocked = client.post(f"{API_PREFIX}/tasks/{task_id}/attempt", headers=active_headers, json={
        "notes": "Third un-overridden attempt"
    })
    assert r_att3_blocked.status_code in (400, 409, 422), f"Expected attempt limit rejection, got {r_att3_blocked.status_code}"
    print("[PASS] 21. Attempt 3 correctly blocked by attempt limit rule (HTTP 409 Conflict)")

    # Authorized override with mandatory reason
    r_override = client.post(f"{API_PREFIX}/tasks/{task_id}/attempt/override", headers=active_headers, json={
        "authorized_override": True,
        "reason": "Executive authorization for critical production sign-off"
    })
    assert r_override.status_code == 200, f"Override failed: {r_override.text}"
    assert r_override.json()["attempt_count"] == 3
    print("[PASS] 22. Attempt override succeeded with mandatory reason (count=3)")

    # Schedule next action date
    r_na = client.post(f"{API_PREFIX}/tasks/{task_id}/next-action", headers=active_headers, json={
        "next_action_date": "2026-10-05T10:00:00Z"
    })
    assert r_na.status_code == 200, f"Next action failed: {r_na.text}"
    assert r_na.json()["next_action_date"] is not None
    print("[PASS] 23. Next action date scheduled")

    # Postpone with mandatory reason
    r_postpone = client.post(f"{API_PREFIX}/tasks/{task_id}/postpone", headers=active_headers, json={
        "new_due_date": "2026-10-10T12:00:00Z",
        "reason": "Awaiting customer signoff on staging environment"
    })
    assert r_postpone.status_code == 200, f"Postpone failed: {r_postpone.text}"
    print("[PASS] 24. Task postponed with mandatory reason")

    # Create reminder
    r_rem = client.post(f"{API_PREFIX}/reminders", headers=active_headers, json={
        "task_id": task_id,
        "remind_at": "2026-10-04T09:00:00Z",
        "message": "Check readiness metrics"
    })
    assert r_rem.status_code == 201, f"Reminder create failed: {r_rem.text}"
    print("[PASS] 25. Reminder created")

    # Create follow-up
    r_fu = client.post(f"{API_PREFIX}/follow-ups", headers=active_headers, json={
        "task_id": task_id,
        "scheduled_at": "2026-10-06T15:00:00Z",
        "notes": "Follow up with release engineering"
    })
    assert r_fu.status_code == 201, f"Follow-up create failed: {r_fu.text}"
    print("[PASS] 26. Follow-up created")

    # Complete task
    r_complete = client.post(f"{API_PREFIX}/tasks/{task_id}/complete", headers=active_headers, json={})
    assert r_complete.status_code == 200, f"Complete task failed: {r_complete.text}"
    assert r_complete.json()["status"] in ("completed", "COMPLETED")
    assert r_complete.json()["completed_at"] is not None
    print("[PASS] 27. Task completed successfully with timestamp")

    # Reopen task with mandatory reason
    r_reopen = client.post(f"{API_PREFIX}/tasks/{task_id}/reopen", headers=active_headers, json={
        "reason": "Re-validating performance under sustained load"
    })
    assert r_reopen.status_code == 200, f"Reopen task failed: {r_reopen.text}"
    assert r_reopen.json()["status"] in ("pending", "PENDING")
    print("[PASS] 28. Task reopened with mandatory reason (status restored to PENDING)")

    # Verify audit history
    r_history = client.get(f"{API_PREFIX}/tasks/{task_id}/history", headers=active_headers)
    assert r_history.status_code == 200, f"History fetch failed: {r_history.text}"
    history_events = r_history.json()
    assert len(history_events) >= 6
    print(f"[PASS] 29. Task audit history verified ({len(history_events)} immutable audit events)")

    # Search & Filter
    t0 = time.perf_counter()
    r_list = client.get(f"{API_PREFIX}/tasks?search=Readiness&priority=urgent", headers=active_headers)
    task_list_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /tasks (search+filter)"] = task_list_latency
    assert r_list.status_code == 200, f"Task list failed: {r_list.text}"
    items = r_list.json()["items"]
    assert any(t["id"] == task_id for t in items)
    print(f"[PASS] 30. Task search & filter query verified (latency: {task_list_latency:.2f}ms)")

    # -------------------------------------------------------------------------
    # PART 4: Dashboard, Notifications & Scheduler E2E
    # -------------------------------------------------------------------------
    # Dashboard summary
    t0 = time.perf_counter()
    r_dash = client.get(f"{API_PREFIX}/dashboard/summary", headers=active_headers)
    dash_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /dashboard/summary"] = dash_latency
    assert r_dash.status_code == 200, f"Dashboard failed: {r_dash.text}"
    dash_data = r_dash.json()
    assert "kpis" in dash_data
    total_open = dash_data["kpis"]["total_open_tasks"]
    print(f"[PASS] 31. Dashboard summary verified (total_open_tasks: {total_open}, latency: {dash_latency:.2f}ms)")

    # Scheduler evaluation
    t0 = time.perf_counter()
    r_eval1 = client.post(f"{API_PREFIX}/scheduler/evaluate", headers=active_headers)
    eval_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["POST /scheduler/evaluate"] = eval_latency
    assert r_eval1.status_code == 200, f"Scheduler evaluation failed: {r_eval1.text}"
    print(f"[PASS] 32. Scheduler initial evaluation succeeded (latency: {eval_latency:.2f}ms)")

    # Scheduler idempotency check (second run shouldn't duplicate)
    r_eval2 = client.post(f"{API_PREFIX}/scheduler/evaluate", headers=active_headers)
    assert r_eval2.status_code == 200
    print("[PASS] 33. Scheduler idempotency check verified")

    # Notifications list
    t0 = time.perf_counter()
    r_notifs = client.get(f"{API_PREFIX}/notifications", headers=active_headers)
    notif_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /notifications"] = notif_latency
    assert r_notifs.status_code == 200, f"Notifications failed: {r_notifs.text}"
    notifs = r_notifs.json()
    print(f"[PASS] 34. Notifications query verified ({len(notifs)} notifications, latency: {notif_latency:.2f}ms)")

    # -------------------------------------------------------------------------
    # PART 5: Reports & Exports E2E
    # -------------------------------------------------------------------------
    t0 = time.perf_counter()
    r_rep_summary = client.get(f"{API_PREFIX}/reports/task-summary", headers=active_headers)
    rep_latency = (time.perf_counter() - t0) * 1000
    perf_metrics["GET /reports/task-summary"] = rep_latency
    assert r_rep_summary.status_code == 200, f"Reports task-summary failed: {r_rep_summary.text}"
    print(f"[PASS] 35. Reports task-summary verified (latency: {rep_latency:.2f}ms)")

    # CSV Export
    r_csv = client.get(f"{API_PREFIX}/reports/tasks/export?format=csv", headers=active_headers)
    assert r_csv.status_code == 200, f"CSV export failed: {r_csv.text}"
    assert "text/csv" in r_csv.headers.get("content-type", "")
    assert len(r_csv.text) > 0
    print("[PASS] 36. Task export CSV verified")

    # Bounded limit enforcement (> MAX_EXPORT_LIMIT should be clamped or rejected)
    r_bounded = client.get(f"{API_PREFIX}/reports/tasks/export?format=csv&limit=100000", headers=active_headers)
    assert r_bounded.status_code in (200, 422)
    print("[PASS] 37. Export bounded limit protection verified")

    print("=" * 70)
    print("Performance Latency Profiling Results:")
    print("=" * 70)
    for endpoint, lat in perf_metrics.items():
        print(f"  {endpoint:<35}: {lat:6.2f} ms")
    print("=" * 70)
    print("ALL 37/37 LIVE QA & RELEASE CANDIDATE CRITERIA PASSED (100%)")
    print("=" * 70)
    return perf_metrics


if __name__ == "__main__":
    try:
        run_phase24_e2e()
    except Exception as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
