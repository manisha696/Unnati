
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    model_validator,
)


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    password: str = Field(min_length=8, max_length=128)

    role: Literal["student", "parent", "admin"]

    phone: str = Field(min_length=10, max_length=10)
    email: EmailStr | None = None

    preferred_language: str = Field(
        default="English",
        max_length=30,
    )

    consent_given: bool = False

    @model_validator(mode="after")
    def validate_registration(self):
        if not self.phone.isdigit():
            raise ValueError(
                "Enter a valid 10-digit mobile number"
            )

        if self.role == "student" and not self.consent_given:
            raise ValueError(
                "Consent is required for student registration"
            )

        return self


class LoginRequest(BaseModel):
    phone: str = Field(min_length=10, max_length=10)
    password: str = Field(min_length=1, max_length=128)

    @model_validator(mode="after")
    def validate_phone(self):
        if not self.phone.isdigit():
            raise ValueError(
                "Enter a valid 10-digit mobile number"
            )

        return self


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: EmailStr | None = None
    phone: str | None = None
    role: str

    preferred_language: str = "English"
    child_code: str | None = None
    profile_completed: bool = False

    organization_name: str | None = None
    designation: str | None = None
    department: str | None = None

    admin_status: str = "not_applicable"
    rejection_reason: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class LinkChildRequest(BaseModel):
    child_code: str = Field(
        min_length=5,
        max_length=20,
    )


# STUDENT PROFILE INPUT
class StudentProfileRequest(BaseModel):
    education_qualification: str | None = None
    marks: str | None = None
    favourite_subjects: str | None = None
    interests: str | None = None
    skills: str | None = None
    career_aspirations: str | None = None
    location: str | None = None
    caste_category: str | None = None
    family_considerations: str | None = None


# PARENT PROFILE INPUT
class ParentProfileRequest(BaseModel):
    parent_education: str | None = None
    parent_occupation: str | None = None
    child_name: str | None = None
    education_budget: str | None = None
    preferred_education_location: str | None = None
    parent_concerns: str | None = None
    preferred_career_pathways: str | None = None
    family_expectations: str | None = None
