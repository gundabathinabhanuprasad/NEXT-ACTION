"""MongoDB document schema for TaskHistory audit log."""

from datetime import datetime
from typing import Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.documents.common import utcnow


class TaskHistoryDocument(BaseModel):
    """Immutable audit trail entry for task events and attempts."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()), alias="_id")
    task_id: Optional[str] = Field(default=None, description="Target Task UUID string")
    action: str = Field(min_length=1, max_length=100)
    old_value: Optional[str] = Field(default=None)
    new_value: Optional[str] = Field(default=None)
    reason: Optional[str] = Field(default=None)
    created_by_user_id: Optional[str] = Field(default=None, description="Actor User UUID string")
    created_at: datetime = Field(default_factory=utcnow)

    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
    )

    def to_mongo(self):
        return self.model_dump(by_alias=True)

    def to_domain(self):
        return self.model_dump(by_alias=False)
