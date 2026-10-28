"""ORM model for a meeting's agenda, with the AI suggestion it started from."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class MeetingAgenda(Base):
    __tablename__ = "meeting_agendas"

    # One agenda per meeting; it goes when the meeting goes.
    meeting_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("meetings.id", ondelete="CASCADE"), primary_key=True
    )
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    action_items: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    # What the model suggested, plus the model and the prompt version. Null when
    # the agenda was typed by hand. Suggested vs. saved is the quality signal.
    ai_suggestion: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
