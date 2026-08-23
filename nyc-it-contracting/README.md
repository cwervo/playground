# NYC Individual-Contractor IT / SWE Work — Agency Map & Access Routes

Target: solo software engineer / data engineer contracting with **New York City** agencies —
OTI, DSNY (Sanitation), DOE (Education), DOHMH (Health), DCP (City Planning) — plus active
ML / big-data / document-processing teams. Covers both direct-to-city and staffing-agency routes.

Compiled 2026-08-23. **All postings must be re-verified live** — see *Caveats* at the end.

---

## 0. How NYC actually buys one engineer

Most `cityjobs.nyc.gov` listings are civil-service or provisional **employee** lines, not contracts.
Contractor work mostly does not appear there — it appears in the City Record, PASSPort, and in
prime vendors' own pipelines. Four real routes, ranked by realism for a single person:

### Route A — Subcontract under a prime on a city IT master contract  *(highest volume)*
OTI registers **Master Agreement (MA1)** contracts: pre-negotiated terms with a pre-selected
vendor pool that agencies then task-order against. Known primes:

| Prime | Vehicle |
|---|---|
| **SVAM International** | Class 2 Enterprise Task Order Agreement — Citywide Systems Integration Services (modernization, systems integration, app dev, cloud/platform integration) |
| **Compulink Technologies** | Expanded OTI contract, citywide agency services |
| **PruTech Solutions** | $4,800,000 IT development & management consulting, 36 months, 01/01/2025 – 12/31/2027 |

Find the rest yourself: **Checkbook NYC** advanced search filtered by agency + *Prime Vendor*,
plus its **M/WBE and Sub Vendors** dashboards; and **PASSPort Public → Browse Contracts**.

### Route B — NYS OGS **HBITS** *(best single-person route)*
**HBITS** = Hourly Based Information Technology Services, OGS contract award **23158**.
Written so *any* government entity in the state is an "authorized user" without special
permission — **including NYC agencies**, which have their own participation form. OGS's own
guidance to individuals: *contact current HBITS contractors directly for a subcontracting
arrangement.* Resumes go in per-title, per-hour, submitted by the prime on your behalf.

- Primes advertising NYC-area HBITS work: **Trigyn** (extended 5 more years), **V Group**, **IIT Inc**
- Sister vehicle for deliverable-based rather than hourly work: **PBITS** (Project Based IT
  Consulting Services), OGS award **23269**

### Route C — Direct micro / small purchase with the agency
Thresholds current as of the cited rule changes:

- **Micropurchase — $20,000** for goods and all non-construction services: *no competition
  required*. An agency can simply buy your time.
- **Sole source** — non-construction $10K–$20K proceeds without a separate procurement method.
- **M/WBE Noncompetitive Small Purchase — $1.5M** (raised to $1M on 2023-06-03, then $1.5M on
  2023-12-19) for City-certified M/WBE vendors. This is the largest lever available to an
  individual. If you are eligible, certification is the single highest-ROI move on this page.

Prerequisite for all of it: **NYC.ID → PASSPort account**, requested by a principal or authorized
designee of your entity. Sole proprietorship or single-member LLC is fine.

### Route D — Nonprofit fiscal intermediaries that staff city agencies
You are employed/contracted by the nonprofit, embedded with and supervised by the agency.
Frequently converts to a city line later.

- **FPHNYC** (Fund for Public Health in NYC) → DOHMH informatics. Representative posting:
  *Software Developer*, 35 hrs/wk, supporting ELC-grant-funded informatics programs, max
  $135,000/yr, primarily remote, **explicit potential to transition to DOHMH** (NYC residency
  rules then apply).
- **Public Health Solutions** — CAMS unit; long-held DOHMH contracts. Grant-funded roles
  supervised by DOHMH (e.g. one running through November 2027).
- **RFCUNY** (Research Foundation CUNY) — ~150 open roles at a time; the Center for Innovation
  in Mental Health is the academic/evaluation arm of DOHMH's Mental Health Innovation Lab.
