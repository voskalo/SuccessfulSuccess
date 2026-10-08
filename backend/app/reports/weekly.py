"""Weekly meetings report builder."""

import csv
import datetime as dt
import io
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionFactory
from app.models import Meeting


def get_iso_week_bounds(iso_week_str: str, tz: ZoneInfo) -> tuple[datetime, datetime]:
    """Parse "2026-W40" into the start and end of that week in the given timezone."""
    # %G is ISO year, %V is ISO week, %u is ISO weekday (1=Monday)
    start = datetime.strptime(f"{iso_week_str}-1", "%G-W%V-%u").replace(tzinfo=tz)
    end = datetime.strptime(f"{iso_week_str}-7 23:59:59.999999", "%G-W%V-%u %H:%M:%S.%f").replace(
        tzinfo=tz
    )
    return start, end


async def get_week_stats(
    session: AsyncSession, start: datetime, end: datetime
) -> tuple[int, float]:
    """Return the number of meetings and total duration in hours for a time window."""
    result = await session.execute(
        select(
            func.count(Meeting.id),
            func.sum(
                func.extract("epoch", Meeting.ends_at)
                - func.extract("epoch", Meeting.starts_at)
            ),
        ).where(Meeting.starts_at >= start, Meeting.starts_at <= end)
    )
    row = result.first()
    count = row[0] or 0
    duration_seconds = float(row[1] or 0.0)
    return count, duration_seconds / 3600.0


async def get_longest_meetings(
    session: AsyncSession, start: datetime, end: datetime, limit: int = 5
) -> list[Meeting]:
    """Return the longest meetings in a time window."""
    result = await session.scalars(
        select(Meeting)
        .where(Meeting.starts_at >= start, Meeting.starts_at <= end)
        .order_by(
            (
                func.extract("epoch", Meeting.ends_at)
                - func.extract("epoch", Meeting.starts_at)
            ).desc()
        )
        .limit(limit)
    )
    return list(result)


async def build_weekly_report_async(week: str) -> bytes:
    """Async implementation of the report builder."""
    tz = ZoneInfo("Europe/Kyiv")
    
    current_start, current_end = get_iso_week_bounds(week, tz)
    
    # Calculate previous week string by subtracting 7 days from current_start
    prev_start_dt = current_start - dt.timedelta(days=7)
    prev_week_str = (
        f"{prev_start_dt.isocalendar().year}-W"
        f"{prev_start_dt.isocalendar().week:02d}"
    )
    
    prev_start, prev_end = get_iso_week_bounds(prev_week_str, tz)

    async with SessionFactory() as session:
        cur_count, cur_duration = await get_week_stats(session, current_start, current_end)
        prev_count, prev_duration = await get_week_stats(session, prev_start, prev_end)
        
        longest = await get_longest_meetings(session, current_start, current_end, limit=5)
        # We need to eager load participants for the longest meetings
        # Actually, participants relationship is lazy="selectin", so it might be loaded
        # automatically when accessed inside the async session.
        # But to be safe we can just use the length of the participants list.
        # Wait, the lazy="selectin" works when accessing the attribute inside the async context.
        # Let's collect the data we need inside the session.
        longest_data = []
        for m in longest:
            longest_data.append({
                "title": m.name,
                "start": m.starts_at.isoformat(),
                "duration_hours": (m.ends_at - m.starts_at).total_seconds() / 3600.0,
                "participants_count": len(m.participants)
            })

    output = io.StringIO()
    writer = csv.writer(output)
    
    writer.writerow(["Weekly Meetings Report", week])
    writer.writerow([])
    
    writer.writerow(["Metric", "This Week", "Last Week", "Change"])
    writer.writerow([
        "Total Meetings", 
        cur_count, 
        prev_count, 
        cur_count - prev_count
    ])
    writer.writerow([
        "Total Duration (hours)", 
        f"{cur_duration:.2f}", 
        f"{prev_duration:.2f}", 
        f"{cur_duration - prev_duration:.2f}"
    ])
    
    writer.writerow([])
    writer.writerow(["Top 5 Longest Meetings"])
    writer.writerow(["Title", "Start", "Duration (hours)", "Participants"])
    for m in longest_data:
        writer.writerow([
            m["title"],
            m["start"],
            f"{m['duration_hours']:.2f}",
            m["participants_count"]
        ])
        
    return output.getvalue().encode("utf-8")


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    import asyncio
    return asyncio.run(build_weekly_report_async(week))

