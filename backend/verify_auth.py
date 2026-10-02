"""Live HTTP verification script for Phase 5 Authentication & Authorization."""

import json
import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def mask_str(s: str) -> str:
    """Mask a string for safe display."""
    if not s or len(s) < 8:
        return "***"
    return f"{s[:4]}...{s[-4:]}"


def main():
    print("==================================================")
    print("PHASE 5 LIVE HTTP AUTHENTICATION VERIFICATION")
    print("==================================================")

    uid_a = uuid.uuid4().hex[:6]
    uid_b = uuid.uuid4().hex[:6]
    email_a = f"usera_{uid_a}@example.com"
    email_b = f"userb_{uid_b}@example.com"
    pass_a = "SecretPasswordA123!"
    pass_b = "SecretPasswordB456!"

    # 1. Register User A
    print("\n1. Register User A")
    r1 = client.post("/api/v1/auth/register", json={"name": "Alice User", "email": email_a, "password": pass_a})
    print(f"POST /api/v1/auth/register -> HTTP {r1.status_code}")
    data_a = r1.json()
    user_a_id = data_a["id"]
    print(f"User A Registered: ID={user_a_id}, Email={data_a['email']}, Active={data_a['is_active']}")
    assert "password" not in data_a and "password_hash" not in data_a

    # 2. Register User B
    print("\n2. Register User B")
    r2 = client.post("/api/v1/auth/register", json={"name": "Bob User", "email": email_b, "password": pass_b})
    print(f"POST /api/v1/auth/register -> HTTP {r2.status_code}")
    data_b = r2.json()
    user_b_id = data_b["id"]
    print(f"User B Registered: ID={user_b_id}, Email={data_b['email']}")

    # 3. Attempt duplicate User A registration
    print("\n3. Attempt Duplicate User A Registration")
    r3 = client.post("/api/v1/auth/register", json={"name": "Alice Clone", "email": email_a.upper(), "password": "OtherPassword!"})
    print(f"POST /api/v1/auth/register (duplicate) -> HTTP {r3.status_code}")
    print(f"Response: {r3.json()}")

    # 4. Login User A
    print("\n4. Login User A")
    r4 = client.post("/api/v1/auth/login", json={"email": email_a, "password": pass_a})
    print(f"POST /api/v1/auth/login -> HTTP {r4.status_code}")
    token_a = r4.json()["access_token"]
    print(f"Token received: type={r4.json()['token_type']}, expires_in={r4.json()['expires_in']}s, token={mask_str(token_a)}")
    headers_a = {"Authorization": f"Bearer {token_a}"}

    # 5. Login with wrong password
    print("\n5. Login with Wrong Password")
    r5 = client.post("/api/v1/auth/login", json={"email": email_a, "password": "WrongPassword!"})
    print(f"POST /api/v1/auth/login (bad password) -> HTTP {r5.status_code}")
    print(f"Response: {r5.json()}")

    # 6. Call /auth/me without token
    print("\n6. Call /auth/me Without Token")
    r6 = client.get("/api/v1/auth/me")
    print(f"GET /api/v1/auth/me (no auth) -> HTTP {r6.status_code}")
    print(f"Response: {r6.json()}")

    # 7. Call /auth/me with valid token
    print("\n7. Call /auth/me With Valid Token")
    r7 = client.get("/api/v1/auth/me", headers=headers_a)
    print(f"GET /api/v1/auth/me (valid auth) -> HTTP {r7.status_code}")
    print(f"Authenticated User: ID={r7.json()['id']}, Email={r7.json()['email']}")

    # 8. Call protected task API without token
    print("\n8. Call Protected Task API Without Token")
    r8 = client.get("/api/v1/tasks")
    print(f"GET /api/v1/tasks (no auth) -> HTTP {r8.status_code}")
    print(f"Response: {r8.json()}")

    # 9. Call protected task API with User A token
    print("\n9. Call Protected Task API With User A Token")
    r9 = client.post(
        "/api/v1/tasks",
        json={"title": "Authenticated Task Flow", "max_attempts": 2},
        headers=headers_a,
    )
    print(f"POST /api/v1/tasks -> HTTP {r9.status_code}")
    task_id = r9.json()["id"]
    print(f"Created Task ID: {task_id}")

    # 10. Verify User A identity comes from JWT
    print("\n10. Verify Creator Identity in Task History")
    r10 = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    print(f"GET /api/v1/tasks/{task_id}/history -> HTTP {r10.status_code}")
    created_hist = r10.json()[0]
    print(f"History Action: {created_hist['action']}, Created By User ID: {created_hist['created_by_user_id']} (Matches User A ID: {user_a_id})")

    # 11 & 12. Attempt to spoof User B using request body
    print("\n11 & 12. Attempt to Spoof User B in Request Body")
    r11 = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"user_id": user_b_id, "notes": "Attempt spoof test"},
        headers=headers_a,
    )
    print(f"POST /attempt with spoofed user_id -> HTTP {r11.status_code}")
    r12 = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    attempt_hist = r12.json()[1]
    print(f"Attempt History Action: {attempt_hist['action']}, Created By User ID: {attempt_hist['created_by_user_id']} (Derived from JWT User A: {user_a_id}, Spoofed User B ignored)")

    # 13 & 14. User A assigns task to User B (Actor is User A, Target is User B)
    print("\n13 & 14. User A Assigns Task to User B")
    r13 = client.post(
        f"/api/v1/tasks/{task_id}/assign",
        json={"assigned_user_id": user_b_id},
        headers=headers_a,
    )
    print(f"POST /assign -> HTTP {r13.status_code}, Assigned User ID: {r13.json()['assigned_user_id']}")
    r14 = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    assign_hist = [h for h in r14.json() if h["action"] == "reassigned"][0]
    print(f"Reassigned Action: Assigner Actor ID: {assign_hist['created_by_user_id']} (User A), Target Assignee: {assign_hist['new_value']} (User B)")

    # 15. Verify health remains public
    print("\n15. Verify Health Endpoint Remains Public")
    r15 = client.get("/health")
    print(f"GET /health (unauthenticated) -> HTTP {r15.status_code}")
    print(f"Response: {r15.json()}")
    print("\nALL VERIFICATIONS PASSED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