- **Fund for the City of New York** — general city-agency project staffing.

---

## 1. Agency by agency

### OTI — Office of Technology and Innovation
1,564 employees, **$869.5M FY2026 budget**. Absorbed DoITT, the Mayor's CTO office, NYC Cyber
Command, MODA / Office of Data Analytics, 311, Open Data, and GIS. Largest surface area by far.

Postings seen in the index:
- **Application Developer** — Brooklyn, posted 02/12/2026, $75,000 – $123,208 (`jid 45592`, also `jid 40601`)
- **Java Developer** — Manhattan (`jid 46041`)
- **Full Stack Developer** — Brooklyn (`jid 41824`)
- **Specialist 3, IAM Consultant** — Citywide Identity and PKI Modernization *(note the title: consultant)*

Contract route: OTI **Vendor Resources** page → MA1 master agreements and Class 2 Enterprise
Task Order Agreements.

**AI / ML:** the NYC **AI Action Plan** (October 2023) — first of its kind in the US — ran 37
actions across 7 initiatives; **31 of 37 complete as of October 2024**. It created an **AI
Steering Committee**, an AI advisory network, and an **Office of Algorithmic Data Integrity**.
Ongoing work is the demand driver here.

**Office of Data Analytics** (ex-MODA, now under OTI):
- **Director of Data Science** — Brooklyn (`jid 42598`), hands-on project direction, runs a team
  of data scientists, works with the City's Chief Analytics Officer
- Hiring contact historically: `MODAjobs@cityhall.nyc.gov`

### DSNY — Department of Sanitation
Two units matter:

- **Bureau of Information Technology (BIT)** — develops and maintains DSNY application software
  "using in-house project resources **and hired consultants**." That phrase is your opening line
  in a cold email.
- **Operations Management Division** — DSNY's data-analytics unit: data maintenance systems and
  analytical products informing operational policy.

Live posting:
- **Data Engineer, DSNY** (Operations Management Division) — `jid 44759`, also LinkedIn
  `4444201271`. Design/build/maintain DBMS, data integration, custom apps. Named stack: SQL with
  complex queries and stored procedures, **OBIEE**, **Power BI**, dashboards and reporting.

Big-data demand driver: the **2026 Draft Solid Waste Management Plan** — curbside
containerization, route optimization, Zero Waste reporting.

### DOE — NYC Public Schools
Runs procurement **separately from the rest of the city**. Do not expect to find this through
PASSPort alone.

- Vendor Portal: `vendorportal.nycenet.edu` (amendments and Q&A are posted here)
- **InfoHub → Open DOE Solicitations**: RFPs *and* **Multiple Task Award Contracts (MTACs)** —
  MTACs are the closest thing DOE has to a staff-augmentation pool
- Contact: `RFPITPROCUREMENT@schools.nyc.gov`
- **DIIT** (Division of Instructional and Information Technology) is the tech org. Its awards
  appear in the **Panel for Educational Policy contracts agenda** PDFs — public, and the best
  early-warning signal for who just won what and will need subs.
- Adjacent: the **School Construction Authority (SCA)** runs its own solicitation for
  **IT Professional Contingent and Temporary Staffing** — a genuine contingent-staffing vehicle.

Posting seen: **Data Analyst Consultant**, Office of Teacher Recruitment and Quality, 65 Court St
Brooklyn, hybrid — note the literal word *Consultant* in the title.

### DOHMH — Health and Mental Hygiene
Tech org sits mostly in Long Island City / Queens.

- **Bureau of Enterprise Technology Business Solutions** — PMO Analysts (`jid 45511`),
  IT Project Manager (`jid 39810`, posted 01/17/2026)
- **Bureau of Application Development and Database Administration** — .NET Developer (`jid 20958`)
- **Bureau of Data Technology & Strategy** — Senior Research Data Scientist (`jid 29552`)
- Analyst – DOHMH (`jid 46295`)

Active procurement:
- Software developer for a **patient scheduling system integrated with the EMR** for the Bureau
  of Public Health Clinic and Bureau of Immunization — **anticipated contract start 07/01/2026**
