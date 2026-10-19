from datetime import datetime
from sqlalchemy import DateTime
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, index=True
    )

    name: Mapped[str] = mapped_column(
        String(100), nullable=False
    )

    email: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True, index=True
    )

    phone: Mapped[str] = mapped_column(
        String(10), unique=True, nullable=False, index=True
    )

    password_hash: Mapped[str] = mapped_column(
        String(255), nullable=False
    )

    role: Mapped[str] = mapped_column(
        String(20), nullable=False, index=True
    )

    is_owner: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )

    preferred_language: Mapped[str] = mapped_column(
        String(30), default="English", nullable=False
    )

    consent_given: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )

    # Student registration par generate hoga.
    # Parent registration par Child Code generate nahi hoga.
    child_code: Mapped[str | None] = mapped_column(
        String(20), unique=True, nullable=True, index=True
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )

    profile_completed: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )

    # ADMIN PROFILE
    organization_name: Mapped[str | None] = mapped_column(
        String(200), nullable=True
    )

    designation: Mapped[str | None] = mapped_column(
        String(150), nullable=True
    )

    department: Mapped[str | None] = mapped_column(
        String(150), nullable=True
    )

    # Private file path; actual file storage is handled by the API.
    id_document_path: Mapped[str | None] = mapped_column(
        String(500), nullable=True
    )

    admin_status: Mapped[str] = mapped_column(
        String(20), default="not_applicable", nullable=False
    )

    rejection_reason: Mapped[str | None] = mapped_column(
        String(500), nullable=True
    )

    reviewed_at: Mapped[datetime | None] = mapped_column(
    DateTime(timezone=True), nullable=True
    )

    reviewed_by_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )


class ParentChildLink(Base):
    __tablename__ = "parent_child_links"

    __table_args__ = (
        UniqueConstraint(
            "parent_id",
            "child_id",
            name="uq_parent_child_pair",
        ),
        CheckConstraint(
            "parent_id != child_id",
            name="ck_parent_child_not_same_user",
        ),
    )

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, index=True
    )

    parent_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    child_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
