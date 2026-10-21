# Unnati Career Guidance Platform

> **Informed career decisions, vocational trades, ITI pathways, and scholarships for students and families.**

---

## 🏗️ Architecture & Project Structure

The project structure is organized into a clean **FastAPI Backend** and a **Flutter Web/Mobile Frontend**:

```text
Unnati/
├── backend/
│   ├── app/
│   │   ├── models/         # SQLAlchemy DB models (User, ParentChildLink, UserProfile)
│   │   ├── routers/        # API routers:
│   │   │   ├── auth.py     # Auth, profile, linking child, child profile inspection
│   │   │   ├── admin.py    # Admin stats dashboard, review queue, user management
│   │   │   └── guidance.py # Vocational careers, courses/ITIs, scholarships, career matcher
│   │   ├── schemas/        # Pydantic validation schemas
│   │   ├── database.py     # Async SQLAlchemy engine with Neon PostgreSQL
│   │   ├── bootstrap_owner.py # Owner bootstrap utility
│   │   └── main.py         # FastAPI application entry point, CORS & health check
│   ├── .env                # Environment variables (Neon DB, JWT Secret, CORS)
│   ├── .env.example        # Reference environment template
│   ├── requirements.txt    # Python dependencies (UTF-8)
│   ├── Dockerfile          # Production Dockerfile
│   └── Procfile            # Deployment configuration for Render / Railway / Heroku
│
├── frontend/
│   ├── lib/
│   │   └── main.dart       # Complete Flutter frontend with interactive dashboards
│   ├── web/                # Flutter web assets, index.html, icons
│   ├── pubspec.yaml        # Flutter dependencies
│   ├── Dockerfile          # Multi-stage Docker build for Flutter Web
│   └── nginx.conf          # NGINX configuration for serving web build
│
├── docker-compose.yml      # 1-command local & server deployment
└── README.md
```

---

## 🌟 Interactive Features Implemented

### 1. Student Features
- **Explore Careers:** Searchable & filterable directory of vocational careers (Electrician, Solar PV Technician, CNC Machinist, EV Service Tech, Healthcare Assistant, Drone Pilot, COPA, etc.) with entry requirements, progression pathways, salaries, and top employers.
- **Career Matcher Quiz:** Interactive quiz matching student qualification and interests to recommended vocational trades with percentage match and reasons.
- **Courses & ITIs:** Comprehensive guide on ITI Craftsmen Training Scheme (CTS), Polytechnic Engineering Diplomas, B.Voc Degrees, and short-term NSDC/PMKVY certifications with admission timelines and fee structures.
- **Scholarships Directory:** Curated opportunities (MahaDBT Post-Matric, AICTE Pragati for Girls, NAPS Apprenticeship Stipend, Minority Scholarships) with eligibility criteria and direct links to official application portals.
- **Unique Child Code:** Automatic generation and 1-click copy of Child Code (`CH-XXXX`) to share with parents.

### 2. Parent Features
- **Link Child Account:** Enter the student's Child Code to instantly link their account.
- **Real-Time Career Progress:** Inspect your linked child's selected trade, qualification, strengths, aspirations, and family preferences.
- **Parent Career Advice:** Tailored advice on vocational vs degree investment, government subsidies, and apprenticeship stipends.
- **Education Options & Budget Guide:** Realistic ROI comparison between ITI, Polytechnic, and degree routes for family financial planning.

### 3. Administrator & Owner Features
- **Platform Analytics Dashboard:** Real-time KPI metrics (Total Users, Students, Parents, Administrators, Pending Applications) and user distribution by preferred language (English, Marathi, Hindi).
- **Admin Review Queue:** Review submitted admin applications with organization name, designation, department, and private verification IDs. 1-click Approve or Reject with reason.
- **User Management:** Searchable platform user directory with role filters and account activation/deactivation toggles.

### 4. 24/7 AI Vocational Counsellor
- Floating bar present across all screens linking directly to the live AI Counsellor Chatbot (`https://counselor-chatbot-two.vercel.app/`).

---

## 🚀 Running Locally

### Option 1: Run with Python & Flutter directly

1. **Start the FastAPI Backend:**
   ```powershell
   cd backend
   python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```
   - API running at: `http://localhost:8000`
   - Swagger Documentation: `http://localhost:8000/docs`

2. **Start the Flutter Web Frontend:**
   ```powershell
   cd frontend
   flutter run -d chrome --web-port 3000
   ```
   - Web application opens automatically at: `http://localhost:3000`

---

### Option 2: Run with Docker Compose

Run the entire stack with a single command:
```bash
docker compose up --build
```
- Frontend available at: `http://localhost:3000`
- Backend API available at: `http://localhost:8000`

---

## 🌐 Hosting Guide

### 1. Hosting the Backend (FastAPI)
You can deploy the backend to **Render**, **Railway**, or **Fly.io** in under 5 minutes:

#### On Render (Recommended & Free):
1. Create a new **Web Service** on [Render.com](https://render.com).
2. Connect your repository and select the `backend` directory as the root.
3. Configure settings:
   - **Environment:** `Python 3`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
4. Add Environment Variables:
   - `DATABASE_URL`: `postgresql://neondb_owner:npg_5empdbgB0lYt@ep-patient-salad-az4zbw39-pooler.c-3.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require`
   - `JWT_SECRET_KEY`: `your_secure_jwt_secret_key`
   - `CORS_ORIGINS`: `*` (or your frontend domain, e.g. `https://your-app.vercel.app`)
5. Deploy! Your backend will be live at `https://your-service.onrender.com`.

---

### 2. Hosting the Frontend (Flutter Web)
You can host the compiled web build on **Vercel**, **Firebase Hosting**, or **Netlify**:

#### Building the Web Release:
```powershell
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://your-backend-service.onrender.com
```
The production bundle is generated in `frontend/build/web`.

#### On Vercel:
1. In `frontend`, deploy the `build/web` directory:
   ```bash
   vercel deploy build/web --prod
   ```
   Or connect your GitHub repository and set the Output Directory to `build/web`.

#### On Firebase Hosting:
1. `firebase init hosting` (set public directory to `build/web`, configure as single-page app: `Yes`).
2. `firebase deploy --only hosting`.
