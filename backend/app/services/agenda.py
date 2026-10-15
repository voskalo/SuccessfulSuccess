"""A meeting's agenda: read it and save it, only for the meeting's owner."""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import MeetingAgenda
from app.repositories.meeting import MeetingRepository
from app.schemas.agenda import AgendaSave
from app.services.meeting import MeetingNotFoundError


class AgendaService:
    def __init__(self, session: AsyncSession, owner_id: str) -> None:
        self.session = session
        self.meetings = MeetingRepository(session, owner_id)

    async def _check_meeting(self, meeting_id: uuid.UUID) -> None:
        # Someone else's meeting behaves exactly like one that does not exist.
        if await self.meetings.get(meeting_id) is None:
            raise MeetingNotFoundError(meeting_id)

    async def get(self, meeting_id: uuid.UUID) -> MeetingAgenda | None:
        await self._check_meeting(meeting_id)
        return await self.session.get(MeetingAgenda, meeting_id)

    async def save(self, meeting_id: uuid.UUID, payload: AgendaSave) -> MeetingAgenda:
        """Create or replace the meeting's agenda."""
        await self._check_meeting(meeting_id)
        agenda = await self.session.get(MeetingAgenda, meeting_id)
        if agenda is None:
            agenda = MeetingAgenda(meeting_id=meeting_id)
            self.session.add(agenda)
        agenda.items = [item.model_dump(mode="json") for item in payload.items]
        agenda.action_items = [item.model_dump(mode="json") for item in payload.action_items]
        agenda.ai_suggestion = (
            payload.ai_suggestion.model_dump(mode="json") if payload.ai_suggestion else None
        )
        await self.session.commit()
        await self.session.refresh(agenda)
        return agenda
