
import os
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    status,
    UploadFile,
    File,
    Form,
)
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from pwdlib import PasswordHash
from pydantic import BaseModel, Field, EmailStr
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User, ParentChildLink
from app.models.profile import UserProfile
from app.schemas.auth import (
    RegisterRequest,
    LoginRequest,
    ParentCodeLoginRequest,
    UserResponse,
    TokenResponse,
    LinkChildRequest,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])

security = HTTPBearer()
password_hash = PasswordHash.recommended()

# Keep this environment variable identical across server restarts.
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "CHANGE_THIS_TO_YOUR_SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

DOCUMENT_DIR = Path(
    os.getenv(
        "ADMIN_DOCUMENT_DIR",
        str(Path(__file__).resolve().parents[2] / "private_admin_documents"),
    )
).resolve()

ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg"}
MAX_DOCUMENT_SIZE = 5 * 1024 * 1024



class ProfileUpdateRequest(BaseModel):
    # STUDENT: personal education and career details
    education_qualification: str | None = Field(default=None, max_length=150)
    marks: str | None = Field(default=None, max_length=100)
    favourite_subjects: str | None = None
    interests: str | None = None
    skills: str | None = None
    career_aspirations: str | None = None
    location: str | None = Field(default=None, max_length=200)
    caste_category: str | None = Field(default=None, max_length=50)
    caste_certificate_status: str | None = Field(default=None, max_length=50)
    family_considerations: str | None = None

    # PARENT: family background and expectations
    parent_education: str | None = Field(default=None, max_length=150)
    parent_occupation: str | None = Field(default=None, max_length=150)
    child_name: str | None = Field(default=None, max_length=100)
    education_budget: str | None = Field(default=None, max_length=100)
    preferred_education_location: str | None = Field(default=None, max_length=200)
    parent_concerns: str | None = None
    preferred_career_pathways: str | None = None
    family_expectations: str | None = None



class AdminProfileRequest(BaseModel):
    organization_name: str = Field(min_length=2, max_length=200)
    designation: str = Field(min_length=2, max_length=150)
    department: str = Field(min_length=2, max_length=150)


def make_user_response(user: User) -> UserResponse:
    return UserResponse.model_validate(user)


def create_access_token(user: User) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "sub": str(user.id),
        "role": user.role,
        "is_owner": user.is_owner,
        "exp": expire,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


async def get_current_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials, Depends(security)
    ],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    try:
        payload = jwt.decode(
            credentials.credentials,
            SECRET_KEY,
            algorithms=[ALGORITHM],
        )
        user_id = int(payload.get("sub", ""))
    except (JWTError, ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
        )

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account not found or inactive",
        )

    if user.role == "admin" and user.admin_status != "approved":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator account is awaiting approval",
        )

    return user



@router.post("/register", response_model=UserResponse, status_code=201)
async def register(
    data: RegisterRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    existing = await db.execute(
        select(User).where(
            (User.phone == data.phone.strip())
            | (
                User.email == str(data.email).lower().strip()
                if data.email
                else User.id == -1
            )
        )
    )

    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=409,
            detail="This mobile number or email is already registered",
        )

    child_code = (
        "CH-" + secrets.token_hex(4).upper()
        if data.role == "student"
        else None
    )

    user = User(
        name=data.name.strip(),
        phone=data.phone.strip(),
        email=str(data.email).lower().strip() if data.email else None,
        password_hash=password_hash.hash(data.password),
        role=data.role,
        is_owner=False,
        preferred_language=data.preferred_language,
        consent_given=data.consent_given,
        child_code=child_code,
        is_active=True,
        profile_completed=False,
        admin_status="approved" if data.role == "admin" else "not_applicable",
    )

    db.add(user)

    try:
        await db.commit()
        await db.refresh(user)
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="This account or Child Code already exists. Try again.",
        )

    return make_user_response(user)


