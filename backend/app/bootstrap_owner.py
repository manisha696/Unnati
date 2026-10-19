
import asyncio
import getpass

from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from pwdlib import PasswordHash

from app.database import AsyncSessionLocal
from app.models.user import User


password_hasher = PasswordHash.recommended()


async def create_owner():
    print("\n=== Unnati Owner Account Setup ===\n")

    async with AsyncSessionLocal() as db:
        existing_owner = await db.scalar(
            select(User.id).where(User.is_owner.is_(True)).limit(1)
        )

        if existing_owner is not None:
            print("An Owner account already exists. Setup cancelled.")
            return

        name = input("Owner name: ").strip()
        email = input("Owner email: ").strip().lower()
        phone = input("Owner mobile (10 digits): ").strip()

        if not name or not email:
            print("Name and email are required.")
            return

        if not phone.isdigit() or len(phone) != 10:
            print("Enter a valid 10-digit mobile number.")
            return

        password = getpass.getpass("Create Owner password (min 12 characters): ")
        confirm_password = getpass.getpass("Confirm Owner password: ")

        if len(password) < 12:
            print("Password must contain at least 12 characters.")
            return

        if password != confirm_password:
            print("Passwords do not match.")
            return

        existing_user = await db.scalar(
            select(User.id).where(
                (func.lower(User.email) == email)
                | (User.phone == phone)
            ).limit(1)
        )

        if existing_user is not None:
            print("This email or phone is already registered.")
            return

        owner = User(
            name=name,
            email=email,
            phone=phone,
            password_hash=password_hasher.hash(password),
            role="owner",
            is_owner=True,
            is_active=True,
            admin_status="approved",
            preferred_language="English",
            consent_given=False,
        )

        db.add(owner)

        try:
            await db.commit()
        except IntegrityError:
            await db.rollback()
            print("Account could not be created because the email or phone is already used.")
            return

        print("\nOwner account created successfully.")
        print("You can now log in using your email or mobile number.")
        print("Keep your password private.")


if __name__ == "__main__":
    asyncio.run(create_owner())
