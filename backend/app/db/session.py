from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings

# pool_pre_ping + pool_recycle: without these, a pooled connection that
# Cloud SQL (or the proxy/socket underneath it) has silently closed while
# idle gets handed out anyway on the next request and fails with a raw
# asyncpg "connection is closed" InterfaceError — a real production
# incident, not a hypothetical: this is exactly what surfaced as an
# intermittent "Something went wrong" on GroupsHomePage right after
# sign-in, on whichever request happened to draw the stale connection.
# pre_ping issues a cheap liveness check before handing out any pooled
# connection and transparently replaces it if dead; recycle proactively
# retires connections older than 30 minutes so they rarely get the
# chance to go stale under us in the first place. Cloud Run's own
# instances can sit idle between requests for far longer than that.
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    future=True,
    pool_pre_ping=True,
    pool_recycle=1800,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
