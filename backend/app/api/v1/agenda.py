"""Agenda endpoints. Saving an agenda always goes through here, never through the parser."""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import SessionDep
from app.auth import CurrentUserDep
from app.schemas.agenda import AgendaRead, AgendaSave
from app.services.agenda import AgendaService

router = APIRouter(prefix="/meetings", tags=["agenda"])


def get_agenda_service(session: SessionDep, user: CurrentUserDep) -> AgendaService:
    return AgendaService(session, user.sub)


AgendaServiceDep = Annotated[AgendaService, Depends(get_agenda_service)]


@router.get(
    "/{meeting_id}/agenda",
    response_model=AgendaRead | None,
    summary="Get a meeting's agenda (null when it has none yet)",
    responses={404: {"description": "Meeting not found"}},
)
async def get_agenda(meeting_id: uuid.UUID, service: AgendaServiceDep) -> AgendaRead | None:
    agenda = await service.get(meeting_id)
    return AgendaRead.model_validate(agenda) if agenda else None


@router.post(
    "/{meeting_id}/agenda",
    response_model=AgendaRead,
    summary="Save a meeting's agenda, with the AI suggestion it started from",
    responses={404: {"description": "Meeting not found"}, 422: {"description": "Validation error"}},
)
async def save_agenda(
    meeting_id: uuid.UUID, payload: AgendaSave, service: AgendaServiceDep
) -> AgendaRead:
    return AgendaRead.model_validate(await service.save(meeting_id, payload))
