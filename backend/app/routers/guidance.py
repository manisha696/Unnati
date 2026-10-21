from typing import Optional, List, Annotated
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.routers.auth import get_current_user
from app.models.user import User, ParentChildLink
from app.models.profile import UserProfile

router = APIRouter(prefix="/guidance", tags=["Career Guidance"])

# Curated Vocational Career Catalog with Parent-Appeal & Job Security Metrics
CAREERS_DATA = [
    {
        "id": "electrician",
        "title": "Electrician & Wireman",
        "stream": "Engineering Trades",
        "qualification": "10th Pass",
        "duration": "2 Years (ITI)",
        "salary_range": "₹18,000 - ₹32,000 / mo",
        "job_security_score": 96,
        "job_security_label": "Very High (Govt & Core PSU Demand)",
        "roi_score": 98,
        "earning_age": "Age 18 - 19",
        "apprenticeship_stipend": "₹8,500 - ₹12,000 / month (NAPS Govt Funded)",
        "fee_estimate": "₹1,500 - ₹3,000 / year (100% Fee Waiver on MahaDBT for Reserved Categories)",
        "parent_appeal": "Government-licensed PWD Wireman certification allows permanent jobs in State Electricity Boards (MSEDCL/Mahatransco) or Railway workshops with zero family debt.",
        "parent_highlights": [
            "Starts earning monthly stipend by age 18 without taking education loans",
            "Eligible for permanent government jobs in State Electricity Board & Railways",
            "Option to open an independent electrical shop or service enterprise with Mudra subsidy",
        ],
        "description": "Install, maintain, and repair electrical power, lighting, and industrial machinery systems.",
        "skills": ["Circuit design", "Wiring", "Safety protocols", "Troubleshooting"],
        "pathway": "10th -> ITI Electrician (NCVT) -> National Apprenticeship Certificate (NAC) -> Licensed Wireman / Contractor or Diploma lateral entry",
        "top_employers": ["MSEDCL / State Electricity Boards", "L&T", "Tata Power", "Indian Railways", "Industrial Manufacturing Plants"],
        "growth": "High demand in renewable energy, solar installation, and building automation.",
    },
    {
        "id": "cnc-operator",
        "title": "CNC Machinist & Precision Operator",
        "stream": "Engineering Trades",
        "qualification": "10th Pass / ITI Turner or Machinist",
        "duration": "1 - 2 Years",
        "salary_range": "₹20,000 - ₹38,000 / mo",
        "job_security_score": 94,
        "job_security_label": "High Core Industry Demand",
        "roi_score": 96,
        "earning_age": "Age 18 - 19",
        "apprenticeship_stipend": "₹9,000 - ₹13,000 / month",
        "fee_estimate": "₹2,000 - ₹4,000 / year in Government ITIs",
        "parent_appeal": "CNC machining is the industrial backbone of manufacturing hubs (Pune, Aurangabad, Nashik). High initial starting salary with rapid promotion to shop floor supervisor.",
        "parent_highlights": [
            "Immediate placement in top automobile and defense auto-parts companies",
            "Air-conditioned precision manufacturing environments with strict safety norms",
            "Skilled machine programmers can earn ₹40k+ within 3 years",
        ],
        "description": "Operate computer-controlled machinery and milling equipment to manufacture precision metal and plastic automotive/aerospace components.",
        "skills": ["G-Code / M-Code basics", "Precision measurement (Micrometer, Vernier)", "Blueprint reading", "Tool setup"],
        "pathway": "10th -> ITI Machinist/Turner -> CNC Master Certification -> Production Supervisor",
        "top_employers": ["Automobile OEMs (Bajaj, Mahindra, Tata)", "Aerospace Suppliers", "Defense Factories", "Tool & Die Workshops"],
        "growth": "Crucial backbone of automotive hubs in Pune, Aurangabad, and Nashik.",
    },
    {
        "id": "solar-technician",
        "title": "Solar PV Rooftop Technician",
        "stream": "Green Energy & Tech",
        "qualification": "10th / 12th Pass",
        "duration": "6 Months - 1 Year",
        "salary_range": "₹20,000 - ₹35,000 / mo",
        "job_security_score": 92,
        "job_security_label": "High Growth & Govt Subsidized Sector",
        "roi_score": 95,
        "earning_age": "Age 18 - 19",
        "apprenticeship_stipend": "₹8,000 - ₹11,000 / month",
        "fee_estimate": "Free under Suryamitra Govt Scheme with stipend",
        "parent_appeal": "Massive government backing under PM Surya Ghar Muft Bijli Yojana guarantees high employment and lucrative local self-employment opportunities.",
        "parent_highlights": [
            "Direct beneficiary of Central Government Solar Mission with continuous installation orders",
            "Can work locally near home village or town doing solar maintenance and installations",
            "High entrepreneurial scope: start an authorized solar dealership with government bank support",
        ],
        "description": "Specialized technician for designing, installing, testing, and maintaining rooftop and grid-tied solar photovoltaic systems.",
        "skills": ["Solar panel mounting", "Inverter setup", "AC/DC wiring", "Energy auditing"],
        "pathway": "10th/ITI -> Suryamitra Certification (NISE / NSDC) -> Solar EPC Companies / Entrepreneur",
        "top_employers": ["Tata Power Solar", "Adani Solar", "EPC Contractors", "Rooftop Solar Startups"],
        "growth": "Rapidly expanding industry backed by PM Surya Ghar Muft Bijli Yojana.",
    },
    {
        "id": "ev-technician",
        "title": "Electric Vehicle (EV) Service Specialist",
        "stream": "Automobile & Green Tech",
        "qualification": "10th / 12th Pass / ITI Mechanic",
        "duration": "1 Year",
        "salary_range": "₹22,000 - ₹40,000 / mo",
        "job_security_score": 93,
        "job_security_label": "Future-Proof Automobile Tech",
        "roi_score": 94,
        "earning_age": "Age 19",
        "apprenticeship_stipend": "₹9,500 - ₹14,000 / month",
        "fee_estimate": "₹3,000 - ₹6,000 / year",
        "parent_appeal": "Automotive market is shifting entirely to EVs (2-wheelers and buses). Early certified technicians enjoy rapid promotion and top dealership demand.",
        "parent_highlights": [
            "Modern, clean high-tech workshop environment (no dirty engine grease)",
            "Authorized service center tie-ups (Ola Electric, Ather, Tata Motors)",
            "Specialized skill commands 20-30% premium salary over traditional mechanics",
        ],
        "description": "Inspect, diagnose, and maintain electric and hybrid vehicle battery packs, drivetrains, and charging stations.",
        "skills": ["High-voltage safety", "Battery management systems (BMS)", "Motor diagnostics", "CAN bus diagnostics"],
        "pathway": "10th/ITI Motor Mechanic -> NSDC EV Conversion Certification -> Certified EV Service Specialist",
        "top_employers": ["Ola Electric", "Ather Energy", "Tata Motors EV", "Authorized Dealership Service Centers"],
        "growth": "Fastest-growing vocational trade in automotive transition.",
    },
    {
        "id": "medical-lab-tech",
        "title": "Medical Laboratory Technician (DMLT)",
        "stream": "Healthcare & Paramedical",
        "qualification": "10th / 12th Pass",
        "duration": "1 - 2 Years (Diploma)",
        "salary_range": "₹20,000 - ₹35,000 / mo",
        "job_security_score": 95,
        "job_security_label": "Recession-Proof Essential Service",
        "roi_score": 93,
        "earning_age": "Age 19 - 20",
        "apprenticeship_stipend": "₹8,000 - ₹12,000 / month in hospital labs",
        "fee_estimate": "₹10,000 - ₹20,000 / year (Eligible for MahaDBT scholarships)",
        "parent_appeal": "Hospital and diagnostic clinical work is deeply respected in society, completely recession-proof, and safe for both male and female candidates.",
        "parent_highlights": [
            "Highly respected healthcare role with dignified indoor laboratory work environment",
            "Always in demand in every district hospital, rural health center, and private clinic",
            "Opportunity to run own pathology collection franchise in local area",
        ],
        "description": "Perform clinical laboratory tests on blood, tissue, and bodily fluids to assist doctors in diagnosing diseases.",
        "skills": ["Sample collection", "Microscopy", "Biochemistry analyzers", "Hematology protocols"],
        "pathway": "10th/12th -> DMLT (Diploma in Medical Lab Tech) -> Senior Lab Tech / Diagnostic Center Manager",
        "top_employers": ["District Civil Hospitals", "Thyrocare", "Dr. Lal PathLabs", "Metropolis", "Diagnostic Clinics"],
        "growth": "High stability with self-employment and franchise laboratory opportunities.",
    },
    {
        "id": "gda-healthcare",
        "title": "General Duty Assistant (Nursing Assistant)",
        "stream": "Healthcare & Paramedical",
        "qualification": "10th / 12th Pass",
        "duration": "6 Months - 1 Year",
        "salary_range": "₹16,000 - ₹28,000 / mo",
        "job_security_score": 91,
        "job_security_label": "Evergreen Healthcare Employment",
        "roi_score": 95,
        "earning_age": "Age 18",
        "apprenticeship_stipend": "₹7,500 - ₹10,000 / month",
        "fee_estimate": "Free / Under ₹3,000 under Skill India Mission",
        "parent_appeal": "Short training duration (6-12 months) gets student into hospital employment immediately, with bridge options to GNM nursing later.",
        "parent_highlights": [
            "Quickest route to dignified hospital employment within 6 to 9 months",
            "Safe, supervised hospital environment with free medical coverage",
            "High demand in both government civil hospitals and private healthcare chains",
        ],
        "description": "Provide daily patient care, monitor vital signs, support nursing staff, and assist with hygiene in hospitals and clinics.",
        "skills": ["Vital signs recording", "First aid & CPR", "Patient mobility", "Infection control"],
        "pathway": "10th -> GDA Certification (HSSC / PMKVY) -> Hospital Staff -> GNM Nursing bridge courses",
        "top_employers": ["Government & Municipal Hospitals", "Private Hospital Chains (Apollo, Fortis, Sahyadri)", "Diagnostic Clinics"],
        "growth": "Evergreen demand in hospitals, eldercare facilities, and rural healthcare centers.",
    },
    {
        "id": "copa-computer-operator",
        "title": "Computer Operator & Office Assistant (COPA)",
        "stream": "IT & Digital Services",
        "qualification": "10th Pass",
        "duration": "1 Year (ITI)",
        "salary_range": "₹16,000 - ₹28,000 / mo",
        "job_security_score": 90,
        "job_security_label": "High Govt & Banking Office Demand",
        "roi_score": 96,
        "earning_age": "Age 18",
        "apprenticeship_stipend": "₹7,700 - ₹10,000 / month",
        "fee_estimate": "₹1,500 - ₹3,000 / year in Government ITIs",
        "parent_appeal": "Dignified desk job in clean office setting. Prime qualification required for government Data Entry Operator (DEO) and MahaOnline center jobs.",
        "parent_highlights": [
            "Clean, comfortable desk job suitable for girls and boys",
            "Qualifies for Central & State Government clerical and computer assistant exams",
            "Can establish a local CSC (Common Service Centre) / MahaOnline center near home",
        ],
        "description": "Data entry, office automation, database management, computer hardware setup, and basic Python/web scripting.",
        "skills": ["MS Office / LibreOffice", "Database entry (SQL)", "Operating system setup", "Basic web programming"],
        "pathway": "10th -> ITI COPA -> Data Executive / Government Office DEO / BCA entry",
        "top_employers": ["Govt Departments (MahaOnline, Taluk Offices)", "Banking BPOs", "Schools & Colleges", "IT Service Centers"],
        "growth": "Strong entry point for administrative and clerical positions.",
    },
    {
        "id": "agriculture-drone-operator",
        "title": "Kisan Drone Pilot & Agri-Tech Specialist",
        "stream": "Agriculture & Rural Tech",
        "qualification": "10th Pass",
        "duration": "3 - 6 Months",
        "salary_range": "₹22,000 - ₹45,000 / mo",
        "job_security_score": 89,
        "job_security_label": "High Rural Growth & Govt Subsidized",
        "roi_score": 97,
        "earning_age": "Age 18 - 19",
        "apprenticeship_stipend": "₹8,000 - ₹12,000 / month",
        "fee_estimate": "Heavily subsidized by Drone Shakti Govt Scheme",
        "parent_appeal": "Modernizes agricultural families: student earns ₹800–₹1,500 per acre spraying crops with DGCA license without leaving rural hometown.",
        "parent_highlights": [
            "Allows youth to stay in their home village while earning city-level income",
            "Huge subsidy (up to 75%) available to purchase agricultural drones under government schemes",
            "High respect among local farmer producer organizations (FPOs)",
        ],
        "description": "Operate DGCA-approved agricultural drones for pesticide spraying, crop health monitoring, and soil mapping.",
        "skills": ["DGCA Remote Pilot License", "GPS mapping", "Drone maintenance", "Agricultural spraying regulations"],
        "pathway": "10th -> RPC Remote Pilot Certificate (DGCA certified) -> Custom Hiring Centers (CHC) / Agri-enterprises",
        "top_employers": ["FPO (Farmer Producer Orgs)", "Agri-tech startups", "Krishi Vigyan Kendras (KVK)", "Self-operated drone service"],
        "growth": "Subsidized through Government Drone Shakti scheme with tremendous rural entrepreneurial demand.",
    },
]

