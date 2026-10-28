"""Pydantic request/response models for a meeting's agenda."""

from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.config import settings

MAX_AGENDA_ITEMS = 50


def _strip_required(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError("must not be blank")
    return stripped


def _strip_optional(value: str | None) -> str | None:
    if value is None:
        return None
    return value.strip() or None


class AgendaItemIn(BaseModel):
    topic: str = Field(min_length=1, max_length=200)
    owner: str | None = Field(default=None, max_length=200)
    minutes: int | None = Field(default=None, ge=1, le=480)

    _topic = field_validator("topic")(_strip_required)
    _owner = field_validator("owner")(_strip_optional)


class ActionItemIn(BaseModel):
    task: str = Field(min_length=1, max_length=500)
    owner: str | None = Field(default=None, max_length=200)
    due: date | None = None

    _task = field_validator("task")(_strip_required)
    _owner = field_validator("owner")(_strip_optional)


class AiSuggestion(BaseModel):
    """What the parser suggested, stored as-is next to what the user saved."""

    agenda: dict[str, Any]
    model: str = Field(min_length=1, max_length=100)
    prompt_version: str = Field(min_length=1, max_length=50)


class AgendaSave(BaseModel):
    items: list[AgendaItemIn] = Field(min_length=1, max_length=MAX_AGENDA_ITEMS)
    action_items: list[ActionItemIn] = Field(default_factory=list, max_length=MAX_AGENDA_ITEMS)
    ai_suggestion: AiSuggestion | None = None


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    items: list[AgendaItemIn]
    action_items: list[ActionItemIn]
    ai_suggestion: AiSuggestion | None
    updated_at: datetime

    @field_serializer("updated_at")
    def _in_app_timezone(self, value: datetime) -> str:
        return value.astimezone(settings.tz).isoformat()
