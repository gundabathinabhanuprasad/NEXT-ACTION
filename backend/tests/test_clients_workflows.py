"""Tests for Client and Workflow REST APIs and service layer integration."""

import uuid
from fastapi.testclient import TestClient
import pytest
from app.db import SessionLocal, get_db
from app.main import app
from app.models.enums import TaskPriority, TaskStatus
from app.services.auth_service import register_user

client = TestClient(app)


@pytest.fixture
def db():
    """Provide a database session for test operations."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture
def auth_headers(db):
    """Fixture providing a registered user and bearer auth headers."""
    email = f"org_test_{uuid.uuid4().hex[:8]}@nextaction.local"
    user = register_user(
        db=db,
        name="Org Test User",
        email=email,
        password="Password123!",
    )
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "Password123!"},
    )
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return headers, user


def test_client_crud_and_authentication(auth_headers):
    """Test full Client CRUD workflow and authentication enforcement."""
    headers, user = auth_headers

    # 1. Unauthenticated request should fail (401)
    unauth_resp = client.get("/api/v1/clients")
    assert unauth_resp.status_code == 401
    assert unauth_resp.json()["error"] == "AUTHENTICATION_REQUIRED"

    # 2. Create client
    create_payload = {
        "name": "Acme Innovations",
        "company": "Acme Corp",
        "email": "contact@acme.com",
        "phone": "+1-555-0199",
        "notes": "Enterprise tier client",
    }
    create_resp = client.post("/api/v1/clients", json=create_payload, headers=headers)
    assert create_resp.status_code == 201
    client_data = create_resp.json()
    client_id = client_data["id"]
    assert client_data["name"] == "Acme Innovations"
    assert client_data["company"] == "Acme Corp"
    assert client_data["email"] == "contact@acme.com"

    # 3. Get client by ID
    get_resp = client.get(f"/api/v1/clients/{client_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == client_id

    # 4. List clients
    list_resp = client.get("/api/v1/clients", headers=headers)
    assert list_resp.status_code == 200
    list_data = list_resp.json()
    assert list_data["total"] >= 1
    assert len(list_data["items"]) >= 1

    # 5. Search clients
    search_resp = client.get("/api/v1/clients?search=Acme Innovations", headers=headers)
    assert search_resp.status_code == 200
    assert any(c["id"] == client_id for c in search_resp.json()["items"])

    # 6. Update client
    update_payload = {
        "name": "Acme Global Industries",
        "company": "Acme Global",
    }
    patch_resp = client.patch(f"/api/v1/clients/{client_id}", json=update_payload, headers=headers)
    assert patch_resp.status_code == 200
    assert patch_resp.json()["name"] == "Acme Global Industries"
    assert patch_resp.json()["company"] == "Acme Global"
    assert patch_resp.json()["email"] == "contact@acme.com"

    # 7. Invalid client ID -> 404
    missing_id = uuid.uuid4()
    missing_resp = client.get(f"/api/v1/clients/{missing_id}", headers=headers)
    assert missing_resp.status_code == 404
    assert missing_resp.json()["error"] == "CLIENT_NOT_FOUND"


def test_workflow_crud_and_authentication(auth_headers):
    """Test full Workflow CRUD workflow and authentication enforcement."""
    headers, user = auth_headers

    # 1. Unauthenticated request should fail (401)
    unauth_resp = client.get("/api/v1/workflows")
    assert unauth_resp.status_code == 401
    assert unauth_resp.json()["error"] == "AUTHENTICATION_REQUIRED"

    # 2. Create workflow
    create_payload = {
        "name": "Customer Onboarding Sprint",
        "description": "Standard 14-day customer onboarding pipeline",
        "is_active": True,
    }
    create_resp = client.post("/api/v1/workflows", json=create_payload, headers=headers)
    assert create_resp.status_code == 201
    wf_data = create_resp.json()
    workflow_id = wf_data["id"]
    assert wf_data["name"] == "Customer Onboarding Sprint"
    assert wf_data["is_active"] is True

    # 3. Get workflow by ID
    get_resp = client.get(f"/api/v1/workflows/{workflow_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == workflow_id

    # 4. List workflows
    list_resp = client.get("/api/v1/workflows", headers=headers)
    assert list_resp.status_code == 200
    list_data = list_resp.json()
    assert list_data["total"] >= 1
    assert len(list_data["items"]) >= 1

    # Search workflow
    search_resp = client.get("/api/v1/workflows?search=Customer Onboarding Sprint", headers=headers)
    assert search_resp.status_code == 200
    assert any(w["id"] == workflow_id for w in search_resp.json()["items"])

    # 5. Filter active workflows
    active_resp = client.get("/api/v1/workflows?is_active=true", headers=headers)
    assert active_resp.status_code == 200
    assert all(w["is_active"] is True for w in active_resp.json()["items"])

    # 6. Update workflow
    update_payload = {
        "name": "Customer Onboarding v2",
        "is_active": False,
    }
    patch_resp = client.patch(f"/api/v1/workflows/{workflow_id}", json=update_payload, headers=headers)
    assert patch_resp.status_code == 200
    assert patch_resp.json()["name"] == "Customer Onboarding v2"
    assert patch_resp.json()["is_active"] is False

    # 7. Invalid workflow ID -> 404
    missing_id = uuid.uuid4()
    missing_resp = client.get(f"/api/v1/workflows/{missing_id}", headers=headers)
    assert missing_resp.status_code == 404
    assert missing_resp.json()["error"] == "WORKFLOW_NOT_FOUND"


def test_task_client_and_workflow_associations(auth_headers):
    """Test task creation referencing real client and workflow and filtering."""
    headers, user = auth_headers

    # Create Client
    c_resp = client.post("/api/v1/clients", json={"name": "Pinnacle Tech"}, headers=headers)
    client_id = c_resp.json()["id"]

    # Create Workflow
    w_resp = client.post("/api/v1/workflows", json={"name": "Product Launch Q4"}, headers=headers)
    workflow_id = w_resp.json()["id"]

    # Create Task associated with both
    task_payload = {
        "title": "Finalize Q4 Architecture Blueprint",
        "client_id": client_id,
        "workflow_id": workflow_id,
        "priority": "urgent",
    }
    task_resp = client.post("/api/v1/tasks", json=task_payload, headers=headers)
    assert task_resp.status_code == 201
    task_data = task_resp.json()
    task_id = task_data["id"]
    assert task_data["client_id"] == client_id
    assert task_data["workflow_id"] == workflow_id

    # Filter tasks by client_id
    client_tasks_resp = client.get(f"/api/v1/tasks?client_id={client_id}", headers=headers)
    assert client_tasks_resp.status_code == 200
    client_tasks = client_tasks_resp.json()["items"]
    assert any(t["id"] == task_id for t in client_tasks)

    # Filter tasks by workflow_id
    workflow_tasks_resp = client.get(f"/api/v1/tasks?workflow_id={workflow_id}", headers=headers)
    assert workflow_tasks_resp.status_code == 200
    workflow_tasks = workflow_tasks_resp.json()["items"]
    assert any(t["id"] == task_id for t in workflow_tasks)