# Curated Courses & Institutes
COURSES_DATA = [
    {
        "id": "iti-trades",
        "category": "Industrial Training Institutes (ITI)",
        "title": "Craftsmen Training Scheme (CTS) Trades",
        "eligibility": "10th Pass (Math & Science for Engineering trades; 8th pass for select trades)",
        "duration": "1 to 2 Years",
        "fees": "₹1,500 - ₹8,000 / year (Government ITIs are mostly free/highly subsidized)",
        "admission_process": "Centralized Online Admission via DVET (e.g. admission.dvet.gov.in in Maharashtra) based on 10th merit.",
        "certification": "National Council for Vocational Training (NCVT) / SCVT certificate recognized worldwide.",
        "popular_trades": [
            "Electrician (2 yrs)",
            "Fitter (2 yrs)",
            "Mechanic Motor Vehicle (2 yrs)",
            "Welder (1 yr)",
            "COPA (1 yr)",
            "Machinist (2 yrs)",
        ],
        "benefits": "Direct eligibility for government apprenticeship (NAPS) with monthly stipend, plus lateral entry into 2nd year Polytechnic Diploma.",
    },
    {
        "id": "polytechnic-diploma",
        "category": "Polytechnic Engineering Diplomas",
        "title": "Diploma in Engineering & Technology",
        "eligibility": "10th Pass with min 35% marks (Direct 2nd year entry for 12th Vocational/ITI holders)",
        "duration": "3 Years (2 Years for lateral entry)",
        "fees": "₹6,000 - ₹25,000 / year (Govt) | Scholarships cover fees for reserved categories via MahaDBT/NSP",
        "admission_process": "Centralized Admission Process (CAP) conducted by Directorate of Technical Education (DTE).",
        "certification": "State Board of Technical Education (MSBTE) Diploma, AICTE approved.",
        "popular_trades": [
            "Mechanical Engineering",
            "Electrical Engineering",
            "Computer Engineering / IT",
            "Civil Engineering",
            "Automobile Engineering",
        ],
        "benefits": "Junior Engineer (JE) roles in PWD, Railways, MSEDCL, or direct lateral admission into B.Tech/B.E. 2nd year.",
    },
    {
        "id": "bvoc-degrees",
        "category": "Bachelor of Vocation (B.Voc)",
        "title": "B.Voc UGC Degree Courses",
        "eligibility": "12th Pass (Any Stream) or 10th + 2-yr ITI",
        "duration": "3 Years (with multiple exit options: Certificate after 6 mo, Diploma after 1 yr, Advanced Diploma after 2 yrs)",
        "fees": "₹10,000 - ₹35,000 / year",
        "admission_process": "University direct admission based on 12th merit.",
        "certification": "UGC Recognized University Bachelor's Degree with NSDC Skill Component.",
        "popular_trades": [
            "Automotive Technology",
            "Renewable Energy & Solar Tech",
            "Software Development & Web Design",
            "Retail Management",
            "Medical Lab Technology",
        ],
        "benefits": "Complete graduate degree eligibility for UPSC, MPSC, Banking exams while gaining 60% hands-on industry internship.",
    },
    {
        "id": "pmkvy-short-term",
        "category": "Short-Term Skill Certifications",
        "title": "PMKVY & National Skill Development Corporation (NSDC)",
        "eligibility": "10th / 12th Pass or School Dropouts",
        "duration": "3 to 6 Months (300 to 600 hours)",
        "fees": "100% Free under Government Scheme with reward stipend upon passing assessment",
        "admission_process": "Register via Skill India Digital portal (skillindiadigital.gov.in) at nearest Pradhan Mantri Kaushal Kendra (PMKK).",
        "certification": "National Skills Qualifications Framework (NSQF) Level 3-5 Government Certificate.",
        "popular_trades": [
            "Solar Panel Installation",
            "CNC Operator",
            "Mobile Phone Hardware Repair",
            "General Duty Assistant (Healthcare)",
            "Field Technician (Home Appliances)",
        ],
        "benefits": "Quick wage employment placement support, loan assistance for self-employment (Mudra loan).",
    },
]

