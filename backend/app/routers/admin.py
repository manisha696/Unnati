
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Response,
)
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.routers.auth import get_current_user
from app.models import user


router = APIRouter(
    prefix="/admin",
    tags=["Administrator"],
)


# Only the bootstrapped Owner can review applications.
async def require_owner(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not current_user.is_active or not current_user.is_owner:
        raise HTTPException(
            status_code=403,
            detail="Owner access required",
        )

    return current_user


class RejectApplicationRequest(BaseModel):
    reason: str = Field(min_length=5, max_length=500)


@router.get("/dashboard")
async def admin_dashboard(
    owner: Annotated[User, Depends(require_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Owner dashboard statistics."""

    result = await db.execute(
        select(User.role, func.count(User.id))
        .where(User.is_active.is_(True))
        .group_by(User.role)
    )

    counts = dict(result.all())

    language_result = await db.execute(
        select(
            User.preferred_language,
            func.count(User.id),
        )
        .where(User.is_active.is_(True))
        .group_by(User.preferred_language)
        .order_by(func.count(User.id).desc())
    )

    languages = [
        {"language": language, "users": count}
        for language, count in language_result.all()
    ]

    pending_count = await db.scalar(
        select(func.count(User.id)).where(
            User.role == "admin",
            User.admin_status == "pending",
        )
    )

    return {
        "message": "Owner dashboard data",
        "owner_name": owner.name,
        "total_users": sum(counts.values()),
        "students": counts.get("student", 0),
        "parents": counts.get("parent", 0),
        "administrators": counts.get("admin", 0),
        "pending_applications": pending_count or 0,
        "users_by_language": languages,
    }


@router.get("/review/applications")
async def list_applications(
    owner: Annotated[User, Depends(require_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status: str = "pending",
):
    """List Admin applications without exposing password or file paths."""

    allowed_statuses = {"pending", "approved", "rejected"}

    if status not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail="Invalid status filter",
        )

    result = await db.execute(
        select(User)
        .where(
            User.role == "admin",
            User.admin_status == status,
        )
        .order_by(User.id.desc())
    )

    applications = result.scalars().all()

    return {
        "applications": [
            {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "phone": user.phone,
                "organization_name": user.organization_name,
                "designation": user.designation,
                "department": user.department,
                "status": user.admin_status,
                "rejection_reason": user.rejection_reason,
                "submitted": user.id_document_path is not None,
            }
            for user in applications
        ]
    }


@router.get("/review/applications/{application_id}/document")
async def view_application_document(
    application_id: int,
    owner: Annotated[User, Depends(require_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Serve a submitted ID document only to the authenticated Owner."""

    user = await db.scalar(
        select(User).where(
            User.id == application_id,
            User.role == "admin",
        )
    )

    if user is None:
        raise HTTPException(
            status_code=404,
            detail="Application not found",
        )

    if not user.id_document_path:
        raise HTTPException(
            status_code=404,
            detail="No ID document was submitted",
        )

    # Do not serve arbitrary paths stored in the database.
    private_dir = (
        Path(__file__).resolve().parents[2]
        / "private_admin_documents"
    ).resolve()

    document_path = Path(user.id_document_path).resolve()

    if (
        not document_path.is_relative_to(private_dir)
        or not document_path.is_file()
    ):
        raise HTTPException(
            status_code=404,
            detail="ID document not found",
        )

    return FileResponse(
        path=document_path,
        media_type="application/octet-stream",
        filename=f"admin-application-{user.id}-id-document",
        headers={"Cache-Control": "no-store"},
    )


@router.post("/review/applications/{application_id}/approve")
async def approve_application(
    application_id: int,
    owner: Annotated[User, Depends(require_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Approve an application; activation is a separate future step."""

    user = await db.scalar(
        select(User)
        .where(
            User.id == application_id,
            User.role == "admin",
        )
        .with_for_update()
    )

    if user is None:
        raise HTTPException(
            status_code=404,
            detail="Application not found",
        )

    if user.admin_status != "pending":
        raise HTTPException(
            status_code=409,
            detail=f"Application is already {user.admin_status}",
        )

    if not user.id_document_path:
        raise HTTPException(
            status_code=400,
            detail="Cannot approve without an ID document",
        )

    user.admin_status = "approved"
    user.is_active = True
    user.rejection_reason = None
    user.reviewed_at = datetime.now(timezone.utc)
    user.reviewed_by_id = owner.id

    await db.commit()

    return {
        "message": "Application approved. Account activation is still required.",
        "application_id": user.id,
        "status": user.admin_status,
        "active": user.is_active,
    }


@router.post("/review/applications/{application_id}/reject")
async def reject_application(
    application_id: int,
    request: RejectApplicationRequest,
    owner: Annotated[User, Depends(require_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Reject an application with a reason."""

    user = await db.scalar(
        select(User)
        .where(
            User.id == application_id,
            User.role == "admin",
        )
        .with_for_update()
    )

    if user is None:
        raise HTTPException(
            status_code=404,
            detail="Application not found",
        )

    if user.admin_status != "pending":
        raise HTTPException(
            status_code=409,
            detail=f"Application is already {user.admin_status}",
        )

    user.admin_status = "rejected"
    user.is_active = False
    user.rejection_reason = request.reason.strip()
    user.reviewed_at = datetime.now(timezone.utc)
    user.reviewed_by_id = owner.id

    await db.commit()

    return {
        "message": "Application rejected.",
        "application_id": user.id,
        "status": user.admin_status,
        "reason": user.rejection_reason,
    }


async def require_admin_or_owner(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not current_user.is_active or (current_user.role != "admin" and not current_user.is_owner):
        raise HTTPException(
            status_code=403,
            detail="Admin or Owner access required",
        )
    return current_user


class UserStatusUpdateRequest(BaseModel):
    is_active: bool


@router.get("/users")
async def list_users(
    user: Annotated[User, Depends(require_admin_or_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
    role: str | None = None,
    search: str | None = None,
    limit: int = 50,
    offset: int = 0,
):
    """List platform users with optional role filtering and name/phone search."""
    stmt = select(User).order_by(User.id.desc()).offset(offset).limit(limit)

    if role and role.lower() != "all":
        stmt = stmt.where(User.role == role.lower())

    if search and search.strip():
        term = f"%{search.strip().lower()}%"
        stmt = stmt.where(
            func.lower(User.name).like(term)
            | User.phone.like(term)
            | func.lower(func.coalesce(User.email, "")).like(term)
        )

    result = await db.execute(stmt)
    users = result.scalars().all()

    total_stmt = select(func.count(User.id))
    if role and role.lower() != "all":
        total_stmt = total_stmt.where(User.role == role.lower())
    total_count = await db.scalar(total_stmt)

    return {
        "total": total_count or 0,
        "users": [
            {
                "id": u.id,
                "name": u.name,
                "phone": u.phone,
                "email": u.email,
                "role": u.role,
                "is_owner": u.is_owner,
                "is_active": u.is_active,
                "preferred_language": u.preferred_language,
                "child_code": u.child_code,
                "profile_completed": u.profile_completed,
                "admin_status": u.admin_status,
            }
            for u in users
        ],
    }


@router.put("/users/{user_id}/status")
async def update_user_status(
    user_id: int,
    request: UserStatusUpdateRequest,
    admin: Annotated[User, Depends(require_admin_or_owner)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Activate or deactivate a user account."""
    target_user = await db.scalar(select(User).where(User.id == user_id))
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    if target_user.is_owner and not admin.is_owner:
        raise HTTPException(status_code=403, detail="Cannot modify Owner status")

    target_user.is_active = request.is_active
    await db.commit()

    return {
        "message": f"User account {'activated' if target_user.is_active else 'deactivated'} successfully",
        "user_id": target_user.id,
        "is_active": target_user.is_active,
    }