@router.post("/admin-application", response_model=UserResponse, status_code=201)
async def register_admin(
    name: Annotated[str, Form()],
    phone: Annotated[str, Form()],
    password: Annotated[str, Form()],
    preferred_language: Annotated[str, Form()] = "English",
    db: AsyncSession = Depends(get_db),
):
    if not name.strip():
        raise HTTPException(status_code=400, detail="Name is required")

    if len(password) < 8 or len(password) > 128:
        raise HTTPException(
            status_code=400,
            detail="Password must be 8 to 128 characters",
        )

    if len(phone) != 10 or not phone.isdigit():
        raise HTTPException(
            status_code=400,
            detail="Enter a valid 10-digit mobile number",
        )

    existing = await db.execute(
        select(User).where(User.phone == phone)
    )

    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=409,
            detail="This mobile number is already registered",
        )

    user = User(
        name=name.strip(),
        phone=phone,
        password_hash=password_hash.hash(password),
        role="admin",
        is_owner=False,
        preferred_language=preferred_language,
        consent_given=False,
        is_active=True,
        profile_completed=False,
        admin_status="approved",
    )

    db.add(user)

    try:
        await db.commit()
        await db.refresh(user)
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="This mobile number is already registered",
        )

    return make_user_response(user)

    


@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    identifier = (data.identifier or data.phone or "").strip()
    result = await db.execute(
        select(User).where(
            (User.phone == identifier)
            | (func.lower(User.email) == identifier.lower())
        )
    )
    user = result.scalar_one_or_none()

    if not user or not password_hash.verify(
        data.password, user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect mobile number, email, or password",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive",
        )

    if user.role == "admin" and user.admin_status != "approved":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin account is awaiting approval",
        )

    return TokenResponse(
        access_token=create_access_token(user),
        token_type="bearer",
        user=make_user_response(user),
    )