# Curated Scholarships Catalog
SCHOLARSHIPS_DATA = [
    {
        "id": "mahadbt-post-matric",
        "title": "MahaDBT Post-Matric Scholarship Scheme",
        "provider": "Government of Maharashtra (Social Justice & Tribal Dev Dept)",
        "target_group": "SC / ST / VJNT / OBC / SBC / EWS students",
        "eligible_courses": "ITI, Polytechnic Diploma, B.Voc, Engineering, Paramedical",
        "benefit": "100% or 50% tuition fee waiver + maintenance allowance (up to ₹12,000/yr)",
        "eligibility": "Family annual income up to ₹2,500,000 (OBC/EWS: up to ₹8,00,000). Domicile of Maharashtra.",
        "deadline": "Usually August - November every academic year (Renewals ongoing)",
        "portal_url": "https://mahadbt.maharashtra.gov.in/",
        "required_docs": ["Caste Certificate", "Income Certificate (Tehsildar)", "10th/12th Marksheet", "Aadhaar Card", "Bank Passbook"],
    },
    {
        "id": "aicte-pragati",
        "title": "AICTE Pragati Scholarship for Girl Students",
        "provider": "Ministry of Education / AICTE",
        "target_group": "Girl students admitted to 1st year or 2nd yr lateral entry of technical Diploma/Degree",
        "eligible_courses": "Polytechnic Engineering Diplomas & Technical Degrees",
        "benefit": "₹50,000 per year for every year of study for college fee, computer, books & equipment",
        "eligibility": "Max 2 girl children per family, family annual income below ₹8,00,000. Admitted through centralized CAP.",
        "deadline": "October - December via National Scholarship Portal (NSP)",
        "portal_url": "https://scholarships.gov.in/",
        "required_docs": ["Income Certificate", "CAP Admission Allotment Letter", "Tuition Fee Receipt", "Aadhaar-seeded Bank Account"],
    },
    {
        "id": "nsp-iti-naps",
        "title": "National Apprenticeship Promotion Scheme (NAPS) Stipend",
        "provider": "Ministry of Skill Development and Entrepreneurship (MSDE)",
        "target_group": "ITI / Diploma graduates undergoing on-the-job apprenticeship",
        "eligible_courses": "All designated ITI and technical trades",
        "benefit": "Monthly stipend ₹7,000 - ₹12,000 per month (Govt reimburses 25% up to ₹1,500/mo directly to apprentice)",
        "eligibility": "Candidate must have passed ITI or Diploma and be aged 14+ years.",
        "deadline": "Open year-round on Apprenticeship India Portal",
        "portal_url": "https://www.apprenticeshipindia.gov.in/",
        "required_docs": ["ITI National Trade Certificate (NTC)", "Aadhaar", "Bank Account Details"],
    },
    {
        "id": "sitaram-jindal",
        "title": "Sitaram Jindal Foundation Scholarship",
        "provider": "Sitaram Jindal Foundation",
        "target_group": "Meritorious students from economically weaker sections",
        "eligible_courses": "ITI (Govt & Private), Diploma, Degree",
        "benefit": "ITI: ₹700/month; Diploma: ₹1,200/month (Girls: ₹1,400/month)",
        "eligibility": "ITI: 45% for boys, 35% for girls. Annual income below ₹4,00,000.",
        "deadline": "Applications accepted throughout the year",
        "portal_url": "https://www.sitaramjindalfoundation.org/",
        "required_docs": ["Marksheet of previous exam", "Income certificate", "Fee receipt"],
    },
    {
        "id": "post-matric-minority",
        "title": "Post-Matric Scholarship for Minorities (NSP)",
        "provider": "Ministry of Minority Affairs",
        "target_group": "Muslim, Christian, Sikh, Buddhist, Jain, Parsi students",
        "eligible_courses": "Class 11, 12, ITI, Diploma, Undergraduate & Postgraduate",
        "benefit": "Admission & tuition fee up to ₹10,000/yr + maintenance allowance up to ₹10,000/yr",
        "eligibility": "Minimum 50% marks in previous examination; family income up to ₹2,00,000.",
        "deadline": "August - November via National Scholarship Portal",
        "portal_url": "https://scholarships.gov.in/",
        "required_docs": ["Minority Community Certificate / Self-Declaration", "Income Certificate", "Marksheet"],
    },
]


