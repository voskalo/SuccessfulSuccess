# Spry Project Specification (Monorepo)

## Architecture Decision: Monorepo
We are building Spry as a monorepo containing the backend, frontend, and database configuration. 
**Why?** A monorepo provides single-commit atomic changes across the API and client. More importantly, for a team of 4 people building a new product from scratch, a monorepo maximizes the context window. An AI agent (or a human reviewer) can read the endpoint, the data model, the database migration, and the frontend component in a single pass without guessing contracts across repository boundaries.

## Scope of the First Slice
- The backend exposes `GET /api/meetings` (returns a list of meetings) and `POST /api/meetings` (creates a new meeting).
- A **meeting** entity has the following fields: 
  - `id` (UUID or integer)
  - `title` (string)
  - `starts_at` (datetime)
  - `ends_at` (datetime)
  - `attendee_count` (integer)
- The frontend has one main page that fetches and lists meetings, plus a simple form to add a new meeting.

## Directory Structure and Contracts

### 1. `backend/`
- **Purpose**: Hosts the Python REST API.
- **Tech Stack**: FastAPI (HTTP layer), SQLAlchemy (ORM mapping rows to objects), Alembic (schema migrations).
- **Python Version**: `python:3.12-slim`
- **Contract details**: 
  - `GET /api/meetings`: Returns a JSON array of meeting objects (e.g., `[{"id": 1, "title": "Standup", "starts_at": "2026-10-01T10:00:00Z", "ends_at": "2026-10-01T10:30:00Z", "attendee_count": 5}]`).
  - `POST /api/meetings`: Accepts JSON with `title`, `starts_at`, `ends_at`, and `attendee_count`. Returns the created meeting object.

### 2. `frontend/`
- **Purpose**: Hosts the single-page application (SPA).
- **Tech Stack**: React + Vite, Tailwind CSS, shadcn/ui components.
- **Node Version**: `node:20-alpine`
- **Contract details**: Communicates strictly with the backend via the `/api/` endpoints.

### 3. Root Level (`docker-compose.yml`)
- **Purpose**: Single command (`docker compose up --build`) to spin up the entire development environment.
- **Services**:
  1. **postgres**: Runs `postgres:16-alpine`. Listens on internal port 5432.
  2. **backend**: Builds from `backend/Dockerfile`. Maps port 8000 to the host. Depends on `postgres` using a healthcheck (`condition: service_healthy`) to ensure the DB is ready before the API starts.
  3. **frontend**: Builds from `frontend/Dockerfile`. Maps port 5173 to the host. Depends on `backend`.
- **Note**: No extra services like Redis, Celery, or Nginx are included. This is a minimal viable setup.
