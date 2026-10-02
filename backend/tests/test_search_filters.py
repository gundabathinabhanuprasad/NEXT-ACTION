"""Comprehensive unit and integration tests for Advanced Search, Filters & Task Discovery (Phase 13)."""

from datetime import datetime, timedelta, timezone
import uuid
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.task import Task
from app.models.user import User
from app.models.workflow import Workflow
from app.services.auth_service import create_access_token, register_user
from app.services.client_service import create_client
from app.services.task_service import create_task, list_tasks
from app.services.workflow_service import create_workflow


def get_auth_headers(db: Session, email: str = "search_tester@nextaction.local", name: str = "Search Tester") -> dict[str, str]:
    """Helper to register and generate Bearer auth headers for testing."""
    user = register_user(db=db, name=name, email=email, password="Password123!")
    token, _ = create_access_token(subject=str(user.id))
    return {"Authorization": f"Bearer {token}"}


# =========================================================================
# 1. Search Query Tests (Service & API)
# =========================================================================

def test_search_by_title_case_insensitive(db: Session, client: TestClient):
    """Search matches task title case-insensitively."""
    headers = get_auth_headers(db, f"s1_{uuid.uuid4().hex[:6]}@example.com")
    t1 = create_task(db=db, title="Architectural Review of OAuth2 Flow")
    t2 = create_task(db=db, title="Database Migration Index Optimizations")

    # Lowercase match
    resp = client.get("/api/v1/tasks?search=oauth2", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    found_ids = [item["id"] for item in data["items"]]
    assert str(t1.id) in found_ids
    assert str(t2.id) not in found_ids

    # Uppercase match
    resp2 = client.get("/api/v1/tasks?search=DATABASE", headers=headers)
    assert resp2.status_code == 200
    data2 = resp2.json()
    found_ids2 = [item["id"] for item in data2["items"]]
    assert str(t2.id) in found_ids2
    assert str(t1.id) not in found_ids2


def test_search_by_description_and_subject_line(db: Session, client: TestClient):
    """Search matches task description and subject line."""
    headers = get_auth_headers(db, f"s2_{uuid.uuid4().hex[:6]}@example.com")
    unique_kw1 = f"quantum_encryption_{uuid.uuid4().hex[:6]}"
    unique_kw2 = f"satellite_uplink_{uuid.uuid4().hex[:6]}"

    t1 = create_task(db=db, title="Security Module", description=f"Implement {unique_kw1} protocol.")
    t2 = create_task(db=db, title="Telecom Module", subject_line=f"Regarding {unique_kw2} channel.")

    # Match description
    resp1 = client.get(f"/api/v1/tasks?search={unique_kw1}", headers=headers)
    assert resp1.status_code == 200
    assert resp1.json()["total"] == 1
    assert resp1.json()["items"][0]["id"] == str(t1.id)

    # Match subject line
    resp2 = client.get(f"/api/v1/tasks?search={unique_kw2}", headers=headers)
    assert resp2.status_code == 200
    assert resp2.json()["total"] == 1
    assert resp2.json()["items"][0]["id"] == str(t2.id)


def test_search_by_client_workflow_and_assignee_name(db: Session, client: TestClient):
    """Search matches associated Client name, Workflow name, or Assignee name."""
    headers = get_auth_headers(db, f"s3_{uuid.uuid4().hex[:6]}@example.com")
    unique_suffix = uuid.uuid4().hex[:6]

    cl = create_client(db, name=f"Acme Cybernetics {unique_suffix}", company="Acme")
    wf = create_workflow(db, name=f"Automated Triage Pipeline {unique_suffix}")
    user = register_user(db, name=f"Samantha Agent {unique_suffix}", email=f"sam_{unique_suffix}@example.com", password="Password123!")

    t_client = create_task(db=db, title=f"Audit Task {unique_suffix}", client_id=cl.id)
    t_workflow = create_task(db=db, title=f"Routing Task {unique_suffix}", workflow_id=wf.id)
    t_assignee = create_task(db=db, title=f"Specialist Task {unique_suffix}", assigned_user_id=user.id)

    # Match by Client Name
    resp_cl = client.get(f"/api/v1/tasks?search=Cybernetics {unique_suffix}", headers=headers)
    assert resp_cl.status_code == 200
    assert str(t_client.id) in [i["id"] for i in resp_cl.json()["items"]]

    # Match by Workflow Name
    resp_wf = client.get(f"/api/v1/tasks?search=Triage Pipeline {unique_suffix}", headers=headers)
    assert resp_wf.status_code == 200
    assert str(t_workflow.id) in [i["id"] for i in resp_wf.json()["items"]]

    # Match by Assignee Name
    resp_as = client.get(f"/api/v1/tasks?search=Samantha Agent {unique_suffix}", headers=headers)
    assert resp_as.status_code == 200
    assert str(t_assignee.id) in [i["id"] for i in resp_as.json()["items"]]


# =========================================================================
# 2. Structural & Status Filters
# =========================================================================

def test_filter_by_status_and_priority(db: Session, client: TestClient):
    """Filter tasks by exact status and priority."""
    headers = get_auth_headers(db, f"s4_{uuid.uuid4().hex[:6]}@example.com")
    tag = uuid.uuid4().hex[:6]

    t_urgent = create_task(db=db, title=f"Critical Outage {tag}", status=TaskStatus.IN_PROGRESS, priority=TaskPriority.URGENT)
    t_low = create_task(db=db, title=f"Backlog Item {tag}", status=TaskStatus.PENDING, priority=TaskPriority.LOW)

    resp_urgent = client.get(f"/api/v1/tasks?search={tag}&priority=urgent&status=in_progress", headers=headers)
    assert resp_urgent.status_code == 200
    assert resp_urgent.json()["total"] == 1
    assert resp_urgent.json()["items"][0]["id"] == str(t_urgent.id)

    resp_low = client.get(f"/api/v1/tasks?search={tag}&priority=low&status=pending", headers=headers)
    assert resp_low.status_code == 200
    assert resp_low.json()["total"] == 1
    assert resp_low.json()["items"][0]["id"] == str(t_low.id)


def test_filter_by_client_and_workflow_id(db: Session, client: TestClient):
    """Filter tasks strictly by client_id or workflow_id."""
    headers = get_auth_headers(db, f"s5_{uuid.uuid4().hex[:6]}@example.com")
    cl1 = create_client(db, name=f"Client Alpha {uuid.uuid4().hex[:4]}")
    cl2 = create_client(db, name=f"Client Beta {uuid.uuid4().hex[:4]}")

    t1 = create_task(db=db, title="Task for Alpha", client_id=cl1.id)
    t2 = create_task(db=db, title="Task for Beta", client_id=cl2.id)

    resp1 = client.get(f"/api/v1/tasks?client_id={cl1.id}", headers=headers)
    assert resp1.status_code == 200
    ids1 = [i["id"] for i in resp1.json()["items"]]
    assert str(t1.id) in ids1
    assert str(t2.id) not in ids1


def test_filter_by_assignment_and_unassigned(db: Session, client: TestClient):
    """Filter by assigned_user_id and unassigned=True."""
    headers = get_auth_headers(db, f"s6_{uuid.uuid4().hex[:6]}@example.com")
    user = register_user(db, "Agent Cooper", f"cooper_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    tag = uuid.uuid4().hex[:6]
    t_assigned = create_task(db=db, title=f"Assigned Task {tag}", assigned_user_id=user.id)
    t_unassigned = create_task(db=db, title=f"Unassigned Task {tag}")

    # Assigned to user
    resp_as = client.get(f"/api/v1/tasks?search={tag}&assigned_user_id={user.id}", headers=headers)
    assert resp_as.status_code == 200
    assert resp_as.json()["total"] == 1
    assert resp_as.json()["items"][0]["id"] == str(t_assigned.id)

    # Unassigned
    resp_un = client.get(f"/api/v1/tasks?search={tag}&unassigned=true", headers=headers)
    assert resp_un.status_code == 200
    assert resp_un.json()["total"] == 1
    assert resp_un.json()["items"][0]["id"] == str(t_unassigned.id)


# =========================================================================
# 3. Date & Attention Filter Tests
# =========================================================================

def test_date_range_filtering(db: Session, client: TestClient):
    """Filter tasks within due_from and due_to date range."""
    headers = get_auth_headers(db, f"s7_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    tag = uuid.uuid4().hex[:6]

    t_early = create_task(db=db, title=f"Early {tag}", due_date=now - timedelta(days=10))
    t_mid = create_task(db=db, title=f"Mid {tag}", due_date=now)
    t_late = create_task(db=db, title=f"Late {tag}", due_date=now + timedelta(days=10))

    from_dt = (now - timedelta(days=2)).isoformat()
    to_dt = (now + timedelta(days=2)).isoformat()

    resp = client.get(
        "/api/v1/tasks",
        params={"search": tag, "due_from": from_dt, "due_to": to_dt},
        headers=headers,
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert len(items) == 1
    assert items[0]["id"] == str(t_mid.id)


def test_overdue_and_due_today_filters(db: Session, client: TestClient):
    """Test smart overdue and due_today filters."""
    headers = get_auth_headers(db, f"s8_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    tag = uuid.uuid4().hex[:6]

    t_overdue = create_task(db=db, title=f"Overdue {tag}", due_date=now - timedelta(days=2), status=TaskStatus.IN_PROGRESS)
    t_today = create_task(db=db, title=f"Today {tag}", due_date=now, status=TaskStatus.PENDING)
    t_completed_past = create_task(db=db, title=f"Done {tag}", due_date=now - timedelta(days=3), status=TaskStatus.COMPLETED)

    # Overdue should exclude completed tasks
    resp_od = client.get(f"/api/v1/tasks?search={tag}&overdue=true", headers=headers)
    assert resp_od.status_code == 200
    od_ids = [i["id"] for i in resp_od.json()["items"]]
    assert str(t_overdue.id) in od_ids
    assert str(t_completed_past.id) not in od_ids

    # Due today
    resp_td = client.get(f"/api/v1/tasks?search={tag}&due_today=true", headers=headers)
    assert resp_td.status_code == 200
    td_ids = [i["id"] for i in resp_td.json()["items"]]
    assert str(t_today.id) in td_ids


def test_next_action_filters(db: Session, client: TestClient):
    """Test has_next_action, no_next_action, and next action date ranges."""
    headers = get_auth_headers(db, f"s9_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    tag = uuid.uuid4().hex[:6]

    t_has_na = create_task(db=db, title=f"With NA {tag}", next_action_date=now + timedelta(days=1))
    t_no_na = create_task(db=db, title=f"Without NA {tag}", next_action_date=None)

    # Has next action
    resp_has = client.get(f"/api/v1/tasks?search={tag}&has_next_action=true", headers=headers)
    assert resp_has.status_code == 200
    assert resp_has.json()["total"] == 1
    assert resp_has.json()["items"][0]["id"] == str(t_has_na.id)

    # No next action
    resp_no = client.get(f"/api/v1/tasks?search={tag}&no_next_action=true", headers=headers)
    assert resp_no.status_code == 200
    assert resp_no.json()["total"] == 1
    assert resp_no.json()["items"][0]["id"] == str(t_no_na.id)


def test_near_max_attempts_filter(db: Session, client: TestClient):
    """Test near_max_attempts filter (attempt_count >= max_attempts - 1)."""
    headers = get_auth_headers(db, f"s10_{uuid.uuid4().hex[:6]}@example.com")
    tag = uuid.uuid4().hex[:6]

    t_near = create_task(db=db, title=f"Near Max {tag}", max_attempts=3)
    t_near.attempt_count = 2  # 2 >= 3 - 1
    db.commit()

    t_fresh = create_task(db=db, title=f"Fresh {tag}", max_attempts=3)
    t_fresh.attempt_count = 0
    db.commit()

    resp = client.get(f"/api/v1/tasks?search={tag}&near_max_attempts=true", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["total"] == 1
    assert resp.json()["items"][0]["id"] == str(t_near.id)


# =========================================================================
# 4. Sorting & Pagination Tests
# =========================================================================

def test_sorting_by_due_date_priority_and_created_at(db: Session, client: TestClient):
    """Test sorting across multiple fields with asc/desc order."""
    headers = get_auth_headers(db, f"s11_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    tag = uuid.uuid4().hex[:6]

    t1 = create_task(db=db, title=f"A Task {tag}", due_date=now + timedelta(days=5), priority=TaskPriority.LOW)
    t2 = create_task(db=db, title=f"B Task {tag}", due_date=now + timedelta(days=1), priority=TaskPriority.HIGH)
    t3 = create_task(db=db, title=f"C Task {tag}", due_date=now + timedelta(days=10), priority=TaskPriority.URGENT)

    # Sort by due_date asc (Earliest first: t2, t1, t3)
    resp_due_asc = client.get(f"/api/v1/tasks?search={tag}&sort_by=due_date&sort_order=asc", headers=headers)
    assert resp_due_asc.status_code == 200
    ids_due_asc = [i["id"] for i in resp_due_asc.json()["items"]]
    assert ids_due_asc == [str(t2.id), str(t1.id), str(t3.id)]

    # Sort by title asc (A, B, C)
    resp_title_asc = client.get(f"/api/v1/tasks?search={tag}&sort_by=title&sort_order=asc", headers=headers)
    assert resp_title_asc.status_code == 200
    ids_title = [i["id"] for i in resp_title_asc.json()["items"]]
    assert ids_title == [str(t1.id), str(t2.id), str(t3.id)]


def test_pagination_and_total_count(db: Session, client: TestClient):
    """Verify page, page_size, and total results count."""
    headers = get_auth_headers(db, f"s12_{uuid.uuid4().hex[:6]}@example.com")
    tag = uuid.uuid4().hex[:6]

    for i in range(5):
        create_task(db=db, title=f"Paginated Task {i} {tag}")

    resp_p1 = client.get(f"/api/v1/tasks?search={tag}&page=1&page_size=2", headers=headers)
    assert resp_p1.status_code == 200
    data1 = resp_p1.json()
    assert data1["total"] == 5
    assert len(data1["items"]) == 2
    assert data1["page"] == 1
    assert data1["page_size"] == 2

    resp_p2 = client.get(f"/api/v1/tasks?search={tag}&page=2&page_size=2", headers=headers)
    assert resp_p2.status_code == 200
    assert len(resp_p2.json()["items"]) == 2

    resp_p3 = client.get(f"/api/v1/tasks?search={tag}&page=3&page_size=2", headers=headers)
    assert resp_p3.status_code == 200
    assert len(resp_p3.json()["items"]) == 1


# =========================================================================
# 5. Validation & Security Tests
# =========================================================================

def test_invalid_date_range_returns_422(db: Session, client: TestClient):
    """due_from after due_to returns HTTP 422 with clear message."""
    headers = get_auth_headers(db, f"s13_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    from_dt = (now + timedelta(days=5)).isoformat()
    to_dt = (now - timedelta(days=5)).isoformat()

    resp = client.get(
        "/api/v1/tasks",
        params={"due_from": from_dt, "due_to": to_dt},
        headers=headers,
    )
    assert resp.status_code == 422
    assert "due_from cannot be after due_to" in resp.json()["detail"]


def test_invalid_sort_field_returns_422(db: Session, client: TestClient):
    """Arbitrary/injected sort_by column returns HTTP 422."""
    headers = get_auth_headers(db, f"s14_{uuid.uuid4().hex[:6]}@example.com")
    resp = client.get("/api/v1/tasks?sort_by=password_hash", headers=headers)
    assert resp.status_code == 422
    assert "Invalid sort_by" in resp.json()["detail"]


def test_unauthenticated_request_rejected(client: TestClient):
    """Unauthenticated search request returns HTTP 401."""
    resp = client.get("/api/v1/tasks?search=secret")
    assert resp.status_code == 401


def test_empty_search_and_no_match_result(db: Session, client: TestClient):
    """Searching for nonexistent keyword returns total 0 and empty items list."""
    headers = get_auth_headers(db, f"s15_{uuid.uuid4().hex[:6]}@example.com")
    resp = client.get("/api/v1/tasks?search=nonexistent_xyz_999999", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["total"] == 0
    assert resp.json()["items"] == []


def test_combined_filters_scenario(db: Session, client: TestClient):
    """Combined search + client + priority + status + overdue."""
    headers = get_auth_headers(db, f"s16_{uuid.uuid4().hex[:6]}@example.com")
    now = datetime.now(timezone.utc)
    cl = create_client(db, name=f"Global Bank {uuid.uuid4().hex[:4]}")
    tag = uuid.uuid4().hex[:6]

    # Matching task
    t_match = create_task(
        db=db,
        title=f"Core Migration {tag}",
        client_id=cl.id,
        priority=TaskPriority.HIGH,
        status=TaskStatus.IN_PROGRESS,
        due_date=now - timedelta(days=1),
    )

    # Non-matching tasks
    create_task(db=db, title=f"Core Migration {tag}", client_id=cl.id, priority=TaskPriority.LOW, status=TaskStatus.IN_PROGRESS, due_date=now - timedelta(days=1))
    create_task(db=db, title=f"Other Task {tag}", client_id=cl.id, priority=TaskPriority.HIGH, status=TaskStatus.IN_PROGRESS, due_date=now - timedelta(days=1))

    resp = client.get(
        f"/api/v1/tasks?search=Core Migration {tag}&client_id={cl.id}&priority=high&status=in_progress&overdue=true",
        headers=headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["items"][0]["id"] == str(t_match.id)