- **DOHMH ACCO Temporary Staffing Services** master-contractor solicitation — temp personnel to
  assist with agency services
- Recurring pattern in DOHMH informatics postings: documenting integrations, cleaning datasets,
  mapping datasets into schemas, technical assistance to maintain data fidelity

Nonprofit route is unusually strong here — see Route D.
Agency job board: `nyc.gov/site/doh/about/employment/job-search.page`

### DCP — Department of City Planning
- **Information Technology Division → Geographic Data & Engineering** — the team publicly known
  as **NYC Planning Labs**. Stated mission: publish high-quality public datasets, build
  transparent automated pipelines **on open-source technologies**, maintain documentation and
  analytics resources, convene across agencies — and **share the work publicly via talks, blogs,
  and presentations**.
- **Data Engineer** — Manhattan, posted **06/04/2026**, full-time (`jid 44221`)
- **Team Lead of Data Engineering** — Manhattan (`jid 27024`)
- **Associate GIS Specialist** — Manhattan (`jid 26825`)

Culture note: of every team on this page, DCP is the one that hires off a visible open-source
track record. A public GitHub trail of pipeline work is worth more here than a resume.

---

## 2. Document processing / OCR / IDP

The most on-target cluster for anyone with document-AI experience.

- **DOF — Finance Information Technology (FIT): OCR/IDP Developer**, Manhattan, `jid 41964`.
  Digitizing and automating DOF's paper application processes. Named stack: **OpenText
  Intelligent Capture** and **Azure Document Intelligence**. This is the sharpest single match
  in this entire document.
- **HRA / DSS — Paperless Office System (POS)**: **Infopeople Corporation** holds consulting for
  POS and HRA Business Processing, renewal **01/01/2025 – 12/31/2026**. POS is one of the largest
  document-workflow systems in city government, and that end date means a renewal or
  re-solicitation window is imminent.
- **DORIS** (Records and Information Services): sets citywide digitization standards, requires
  agencies to certify image and metadata accuracy, and **procures scanning and digitization
  services**. Maintains an M/WBE page — an explicit small-vendor on-ramp.
- **AI & Bot Developer** — Manhattan, `jid 19411`. AI, chatbot, **OCR**, and RPA; writing APIs
  and extracting data to feed a voice bot / chatbot / virtual assistant.

---

## 3. Other live ML / big-data postings worth tracking

| Role | Where | ID |
|---|---|---|
| Director of AI Solutions | Comptroller's Office, Manhattan | `jid 43874` |
| AI Project Lead | Brooklyn | `jid 44205` |
| Data Engineer, Division Management & Systems Coordination — *"use Machine Learning … for anomaly detection"* | Queens | `jid 42004` |
| Associate Data Engineer — scikit-learn / R | Brooklyn | `jid 40552` |
| Data Engineer — Enterprise Data Science and Engineering Unit (EDSE), IT & Telecom | — | `jid 35926`, `jid 35913` |
| Data Scientist | Brooklyn | `jid 41584` |
| Data Scientist | All boros | `jid 45209` |
| Senior Programmer Analyst | All boros | `jid 12542` |

---

## 4. Do this week, in order

1. **PASSPort account.** NYC.ID first, then request the PASSPort account as principal of your
   entity. Half a day. Nothing else on this page works without it.
2. **Check M/WBE eligibility.** If you qualify, start certification now — $1.5M noncompetitive
   is the difference between "cannot be hired quickly" and "can be hired on a phone call."
3. **Email HBITS primes** — Trigyn, V Group, IIT Inc, plus the full contractor list from OGS
   award 23158. One page: titles you match, hourly rate, NYC authorized-user availability.
4. **Email the NYC-side primes** — SVAM, Compulink, PruTech. Same one-pager, framed against
   their active task orders.
5. **Apply direct to the three sharpest fits:** DOF OCR/IDP Developer (`jid 41964`),
   DSNY Data Engineer (`jid 44759`), DCP Data Engineer (`jid 44221`).
