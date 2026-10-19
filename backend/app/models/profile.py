
from sqlalchemy import Integer, String, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from app.models.user import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, index=True
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # STUDENT PROFILE
    education_qualification: Mapped[str | None] = mapped_column(
        String(150), nullable=True
    )
    marks: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    favourite_subjects: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    interests: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    skills: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    career_aspirations: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    location: Mapped[str | None] = mapped_column(
        String(200), nullable=True
    )
    caste_category: Mapped[str | None] = mapped_column(
        String(50), nullable=True
    )
    caste_certificate_status: Mapped[str | None] = mapped_column(
        String(50), nullable=True
    )
    family_considerations: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )

    # PARENT PROFILE
    parent_education: Mapped[str | None] = mapped_column(
        String(150), nullable=True
    )
    parent_occupation: Mapped[str | None] = mapped_column(
        String(150), nullable=True
    )
    child_name: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    education_budget: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    preferred_education_location: Mapped[str | None] = mapped_column(
        String(200), nullable=True
    )
    parent_concerns: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    preferred_career_pathways: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    family_expectations: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