class CareerMatchRequest(BaseModel):
    qualification: Optional[str] = None
    interests: Optional[str] = None
    skills: Optional[str] = None
    budget: Optional[str] = None
    preferred_location: Optional[str] = None


@router.get("/careers")
async def get_careers(
    sector: Optional[str] = Query(None, description="Filter by sector/stream"),
    query: Optional[str] = Query(None, description="Search term for title or skills"),
):
    """Retrieve vocational careers catalog with search and sector filtering."""
    results = CAREERS_DATA

    if sector and sector.lower() != "all":
        results = [
            c for c in results
            if sector.lower() in c["stream"].lower()
        ]

    if query and query.strip():
        q = query.strip().lower()
        results = [
            c for c in results
            if q in c["title"].lower()
            or q in c["description"].lower()
            or any(q in s.lower() for s in c.get("skills", []))
            or q in c["stream"].lower()
        ]

    sectors = sorted(list(set(c["stream"] for c in CAREERS_DATA)))
    return {
        "count": len(results),
        "sectors": ["All"] + sectors,
        "careers": results,
    }


@router.get("/careers/{career_id}")
async def get_career_detail(career_id: str):
    """Get complete profile and pathway details for a specific career."""
    career = next((c for c in CAREERS_DATA if c["id"] == career_id), None)
    if not career:
        return {"error": "Career not found", "career": None}
    return {"career": career}