6. **Set standing alerts:** City Record Online (`a856-cityrecord.nyc.gov`) for *IT consulting*,
   *staff augmentation*, *software development*; PASSPort Public → Browse Contracts;
   DOE InfoHub open solicitations; DOHMH ACCO notices.
7. **Checkbook NYC sweep:** pull each target agency's IT prime vendors and their contract values,
   then cold-email the primes with the most headroom on active awards.

---

## 5. Caveats

Sandbox egress blocked direct loads of `nyc.gov`, `cityjobs.nyc.gov`, `data.cityofnewyork.us`,
`a856-cityrecord.nyc.gov`, `databook.nyc`, and `ogs.ny.gov`. Everything here was assembled from
search-index results, not live pages. Consequences:

- **Job IDs and posting dates are as reported by the index. Some are certainly closed.** Re-check
  each on `cityjobs.nyc.gov/job/...-jid-NNNNN` before investing effort.
- Contract values, vendor names, and date ranges are as reported in award notices and press
  releases; confirm current status in Checkbook NYC or PASSPort.
- Procurement thresholds are as of the cited rule amendments (micropurchase $20K;
  M/WBE noncompetitive $1.5M effective 2023-12-19). Verify against current NYC Rules § 3-08
  before relying on a number in a proposal.
- No claim is made that any specific role is open **as an individual contract** rather than a
  civil-service line unless the posting title itself says Consultant.

## Sources