@router.post("/parent-code-login", response_model=TokenResponse)
async def parent_code_login(
    data: ParentCodeLoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Direct login for parents using student's Child Code."""
    code = data.child_code.strip().upper()
    child = await db.scalar(
        select(User).where(
            User.child_code == code,
            User.role == "student",
            User.is_active.is_(True),
        )
    )
    if not child:
        raise HTTPException(
            status_code=404,
            detail="Student Child Code not found. Please verify with your child.",
        )

    parent_phone = data.parent_phone.strip() if data.parent_phone else None
    if parent_phone and (not parent_phone.isdigit() or len(parent_phone) != 10):
        raise HTTPException(
            status_code=400,
            detail="Enter a valid 10-digit mobile number",
        )

    parent_user = None

    if parent_phone:
        parent_user = await db.scalar(
            select(User).where(User.phone == parent_phone)
        )
    else:
        # Check if parent is already linked to this child
        link = await db.scalar(
            select(ParentChildLink).where(ParentChildLink.child_id == child.id)
        )
        if link:
            parent_user = await db.scalar(
                select(User).where(User.id == link.parent_id, User.is_active.is_(True))
            )

    if not parent_user:
        # Create a persistent parent account
        if not parent_phone:
            parent_phone = f"98{child.id:08d}"[-10:]
            while await db.scalar(select(User.id).where(User.phone == parent_phone)):
                parent_phone = f"9{secrets.randbelow(10**9):09d}"

        parent_name = data.parent_name.strip() if data.parent_name else f"Parent of {child.name}"
        parent_user = User(
            name=parent_name,
            phone=parent_phone,
            password_hash=password_hash.hash(secrets.token_hex(16)),
            role="parent",
            is_owner=False,
            preferred_language=child.preferred_language or "English",
            consent_given=True,
            is_active=True,
            profile_completed=True,
            admin_status="not_applicable",
        )
        db.add(parent_user)
        await db.flush()

    # Ensure the parent-child link exists
    existing_link = await db.scalar(
        select(ParentChildLink).where(
            ParentChildLink.parent_id == parent_user.id,
            ParentChildLink.child_id == child.id,
        )
    )
    if not existing_link:
        db.add(ParentChildLink(parent_id=parent_user.id, child_id=child.id))

    await db.commit()
    await db.refresh(parent_user)

    return TokenResponse(
        access_token=create_access_token(parent_user),
        token_type="bearer",
        user=make_user_response(parent_user),
    )


@router.get("/me", response_model=UserResponse)
async def get_me(
    current_user: Annotated[User, Depends(get_current_user)],
):
    return make_user_response(current_user)


@router.post("/profile", response_model=UserResponse)
@router.put("/profile", response_model=UserResponse)
async def save_profile(
    data: ProfileUpdateRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    if current_user.role not in {"student", "parent"}:
        raise HTTPException(
            status_code=403,
            detail="Use the admin profile endpoint for admin accounts",
        )

    result = await db.execute(
        select(UserProfile).where(
            UserProfile.user_id == current_user.id
        )
    )
    profile = result.scalar_one_or_none()
    profile_data = data.model_dump(exclude_unset=True)

    # Prevent student fields from being submitted as parent profile data,
    # and vice versa.

    student_fields = {
        "education_qualification",
        "marks",
        "favourite_subjects",
        "interests",
        "skills",
        "career_aspirations",
        "location",
        "caste_category",
        "caste_certificate_status",
        "family_considerations",
    }

    parent_fields = {
        "parent_education",
        "parent_occupation",
        "child_name",
        "education_budget",
        "preferred_education_location",
        "parent_concerns",
        "preferred_career_pathways",
        "family_expectations",
    }

    allowed_fields = (
        student_fields
        if current_user.role == "student"
        else parent_fields
    )

    profile_data = {
        key: value
        for key, value in profile_data.items()
        if key in allowed_fields
    }

    allowed_fields = (
        student_fields if current_user.role == "student" else parent_fields
    )
    profile_data = {
        key: value
        for key, value in profile_data.items()
        if key in allowed_fields
    }

    if profile is None:
        profile = UserProfile(
            user_id=current_user.id,
            **profile_data,
        )
        db.add(profile)
    else:
        for field, value in profile_data.items():
            setattr(profile, field, value)

    current_user.profile_completed = True

    await db.commit()
    await db.refresh(current_user)

    return make_user_response(current_user)


@router.post("/admin-profile")
async def save_admin_profile(
    organization_name: Annotated[str, Form()],
    designation: Annotated[str, Form()],
    department: Annotated[str, Form()],
    id_document: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != "admin":
        raise HTTPException(
            status_code=403,
            detail="Only admin accounts can submit this profile",
        )

    

    extension = Path(id_document.filename or "").suffix.lower()

    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=415,
            detail="Upload a PDF, PNG, JPG, or JPEG file",
        )

    content = await id_document.read(MAX_DOCUMENT_SIZE + 1)

    if not content or len(content) > MAX_DOCUMENT_SIZE:
        raise HTTPException(
            status_code=413,
            detail="File must be non-empty and no larger than 5 MB",
        )

    signatures = {
        ".pdf": content.startswith(b"%PDF-"),
        ".png": content.startswith(b"\x89PNG\r\n\x1a\n"),
        ".jpg": content.startswith(b"\xff\xd8\xff"),
        ".jpeg": content.startswith(b"\xff\xd8\xff"),
    }

    if not signatures.get(extension, False):
        raise HTTPException(
            status_code=415,
            detail="File contents do not match the selected file type",
        )

    DOCUMENT_DIR.mkdir(parents=True, exist_ok=True)
    stored_path = DOCUMENT_DIR / (secrets.token_hex(24) + extension)

    try:
        stored_path.write_bytes(content)
    except OSError:
        raise HTTPException(
            status_code=500,
            detail="Unable to store the ID proof securely",
        )

    current_user.organization_name = organization_name.strip()
    current_user.designation = designation.strip()
    current_user.department = department.strip()
    current_user.id_document_path = str(stored_path)
    current_user.admin_status = "approved"
    current_user.profile_completed = True

    await db.commit()
    await db.refresh(current_user)

    return {
    "message": "Admin profile saved successfully",
    "status": current_user.admin_status,
    "profile_completed": current_user.profile_completed,
    "user": make_user_response(current_user).model_dump(mode="json"),
    }


@router.post("/link-child")
async def link_child(
    data: LinkChildRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    if current_user.role != "parent":
        raise HTTPException(
            status_code=403,
            detail="Only parents can link a child",
        )

    result = await db.execute(
        select(User).where(
            User.child_code == data.child_code.strip().upper(),
            User.role == "student",
            User.is_active.is_(True),
        )
    )
    child = result.scalar_one_or_none()

    if not child:
        raise HTTPException(
            status_code=404,
            detail="Student Child Code not found",
        )

    existing = await db.execute(
        select(ParentChildLink).where(
            ParentChildLink.parent_id == current_user.id,
            ParentChildLink.child_id == child.id,
        )
    )

    if existing.scalar_one_or_none():
        return {"message": "This child is already linked"}

    db.add(
        ParentChildLink(
            parent_id=current_user.id,
            child_id=child.id,
        )
    )

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Unable to link child",
        )

    return {
        "message": "Child linked successfully",
        "child_name": child.name,
        "child_code": child.child_code,
    }


@router.get("/my-children")
async def my_children(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    if current_user.role != "parent":
        raise HTTPException(
            status_code=403,
            detail="Only parents can view linked children",
        )

    result = await db.execute(
        select(User)
        .join(ParentChildLink, ParentChildLink.child_id == User.id)
        .where(ParentChildLink.parent_id == current_user.id)
        .order_by(User.name)
    )

    children = result.scalars().all()

    return [
        {
            "id": child.id,
            "name": child.name,
            "child_code": child.child_code,
            "profile_completed": child.profile_completed,
        }
        for child in children
    ]


@router.get("/profile")
async def get_my_profile(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Retrieve the current user's profile information."""
    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == current_user.id)
    )
    profile = result.scalar_one_or_none()

    profile_dict = {}
    if profile:
        profile_dict = {
            c.name: getattr(profile, c.name)
            for c in profile.__table__.columns
            if c.name not in ["id", "user_id"]
        }

    return {
        "user": make_user_response(current_user).model_dump(mode="json"),
        "profile": profile_dict,
    }


@router.get("/child-profile/{child_id}")
async def get_child_profile(
    child_id: int,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Allow a linked parent to view their child's full profile & aspirations."""
    if current_user.role != "parent":
        raise HTTPException(
            status_code=403,
            detail="Only parents can view child profiles",
        )

    link = await db.scalar(
        select(ParentChildLink).where(
            ParentChildLink.parent_id == current_user.id,
            ParentChildLink.child_id == child_id,
        )
    )
    if not link:
        raise HTTPException(
            status_code=404,
            detail="Child is not linked to your account",
        )

    child = await db.scalar(
        select(User).where(User.id == child_id)
    )
    if not child:
        raise HTTPException(
            status_code=404,
            detail="Child user not found",
        )

    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == child_id)
    )
    child_profile = result.scalar_one_or_none()

    profile_dict = {}
    if child_profile:
        profile_dict = {
            c.name: getattr(child_profile, c.name)
            for c in child_profile.__table__.columns
            if c.name not in ["id", "user_id"]
        }

    return {
        "child": {
            "id": child.id,
            "name": child.name,
            "child_code": child.child_code,
            "profile_completed": child.profile_completed,
            "preferred_language": child.preferred_language,
        },
        "profile": profile_dict,
    }


@router.delete("/unlink-child/{child_id}")
async def unlink_child(
    child_id: int,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Allow a parent to unlink a child account."""
    if current_user.role != "parent":
        raise HTTPException(
            status_code=403,
            detail="Only parents can unlink children",
        )

    result = await db.execute(
        select(ParentChildLink).where(
            ParentChildLink.parent_id == current_user.id,
            ParentChildLink.child_id == child_id,
        )
    )
    link = result.scalar_one_or_none()
    if not link:
        raise HTTPException(
            status_code=404,
            detail="Linked child record not found",
        )

    await db.delete(link)
    await db.commit()
    return {"message": "Child unlinked successfully"}