@router.get("/courses")
async def get_courses(
    category: Optional[str] = Query(None, description="Filter by course category"),
):
    """Retrieve curated educational and vocational courses."""
    results = COURSES_DATA
    if category and category.lower() != "all":
        results = [
            c for c in results
            if category.lower() in c["category"].lower()
        ]
    categories = sorted(list(set(c["category"] for c in COURSES_DATA)))
    return {
        "count": len(results),
        "categories": ["All"] + categories,
        "courses": results,
    }


@router.get("/scholarships")
async def get_scholarships(
    target: Optional[str] = Query(None, description="Filter by target group"),
):
    """Retrieve scholarship opportunities with eligibility criteria and application portals."""
    results = SCHOLARSHIPS_DATA
    if target and target.lower() != "all":
        results = [
            s for s in results
            if target.lower() in s["target_group"].lower()
        ]
    return {
        "count": len(results),
        "scholarships": results,
    }


@router.get("/personalized-recommendations")
async def get_personalized_recommendations(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    child_id: Optional[int] = None,
):
    """
    Analyzes the user's stage-2 profile input and generates vocational course recommendations
    specifically highlighted with parent-attracting metrics:
    - Job Security Score
    - Earning Timeline & Stipend
    - ROI Score & Government Fee Waiver
    - Peace of mind points for parents
    """
    target_user_id = current_user.id
    target_student_name = current_user.name

    if current_user.role == "parent":
        if child_id:
            target_user_id = child_id
            c_user = await db.scalar(select(User).where(User.id == child_id))
            if c_user:
                target_student_name = c_user.name
        else:
            first_link = await db.scalar(
                select(ParentChildLink.child_id).where(ParentChildLink.parent_id == current_user.id).limit(1)
            )
            if first_link:
                target_user_id = first_link
                c_user = await db.scalar(select(User).where(User.id == first_link))
                if c_user:
                    target_student_name = c_user.name

    profile = await db.scalar(
        select(UserProfile).where(UserProfile.user_id == target_user_id)
    )

    qual = (profile.education_qualification if profile else "") or ""
    interests = (profile.interests if profile else "") or ""
    skills = (profile.skills if profile else "") or ""
    aspirations = (profile.career_aspirations if profile else "") or ""
    caste = (profile.caste_category if profile else "") or "OPEN"
    budget = (profile.education_budget if profile else "") or ""

    user_text = f"{interests} {skills} {aspirations} {qual}".lower()

    scored = []
    for c in CAREERS_DATA:
        match_score = 50
        reasons = []

        if qual:
            q_lower = qual.lower()
            if "10" in q_lower and "10" in c["qualification"]:
                match_score += 25
                reasons.append("Eligible immediately with your 10th qualification.")
            elif "12" in q_lower:
                match_score += 25
                reasons.append("Eligible with your 12th background.")
            elif "iti" in q_lower or "diploma" in q_lower:
                match_score += 30
                reasons.append("Direct vertical progression for your technical training.")

        # Keywords in skills and description
        keywords = [c["title"].lower(), c["stream"].lower()] + [s.lower() for s in c.get("skills", [])]
        matched = [k for k in keywords if k in user_text]
        if matched:
            match_score += len(matched) * 12
            reasons.append(f"Fits your stated interest in {', '.join(matched[:2])}.")

        # Check domain inclinations
        if any(w in user_text for w in ["electric", "circuit", "wire", "switch"]):
            if c["id"] in ["electrician", "solar-technician", "ev-technician"]:
                match_score += 20
                reasons.append("Matches your hands-on electrical/energy interest.")

        if any(w in user_text for w in ["machine", "motor", "tool", "mechanic", "car", "vehicle"]):
            if c["id"] in ["cnc-operator", "ev-technician"]:
                match_score += 20
                reasons.append("Matches your interest in precision mechanics & vehicles.")

        if any(w in user_text for w in ["hospital", "doctor", "health", "nurse", "patient"]):
            if c["id"] in ["medical-lab-tech", "gda-healthcare"]:
                match_score += 25
                reasons.append("Matches your desire to work in healthcare & patient service.")

        if any(w in user_text for w in ["computer", "code", "software", "typing", "office"]):
            if c["id"] == "copa-computer-operator":
                match_score += 25
                reasons.append("Matches your computer & office technology aspiration.")

        has_fee_waiver = caste.upper() in ["SC", "ST", "OBC", "VJNT", "SBC", "EWS"]
        fee_reason = "100% or 50% Tuition Fee Waiver eligible via MahaDBT" if has_fee_waiver else "Low-cost government subsidized course"

        if not reasons:
            reasons.append("High-demand vocational trade with fast placement and steady income.")

        final_match = min(98, match_score + (c.get("job_security_score", 90) // 15))

        scored.append({
            "career": c,
            "match_percentage": final_match,
            "job_security_score": c.get("job_security_score", 90),
            "job_security_label": c.get("job_security_label", "High Industry Demand"),
            "roi_score": c.get("roi_score", 95),
            "earning_age": c.get("earning_age", "Age 18 - 19"),
            "apprenticeship_stipend": c.get("apprenticeship_stipend", "₹8,500 - ₹12,000 / mo"),
            "fee_estimate": c.get("fee_estimate", "Subsidized Govt ITI"),
            "fee_reason": fee_reason,
            "parent_appeal": c.get("parent_appeal", ""),
            "parent_highlights": c.get("parent_highlights", []),
            "reasons": reasons,
        })

    scored.sort(key=lambda x: (x["match_percentage"] + x["job_security_score"]), reverse=True)

    return {
        "student_name": target_student_name,
        "qualification": qual if qual else "10th / General",
        "caste_category": caste,
        "recommendations": scored[:4],
    }


@router.post("/career-match")
async def match_careers(data: CareerMatchRequest):
    """Match student profile to recommended vocational paths."""
    scored = []
    user_text = f"{data.interests or ''} {data.skills or ''} {data.qualification or ''}".lower()

    for career in CAREERS_DATA:
        score = 0
        reasons = []

        if data.qualification:
            qual = data.qualification.lower()
            if "10th" in qual and "10th" in career["qualification"].lower():
                score += 25
                reasons.append("Matches your 10th pass qualification.")
            elif "12th" in qual:
                score += 30
                reasons.append("Eligible with your 12th background.")
            elif "diploma" in qual or "iti" in qual:
                score += 35
                reasons.append("Directly builds upon your technical background.")

        career_keywords = [
            career["title"].lower(),
            career["stream"].lower(),
        ] + [s.lower() for s in career.get("skills", [])]

        matches = [kw for kw in career_keywords if kw in user_text]
        if matches:
            score += len(matches) * 20
            reasons.append(f"Aligns with your interests: {', '.join(matches[:3])}.")

        if any(w in user_text for w in ["computer", "code", "software", "digital", "data", "it"]):
            if "digital" in career["id"] or "copa" in career["id"]:
                score += 30
                reasons.append("Matches your digital & technology interest.")

        if any(w in user_text for w in ["machine", "electric", "mechanic", "technical", "wiring", "solar"]):
            if any(term in career["id"] for term in ["electrician", "solar", "cnc", "ev", "refrigeration"]):
                score += 30
                reasons.append("Matches your mechanical & electrical inclination.")

        if any(w in user_text for w in ["health", "doctor", "hospital", "patient", "nursing", "biology"]):
            if any(term in career["id"] for term in ["gda", "medical-lab"]):
                score += 35
                reasons.append("Matches your healthcare & service interest.")

        if any(w in user_text for w in ["farm", "drone", "agri", "nature", "rural"]):
            if "drone" in career["id"]:
                score += 35
                reasons.append("Matches your interest in agriculture & drone technology.")

        if not reasons:
            reasons.append("Strong vocational career with practical training and fast employment.")

        score = max(score, 40)
        scored.append({
            "career": career,
            "match_percentage": min(98, score + 15),
            "reasons": reasons,
        })

    scored.sort(key=lambda x: x["match_percentage"], reverse=True)
    return {
        "recommendations": scored[:5],
    }