- NYC Jobs portal — https://cityjobs.nyc.gov
- PASSPort Public — https://a0333-passportpublic.nyc.gov/index.html · contracts: https://a0333-passportpublic.nyc.gov/contracts.html
- M/WBE Noncompetitive Small Purchase threshold amendment — https://rules.cityofnewyork.us/rule/amendment-to-mwbe-noncompetitive-small-purchase-mechanism-dollar-threshold/
- NYC Admin Code § 3-08 Small Purchases — https://codelibrary.amlegal.com/codes/newyorkcity/latest/NYCrules/0-0-0-21971
- MOCS legislative and regulatory reforms — https://www.nyc.gov/site/mocs/regulations/legislative-and-regulatory-reforms.page
- M/WBE Small Purchase vendor job aid — https://www.nyc.gov/assets/mocs/downloads/PASSPort/learning-to-use-passport/MWBE_SmallPurchase_VendorJobAid.pdf
- OGS HBITS (award 23158) — https://ogs.ny.gov/procurement/hbits-hourly-based-information-technology-services · https://ogs.ny.gov/contract-award-23158
- OGS HBITS contractor information — https://online.ogs.ny.gov/purchase/snt/awardnotes/7301223158ContractorInfo.pdf
- OGS PBITS (award 23269) — https://ogs.ny.gov/award-23269
- Trigyn HBITS extension — https://www.trigyn.com/trigyns-new-york-state-ogs-hourly-based-it-services-hbits-contract-extended
- SVAM government contracts — https://svam.com/gov-contracts/
- Compulink OTI contract expansion — https://www.businesswire.com/news/home/20241007744326/en/Compulink-Grows-NYC-IT-Contract-to-Better-Serve-City-Agencies
- OTI vendor resources — https://www.nyc.gov/content/oti/pages/vendor-resources
- OTI working at OTI — https://www.nyc.gov/content/oti/pages/working-at-oti
- OTI artificial intelligence — https://www.nyc.gov/content/oti/pages/artificial-intelligence
- AI Action Plan progress report 2024 — https://www.nyc.gov/assets/oti/downloads/pdf/reports/ai-action-plan-progress-report-2024.pdf
- How NYC government is using AI (City & State, July 2026) — https://www.cityandstateny.com/policy/2026/07/how-nyc-government-using-ai/414871/
- Mayor's Office of Data Analytics — https://www.nyc.gov/site/operations/research/mayor-office-of-data-analytics.page
- OTI (agency overview) — https://en.wikipedia.org/wiki/New_York_City_Office_of_Technology_and_Innovation
- DSNY Data Engineer — https://cityjobs.nyc.gov/job/data-engineer-in-nyc-all-boros-jid-44759 · https://www.linkedin.com/jobs/view/data-engineer-at-nyc-department-of-sanitation-dsny-4444201271
- DSNY careers — https://www.nyc.gov/site/dsny/careers/careers.page
- DSNY 2026 Draft Solid Waste Management Plan — https://www.nyc.gov/assets/dsny/downloads/resources/reports/solid-waste-management/2026-swmp/draft-swmp-2026.pdf
- DOE Multiple Task Award Contract solicitations — https://infohub.nyced.org/in-our-schools/working-with-the-doe/contracts-and-purchasing/open-doe-solicitations/Multiple-Task-Award-Contract-Solicitations
- DOE Requests for Proposals — https://infohub.nyced.org/in-our-schools/working-with-the-doe/contracts-and-purchasing/open-doe-solicitations/request-for-proposals
- DOE important vendor topics — https://infohub.nyced.org/in-our-schools/working-with-the-doe/contracts-and-purchasing/important-vendor-topics
- DOE Vendor Portal — https://vendorportal.nycenet.edu/vendorportal/login.aspx
- DOE Data Analyst Consultant — https://datajobs.com/NYC-Department-of-Education/Data-Analyst-Consultant-Job~103985
- DOHMH job search — https://www.nyc.gov/site/doh/about/employment/job-search.page
- DOHMH temporary staffing solicitation — https://www.nyc.gov/assets/doh/downloads/pdf/acco/2025/notice-of-solicitation-temporary-staffing-services.pdf
- DOHMH master contractor solicitation — https://www.nyc.gov/assets/doh/downloads/pdf/acco/2024/master-contractor-notice-of-solicitation.pdf
- FPHNYC Software Developer — https://www.linkedin.com/jobs/view/software-developer-at-fund-for-public-health-in-nyc-3178557428
- Public Health Solutions careers — https://www.builtinnyc.com/company/public-health-solutions/jobs
- RFCUNY careers — https://www.rfcuny.org/careers/ · https://rfcuny.wd108.myworkdayjobs.com/RFCUNY
- DCP Data Engineer — https://cityjobs.nyc.gov/job/data-engineer-in-manhattan-jid-44221
- DCP Team Lead of Data Engineering — https://cityjobs.nyc.gov/job/team-lead-of-data-engineering-in-manhattan-jid-27024
- DCP Associate GIS Specialist — https://cityjobs.nyc.gov/job/associate-gis-specialist-in-manhattan-jid-26825
- DOF OCR/IDP Developer — https://cityjobs.nyc.gov/job/ocr-idp-developer-in-manhattan-jid-41964
- AI & Bot Developer — https://cityjobs.nyc.gov/job/ai-and-bot-developer-in-manhattan-jid-19411
- Director of AI Solutions — https://cityjobs.nyc.gov/job/director-of-ai-solutions-in-manhattan-jid-43874
- AI Project Lead — https://cityjobs.nyc.gov/job/ai-project-lead-in-brooklyn-jid-44205
- Director of Data Science — https://cityjobs.nyc.gov/job/director-of-data-science-in-brooklyn-jid-42598
- Senior Research Data Scientist, Bureau of Data Technology & Strategy — https://cityjobs.nyc.gov/job/senior-research-data-scientist-bureau-of-data-technology-and-strategy-in-queens-jid-29552
- DORIS digitization guide — https://www.nyc.gov/assets/records/pdf/Digitization%20Guide%20for%20Records%20with%20Long%20Term%20Retention%20at%20NYC%20Agencies%2020161031.pdf
- DORIS M/WBE — https://www.nyc.gov/site/records/about/minority-and-women-owned-business-enterprises.page
- Checkbook NYC — https://www.checkbooknyc.com/ · overview: https://www.checkbooknyc.com/contracts-application-overview/newwindow
- City Record Online — https://a856-cityrecord.nyc.gov
- Comptroller contract primer — https://comptroller.nyc.gov/reports/contract-primer/
