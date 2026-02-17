# Civic Pulse: Comprehensive Data Sources Catalog

**Purpose:** This document catalogs every government and academic data source identified for powering Civic Pulse’s community information features. It covers federal agencies, Georgia state agencies, public university research centers, and environmental/health screening tools. Each source is described with its coverage, access method, geographic granularity, update frequency, and specific application to Civic Pulse’s mission of providing apolitical, factual community data to voters and candidates.

**Design principle:** Present raw data and trends without editorial framing. Let the numbers speak. Always cite the source agency and methodology. Never characterize data as “good” or “bad” — present it in context (historical trend, state/national comparison) and let voters draw their own conclusions.

**Organization:** Sources are grouped by domain (economic, public safety, education, health, environmental, fiscal transparency, and infrastructure). Within each domain, federal sources appear first, followed by Georgia-specific sources that provide more granular or more timely data for the state. The final sections cover cross-cutting tools, integration architecture, and presentation guidelines.

-----

## 1. Economic Data

Economic conditions are among the most universally relevant community indicators for local races. Voters care about jobs, income, housing costs, and whether their community is growing or declining. The sources below range from highly granular Census data updated annually to monthly unemployment figures that capture economic momentum.

### 1.1 U.S. Census Bureau — American Community Survey (ACS)

The ACS is the single richest source of local socioeconomic data in the United States. It provides annual estimates of income, poverty, employment, housing costs, health insurance coverage, educational attainment, commute times, and demographic composition. The 5-year estimates (ACS 5-Year) are available down to the census tract and block group level, making them suitable for city council and school board districts.

**Key variables for Civic Pulse:** Median household income, poverty rate (percentage of population below poverty level), unemployment rate (civilian labor force), median home value and median gross rent, housing cost burden (percentage of households spending 30%+ of income on housing), health insurance coverage rate, educational attainment distribution (high school, bachelor’s, graduate), and population change over time.

**API access:** Free REST API at `api.census.gov`. Requires a free API key (obtained at api.census.gov/data/key_signup). Returns JSON. Supports geographic filtering by state, county, place (city), tract, and block group using FIPS codes. The TIGERweb GeoServices REST API provides boundary shapefiles for mapping. Rate limit is 500 queries/day without a key, unlimited with a key.

**Geographic granularity:** Block group (smallest), census tract, place (city/town), county, state, nation. The 5-year estimates cover all geographies; 1-year estimates are only available for areas with 65,000+ population.

**Update frequency:** Annual release, typically in September/December. 5-year estimates have a 1-year lag (e.g., 2019-2023 data released in late 2024).

**Civic Pulse application:** ACS data forms the foundation of the community economic snapshot. The Census Geocoding API can translate any voter address to FIPS codes, enabling a “look up my neighborhood” feature that maps directly to cached ACS data. For small-area estimates (tracts, block groups), the margin of error should always be displayed to prevent voters from over-interpreting small differences. The `censusapi` R package and various Python wrappers (e.g., `census`, `cenpy`) simplify API calls.

**URL:** https://www.census.gov/data/developers/data-sets.html

-----

### 1.2 Bureau of Labor Statistics (BLS) — Local Area Unemployment Statistics (LAUS)

LAUS provides monthly and annual employment, unemployment, and labor force estimates for states, counties, metropolitan areas, and many cities. This is the authoritative source for local unemployment rates and is updated far more frequently than the ACS, making it the best indicator of current economic momentum.

**Key variables for Civic Pulse:** Unemployment rate (monthly, by county and metro area), labor force size, number of employed and unemployed persons, and year-over-year and month-over-month changes.

**API access:** Free REST API at `api.bls.gov/publicAPI/v2/timeseries/data/`. Requires a free registration key for Version 2 (higher rate limits: 500 queries/day, up to 50 series per query, 20 years of data per query). Series IDs follow a structured format — for LAUS, the prefix is `LAUS` followed by area codes. Returns JSON.

**Geographic granularity:** State (seasonally adjusted), county, metropolitan statistical area, and some cities (not seasonally adjusted at sub-state level). Sub-state data is not seasonally adjusted, which means raw month-to-month comparisons can be misleading due to seasonal hiring patterns. For voter-facing displays, year-over-year comparisons are more appropriate than month-over-month at the local level.

**Update frequency:** Monthly, with approximately a 2-month lag. State data released first, followed by metro/county data about two weeks later.

**Civic Pulse application:** BLS LAUS is the most current economic indicator available at the county level. Displaying a 12-month or 24-month unemployment trend line gives voters a clear sense of economic direction. BLS also provides the Quarterly Census of Employment and Wages (QCEW) with employment and wage data by industry at the county level, which could support a “what industries employ people here” view. The Consumer Price Index (CPI) is available at the metro level for major cities and could show local inflation trends.

**URL:** https://www.bls.gov/lau/ (data), https://www.bls.gov/developers/ (API)

-----

### 1.3 Federal Reserve Economic Data (FRED) — St. Louis Fed

FRED aggregates over 800,000 time series from dozens of government sources into a single, well-documented API. For local data, it includes county-level poverty rates, unemployment, income, housing price indices, and population. FRED’s strength is making it easy to access data that originates from the Census Bureau, BLS, FHFA, BEA, and other agencies through a single consistent interface.

**Key variables for Civic Pulse:** County-level poverty rate (from ACS, via FRED), county-level unemployment rate (from BLS LAUS, via FRED), House Price Index by county (from FHFA, via FRED), per capita personal income by county (from BEA, via FRED), population estimates (from Census, via FRED), and burdened households and single-parent household rates.

**API access:** Free REST API at `api.stlouisfed.org/fred/`. Requires a free API key. Returns JSON or XML. Series can be searched by tag (e.g., `county`, `poverty`, `housing`). Supports date range filtering and frequency aggregation. Over 330,000 county-tagged series provide substantial local coverage.

**Geographic granularity:** Varies by series. County-level data is available for poverty, unemployment, income, and housing prices. Metro-level data is available for a broader set of indicators. City-level data is limited.

**Civic Pulse application:** FRED is an excellent “convenience layer” — rather than querying multiple agency APIs directly, Civic Pulse can pull most economic indicators from FRED with a consistent format. For the MVP, FRED could serve as the primary economic data backend, supplemented by direct Census API calls for ACS detail not available in FRED.

**URL:** https://fred.stlouisfed.org/ (browse), https://fred.stlouisfed.org/docs/api/fred/ (API documentation)

-----

### 1.4 Bureau of Economic Analysis (BEA) — Regional Economic Accounts

BEA produces GDP, personal income, and employment data by county, metro area, and state. It provides the official GDP estimates for the United States and the most granular income data available outside the Census.

**Key variables for Civic Pulse:** Per capita personal income by county (annual), total personal income and its components (wages, transfers, investment income), real GDP by metropolitan statistical area, and regional price parities (cost of living adjustment by metro area).

**API access:** Free REST API at `apps.bea.gov/api/`. Requires a free API key. Returns JSON or XML.

**Geographic granularity:** County (income and employment), metropolitan area (GDP), state.

**Update frequency:** Annual, with approximately a 1-year lag for county data.

**Civic Pulse application:** The Regional Price Parities (RPPs) are particularly valuable for context — they show whether local incomes go further or not compared to the national average. A voter in a county with $55,000 median income and a low cost of living is in a very different situation than one in a county with $55,000 income and a high cost of living. Presenting income alongside RPPs avoids misleading comparisons.

**URL:** https://www.bea.gov/data/by-place-county-metro-local

-----

### 1.5 USDA Economic Research Service (ERS) — County-Level Data Sets

The ERS aggregates county-level data on poverty, population change, unemployment, educational attainment, and rural-urban classifications. While it draws from Census and BLS data, it adds rural/urban context and economic typologies that are useful for understanding local conditions.

**Key variables for Civic Pulse:** County economic typology (farming, mining, manufacturing, government, recreation, nonspecialized), persistent poverty counties (20%+ poverty rate for 30+ years), population change and net migration, and rural-urban continuum codes.

**Access:** Downloadable Excel/CSV files only; no API. Files are updated annually.

**Civic Pulse application:** The economic typology classifications are a concise way to describe a community’s economic character. The persistent poverty designation is a powerful contextual indicator. These are static classifications that could be bundled with the application data rather than queried dynamically.

**URL:** https://www.ers.usda.gov/data-products/county-level-data-sets/

-----

### 1.6 Census Bureau — Population Estimates Program

Population change is one of the most fundamental indicators of a community’s trajectory. The Census Bureau provides annual population estimates at the county, city, and metro level between decennial censuses, including components of change (births, deaths, domestic migration, international migration).

**Civic Pulse application:** Whether a community is growing or shrinking affects every policy area — school capacity, infrastructure investment, tax revenue, housing demand. A simple population trend chart with migration components tells a story that applies to every local race.

**URL:** https://www.census.gov/programs-surveys/popest.html

-----

### 1.7 Georgia Department of Labor — Labor Market Explorer

The Georgia DOL’s Workforce Statistics and Economic Research (WS&ER) division produces labor market data for all 159 Georgia counties through the Georgia Labor Market Explorer, working in cooperation with the federal BLS to produce Georgia-specific estimates.

**What it covers:** Monthly civilian labor force estimates (labor force, employed, unemployed, unemployment rate) for every county, MSA, city over 10,000 population, and Regional Commission area. Unemployment insurance initial claims by county and MSA (monthly, with previous month and previous year comparisons). Quarterly Census of Employment and Wages (QCEW) showing establishment counts, employment, and wages by industry at the county level. Occupational wage data statewide and by local area. Area Labor Profiles for each of Georgia’s 159 counties, providing a comprehensive summary of industry mix, income, and occupational profiles. Short- and long-term employment and industry projections by local workforce area.

**Access:** The Georgia Labor Market Explorer (explorer.gdol.ga.gov) provides interactive data retrieval. Area Labor Profiles are downloadable PDFs. Monthly publications are posted on a regular schedule. No API, but data can be downloaded from the Explorer tool.

**Civic Pulse application:** The Area Labor Profiles are a ready-made community economic snapshot for every county in Georgia. They combine data from multiple sources (BLS, Census, DOL internal data) into a single narrative document. For local races where economic development is an issue, these profiles provide the factual foundation voters need. The monthly UI claims data is also one of the most current economic indicators available at the county level — more current than BLS LAUS, which has a longer processing lag.

**URLs:** https://dol.georgia.gov/get-labor-market-information (overview), https://explorer.gdol.ga.gov/ (Labor Market Explorer)

-----

### 1.8 GeorgiaData.org — Carl Vinson Institute of Government, University of Georgia

GeorgiaData.org is the single most valuable Georgia-specific data aggregator for Civic Pulse’s purposes. Maintained by UGA’s Carl Vinson Institute of Government (CVIOG), it consolidates county-level data from dozens of public sources into a single, consistently organized repository. It is the digital successor to the Georgia County Guide, which has served planners and policymakers for over 30 years.

**What it covers:** County-level data organized across topic areas including agriculture, courts and crime (GBI crime data, state prison incarceration, felony probation), economics (median household income, personal income per capita, poverty rate, sales tax distributions by jurisdiction and over time), education (educational attainment, K-12 enrollment), health (percent uninsured), housing (homeownership rate, rental vacancy rate), labor (county business patterns, labor force participation, occupation projections, unemployment rate, UI claims weekly snapshots), population, public assistance (SNAP, TANF), and vital statistics (births, deaths).

**Access:** Data is browsable through interactive maps and visualizations, with Excel download available for most datasets. There is no public API, so data would need to be periodically downloaded in batch. The site is publicly accessible with no login required.

**Civic Pulse application:** GeorgiaData.org has already done the hard work of normalizing and organizing county-level data from disparate state and federal sources into a consistent format. For a Georgia-focused launch, it effectively functions as a pre-built data warehouse. Rather than integrating with a dozen separate agencies, Civic Pulse can treat GeorgiaData as a primary aggregation layer for Georgia counties and supplement with direct agency data where greater granularity or timeliness is needed. The site’s own data visualization approach — designed for “helping communities make informed decisions” — provides a model for apolitical data presentation.

**URL:** https://georgiadata.org/

-----

## 2. Public Safety and Criminal Justice Data

Crime data is among the most sensitive categories for apolitical presentation. The FBI explicitly warns against using UCR data to rank jurisdictions, and incomplete reporting makes some comparisons misleading. Civic Pulse should present crime trends over time with clear source attribution and reporting coverage caveats, never as isolated snapshots or rankings.

### 2.1 FBI Crime Data Explorer — Uniform Crime Reporting (UCR) Program

Crime statistics reported by over 18,000 local law enforcement agencies across the United States. Data is available in two formats: the legacy Summary Reporting System (SRS) providing aggregate offense counts, and the National Incident-Based Reporting System (NIBRS) providing detailed incident-level data including offense type, victim/offender demographics, weapons, and location.

**Key variables for Civic Pulse:** Violent crime rates (homicide, assault, robbery, rape) by agency, property crime rates (burglary, larceny, motor vehicle theft) by agency, arson data, hate crime statistics by state and year, law enforcement employee counts (officers and civilians) by agency, and clearance rates (percentage of crimes solved).

**API access:** Free REST API at `api.usa.gov/crime/fbi/sapi/`. Requires a free data.gov API key. Returns JSON or CSV. Queries by agency ORI (Originating Agency Identifier), state, or national level. Supports multi-year queries. The API codebase is open source on GitHub (fbi-cde/crime-data-api), built with Python Flask and SQLAlchemy on PostgreSQL — notably similar to Civic Pulse’s own stack.

**Geographic granularity:** Individual law enforcement agency (which roughly maps to city or county jurisdiction). Not every agency reports consistently, so coverage gaps exist.

**Update frequency:** Quarterly releases on the Crime Data Explorer. Full annual data typically available by fall of the following year.

**Civic Pulse application:** The biggest challenge with UCR data is incomplete reporting — not all agencies report every year, and the transition from SRS to NIBRS has caused temporary data gaps in some jurisdictions. For voter-facing display, it’s essential to show data availability clearly (e.g., “Reported by [Agency Name], covering years 20XX-20XX”) and to avoid displaying data for agencies with incomplete reporting years without clear caveats. Trend lines are more informative than single-year snapshots. The FBI’s warning against ranking jurisdictions should be respected — show each community’s trend and its comparison to state/national averages, not league tables.

**URL:** https://cde.ucr.cjis.gov/ (explorer), https://github.com/fbi-cde/crime-data-api (API source)

-----

### 2.2 Bureau of Justice Statistics (BJS) — Data Analysis Tools

BJS produces secondary analyses and tools built on top of UCR data and its own surveys. The most relevant for local context are the Justice Expenditure and Employment Tool (JEET), which shows how state and local governments allocate resources across police, courts, and corrections, and the Law Enforcement Agency Reported Crime Analysis Tool (LEARCAT), which enables examination of NIBRS data for full-reporting states and large agencies.

**Key variables for Civic Pulse:** Per capita justice expenditures by state and large city/county (police, judicial, corrections), justice system employment per 10,000 residents, detailed NIBRS crime analysis for reporting agencies, and parole and probation population trends by state.

**API access:** BJS provides a SODA API (Socrata Open Data API) for the NIBRS National Estimates and the National Crime Victimization Survey (NCVS). The JEET and LEARCAT are interactive web tools without a public API, but underlying data can be downloaded.

**Geographic granularity:** State-level for expenditure data. Agency-level for LEARCAT. National for NCVS.

**Civic Pulse application:** The expenditure data is particularly useful for school board and county commission races, where justice spending is a direct budget decision. Presenting per capita spending trends over time helps voters understand local resource allocation priorities without editorializing.

**URL:** https://bjs.ojp.gov/data/data-analysis-tools

-----

### 2.3 Georgia Bureau of Investigation (GBI) — Uniform Crime Reporting Program

Georgia’s UCR program, administered by the GBI through the Georgia Crime Information Center (GCIC), collects crime data from all law enforcement agencies operating in the state — sheriffs’ offices, city police departments, campus police, and other designated agencies. GBI received NIBRS certification from the FBI in June 2018 and transitioned to full NIBRS reporting in October 2019.

**What it covers:** Annual summary reports include county-level index crime data (murder, rape, robbery, aggravated assault, burglary, larceny-theft, motor vehicle theft, arson, and human trafficking), broken down by Metropolitan Statistical Area and non-metropolitan counties. Reports also include profiles of persons arrested by age, sex, and race; juvenile arrest data and dispositions; law enforcement personnel counts; family violence incidents (mandated reporting since 1995); and officers killed or assaulted. Five-year trend data is included in each annual report.

**Geographic granularity:** County level (compiled from all agencies operating within that county). Individual agency data is also available upon request via ucrweb@gbi.ga.gov.

**Access:** Annual summary reports are downloadable as PDFs from the GBI website. The GBI Crime Statistics Database provides an interactive query tool. There is no public API — data would need to be extracted from PDFs or the interactive tool, or obtained from GeorgiaData.org’s normalized version.

**Civic Pulse application:** The GBI data is the authoritative Georgia-specific crime data source. While the FBI Crime Data Explorer includes Georgia agencies, the GBI reports are published faster, include Georgia-specific context (family violence data, which is mandated reporting in Georgia), and are presented in county-level aggregations that map cleanly to local government jurisdictions. GeorgiaData.org already integrates GBI crime data into its county-level views and helpfully provides “average months reported” alongside the crime data, which Civic Pulse should display as a data quality indicator.

**URL:** https://gbi.georgia.gov/services/crime-statistics

-----

### 2.4 Georgia Juvenile Justice Data Clearinghouse

County-level juvenile justice reports produced by the Juvenile Data Integrity Stakeholders Work Group, drawing from multiple state agencies. Relevant for communities concerned about youth crime and intervention programs. Available at GeorgiaData.org under the Courts and Crime topic.

-----

### 2.5 State and Local Open Data Portals

Many states, counties, and cities maintain their own open data portals with crime data that is more granular and more current than FBI UCR data, often including incident-level records updated daily or weekly with specific location data. Many of these portals run on Socrata (data.gov platform) or CKAN, which provide standardized APIs. In Georgia, Fulton County maintains a Socrata-based portal at data.fultoncountyga.gov, and the City of Atlanta operates a GIS-based Open Data Hub. A practical approach for Civic Pulse would be to maintain a registry of known local portals and their API endpoints, starting with the jurisdictions where early users are located.

**URL:** https://catalog.data.gov/dataset?tags=crime

-----

## 3. Education Data

Education data is central to school board races and relevant to virtually every local campaign, since school quality affects property values, family decisions, and community identity. The sources below provide everything from national benchmarks to individual school report cards. In Georgia, the state-specific sources (GOSA and GaDOE) are substantially richer than the federal equivalents.

### 3.1 National Center for Education Statistics (NCES) — Common Core of Data (CCD)

CCD is the Department of Education’s primary database on public elementary and secondary education. It provides annual data on every public school and school district (Local Education Agency) in the United States, covering enrollment, staffing, demographics, and finances.

**Key variables for Civic Pulse:** Total enrollment by school and district, student-teacher ratio, per-pupil expenditure (current spending), revenue sources (federal, state, local) and total revenue, free/reduced lunch eligibility (proxy for student poverty), graduation rates and dropout rates, demographic composition of student body, and school locale classification (urban, suburban, town, rural).

**API access:** NCES provides data through the EDGE (Education Demographic and Geographic Estimates) Open Data platform at data-nces.opendata.arcgis.com, which uses ArcGIS REST APIs. The CCD Data File Tool provides downloadable flat files. The ElSi (Elementary/Secondary Information System) tool allows custom table generation. EDGE also provides school district boundary shapefiles, which can map voter addresses to districts.

**Geographic granularity:** Individual school and school district (LEA). EDGE also provides school attendance zone boundaries where available, directly relevant for school board elections.

**Update frequency:** Annual, with approximately a 1-2 year lag. Financial data has a longer lag than enrollment data.

**Civic Pulse application:** For school board races, CCD data is essential. The ability to show a school district’s enrollment trends, spending per pupil compared to the state average, and graduation rates over time provides voters with factual foundation. For Georgia specifically, CCD serves as a national benchmark layer beneath the richer GOSA and GaDOE data.

**URL:** https://nces.ed.gov/ccd/ (CCD home), https://data-nces.opendata.arcgis.com/ (EDGE open data), https://nces.ed.gov/ccd/elsi/ (ElSi table generator)

-----

### 3.2 EDFacts / State Report Cards

Under the Every Student Succeeds Act (ESSA), states must publish annual report cards with student achievement data, including proficiency rates on state assessments, chronic absenteeism, and per-pupil expenditure. EDFacts is the federal system that collects this data from states.

**Key variables for Civic Pulse:** Student proficiency rates in math and reading by school and district, chronic absenteeism rates, achievement gaps between student subgroups, school accountability ratings (as defined by each state), and per-pupil expenditure at the school level.

**Access:** State-level data is published on each state’s education agency website and aggregated at the federal level through EDFacts. No single unified API exists. The Department of Education publishes EDFacts data files on data.gov.

**Civic Pulse application:** Student achievement data is the most politically sensitive education data to present. Proficiency standards vary by state, making cross-state comparisons meaningless. Within a state, however, comparing a district to the state average or showing trends over time is factually sound. The key to apolitical presentation is showing the data in context without characterizing performance — that judgment belongs to the voter.

-----

### 3.3 National Assessment of Educational Progress (NAEP) — “The Nation’s Report Card”

NAEP is the only nationally representative assessment of student achievement in the United States. It provides state-level results in math, reading, science, and writing for grades 4, 8, and 12, plus results for 27 large urban districts through the Trial Urban District Assessment (TUDA).

**Key variables for Civic Pulse:** State-level average scores and proficiency percentages, urban district scores for participating cities, achievement trends over time (data back to 1990s), and achievement gaps by demographic group.

**API access:** NAEP Data Service API at nationsreportcard.gov/api_documentation.aspx. Returns JSON. Supports queries by subject, grade, year, jurisdiction, and demographic variable.

**Geographic granularity:** State and participating urban districts only. Not available at the school or district level beyond TUDA cities.

**Civic Pulse application:** NAEP is most useful as a state-level benchmark. Because it uses a consistent national framework (unlike state assessments), it provides an apples-to-apples comparison of how a state’s students perform relative to the nation. This is valuable context for framing local district performance.

**URL:** https://nces.ed.gov/nationsreportcard/data/

-----

### 3.4 Governor’s Office of Student Achievement (GOSA) — Georgia Education Data

GOSA is Georgia’s education accountability and transparency office. It produces the annual Report Card for all public schools and districts, the Georgia School Grades Reports (A-F letter grades for every public school), and several specialized dashboards. GOSA also manages GA•AWARDS, the state’s pre-K through workforce longitudinal data system.

**What it covers:** The Report Card (K-12 Report Card at gaawards.gosa.ga.gov) includes school- and district-level data on Georgia Milestones assessment results (by subject, grade, and student subgroup), graduation rates, college enrollment rates, student enrollment demographics, attendance data, discipline data, and personnel data. The Georgia School Grades Reports assign A-F letter grades to every public elementary, middle, and high school based on performance on state tests, student body composition, and graduation rates. The Downloadable Data Repository (download.gosa.ga.gov) provides multi-year spreadsheets for all Georgia schools and districts covering enrollment, assessment results, poverty rates, personnel, high school graduation, student mobility, and more. Specialized dashboards include the High School Graduate Outcomes Dashboard (post-graduation employment and earnings), the Georgia Higher Learning and Earnings Dashboard, the K-12 Student Discipline Dashboard, and the Schools Like Mine comparison tool.

**Access:** Interactive dashboards online. The downloadable data repository provides free Excel/CSV files with no login required. Custom data requests for information not available in the public files can be submitted through a GOSA Data Request Form. There is no API.

**Civic Pulse application:** For Georgia school board races, GOSA data is essential and should be the primary education data source. The downloadable data repository is the cleanest, most structured source for school-level education data in Georgia — already organized into CSV/Excel files with consistent formatting across years. The School Grades Reports provide a simple, state-sanctioned performance summary (the A-F grades) that voters can understand at a glance, though Civic Pulse should present these alongside the underlying component scores to provide depth. The Graduate Outcomes Dashboard connecting K-12 data to postsecondary earnings is particularly compelling for demonstrating long-term education quality.

**URLs:** https://gosa.georgia.gov/dashboards-data-report-card (main portal), https://download.gosa.ga.gov/ (downloadable data), https://gaawards.gosa.ga.gov/analytics/K12ReportCard (interactive report card)

-----

### 3.5 Georgia Department of Education (GaDOE) — CCRPI and GaDOE Insights

GaDOE produces the College and Career Ready Performance Index (CCRPI), Georgia’s statewide school accountability system. CCRPI rates schools and districts on a 0-100 scale across five components: Content Mastery, Progress, Closing Gaps, Readiness, and (for high schools) Graduation Rate. GaDOE also maintains the GaDOE Insights platform with dashboards covering educators and staff, teaching and learning, student performance, finance, and technology.

**What it covers:** CCRPI component scores at the school and district level, Georgia Milestones assessment data, per-pupil expenditure, School Climate Star Ratings (1-5 stars based on climate, discipline, safety, and attendance), and QBE (Quality Basic Education) funding formula data.

**Important caveat:** In October 2023, the U.S. Department of Education granted Georgia a waiver from publishing the single overall CCRPI score. GaDOE now publishes only the five component scores without rolling them up into a single number. Civic Pulse should present the component scores individually (which is arguably more informative than a single composite) and note the waiver context.

**Access:** CCRPI data is available through the GaDOE CCRPI Reporting System (ccrpi.gadoe.org) and GaDOE Insights dashboards. Downloadable data is available. No API.

**Civic Pulse application:** The CCRPI component scores and School Climate Star Ratings add dimensions that GOSA’s data does not fully cover, particularly the school climate assessment. The QBE funding data from GaDOE Insights shows how state education funding flows to each district, which is directly relevant to school board campaigns.

**URLs:** https://ccrpi.gadoe.org/ (CCRPI scores), https://georgiainsights.gadoe.org/ (GaDOE Insights dashboards)

-----

## 4. Health Data

Health outcomes are a direct concern for local government races, particularly in counties where public health departments, hospitals, and emergency services are county-managed. The sources below range from national tract-level health estimates to Georgia’s own vital statistics and hospital data.

### 4.1 Centers for Disease Control and Prevention (CDC) — PLACES and WONDER

CDC PLACES provides model-based estimates of health outcomes at the census tract, place, and county level, including prevalence of chronic conditions, health behaviors, and preventive service use. CDC WONDER provides mortality and natality data by county.

**Civic Pulse application:** PLACES data is useful for showing how a community’s health indicators compare to state and national benchmarks. The tract-level granularity makes it relevant for city council districts. The model-based nature of the estimates should be disclosed.

**URL:** https://www.cdc.gov/places/ and https://wonder.cdc.gov/

-----

### 4.2 CDC/ATSDR — Environmental Justice Index (EJI)

The Environmental Justice Index is a national, census-tract-level tool that measures the cumulative impacts of environmental burden through the lens of human health and health equity. It uses 36 indicators across three modules — environmental burden, social vulnerability, and health vulnerability — to calculate a comprehensive cumulative impacts score. Data sources include the Census Bureau, EPA, U.S. Mine Safety and Health Administration, USGS, DOT, and CDC.

**Civic Pulse application:** The EJI provides a holistic health-and-environment score for every census tract, making it useful for identifying communities facing compounded challenges. Unlike EJScreen (which focuses on environmental indicators) or CEJST (which identifies disadvantaged communities for federal funding purposes), EJI is explicitly designed around health outcomes. The three-module structure allows Civic Pulse to show which dimension — environmental, social, or health — contributes most to a tract’s score.

**URL:** https://www.atsdr.cdc.gov/place-health/php/eji/index.html

-----

### 4.3 Georgia Department of Public Health — OASIS

The Online Analytical Statistical Information System (OASIS) is DPH’s web-based health data platform, maintained by the Office of Health Indicators for Planning (OHIP). The mapping component is developed by UGA’s Carl Vinson Institute of Government.

**What it covers:** Vital statistics (births, deaths, infant mortality), hospital discharge data, emergency room visit data, STD surveillance, motor vehicle crash data, Youth Risk Behavior Survey results, Behavioral Risk Factor Surveillance Survey data, arboviral surveillance, and population data. Data is available in tabular, mapped, and charted forms. The Community Health Needs Assessment Dashboard provides ranked health indicators, trend charts, and census-tract-level maps.

**Access:** Interactive web tool with query builder. No API, but data can be exported from queries.

**Civic Pulse application:** For Georgia communities, OASIS provides more granular and more current health data than the national CDC sources. Infant mortality rates, ER utilization, and motor vehicle crash data are all relevant to local policy debates. The census-tract-level mapping capability exceeds most federal health data sources in geographic precision.

**URL:** https://oasis.state.ga.us/

-----

### 4.4 Georgia Data Analytics Center (GDAC) — Health Dashboards

GDAC, a division of the Governor’s Office of Planning and Budget, provides Tableau dashboards covering Medicaid drug utilization and quality measures, State Health Benefit Plan (SHBP) enrollment and costs, and Georgia’s All Payer Claims Database (APCD) public data. The APCD, established by SB 482 (2020), is administered by the Georgia Technology Research Institute (GTRI) and built on the OHDSI (Observational Health Data Sciences and Informatics) analytics platform hosted in GDAC’s AWS data lake.

**Civic Pulse application:** The Medicaid quality measures allow voters to compare state and national healthcare quality for the Medicaid population. SHBP data is relevant for understanding public employee healthcare costs, which are a budget line item for local government and school districts. The GDAC population projections dashboard is also valuable — it shows where Georgia’s population is growing and declining at the county level, which affects health infrastructure demand.

**URL:** https://gdac.georgia.gov/

-----

## 5. Environmental Data

Environmental conditions are an emerging priority for local campaigns, particularly in communities near industrial facilities, impaired waterways, or areas experiencing climate-related pressures. The Science for Georgia organization has demonstrated strong community demand for accessible environmental data, finding that “there are many publicly available datasets that can be used, but they are not easily identifiable and/or able to be used together.” The sources below address this gap.

### 5.1 EPA — Environmental Justice Screening Tool (EJScreen)

EJScreen is EPA’s nationally consistent environmental justice screening and mapping tool, operating at the census block group level. It combines 13 environmental burden indicators with six demographic indicators to produce composite EJ indexes.

**Environmental indicators:** PM2.5 (fine particulate matter), ozone, diesel particulate matter, air toxics cancer risk (from the National Air Toxics Assessment), air toxics respiratory hazard index, traffic proximity and volume, lead paint indicator (percentage of housing built before 1960), Superfund site proximity, RMP (Risk Management Plan) facility proximity, hazardous waste facility proximity, underground storage tank proximity, and wastewater discharge indicator.

**Demographic indicators:** People of color percentage, low income percentage, unemployment rate, limited English-speaking percentage, less than high school education percentage, and under age 5 percentage.

**API access:** EJScreen provides ArcGIS Map Services, a downloadable national dataset, and an API for programmatic access. Data is at the census block group level.

**Civic Pulse application:** EJScreen’s block-group granularity makes it relevant for the most local races. The environmental indicators are directly useful in communities near highways (traffic proximity), older housing stock (lead paint), or industrial areas (facility proximity, air toxics). Civic Pulse should present individual indicators rather than the composite indexes, allowing voters to see which specific environmental conditions affect their block group. The percentile rankings (comparing each block group to state or national distributions) provide built-in context.

**URL:** https://www.epa.gov/ejscreen

-----

### 5.2 Climate and Economic Justice Screening Tool (CEJST)

Developed by the White House Council on Environmental Quality, CEJST identifies communities that are disadvantaged and overburdened across eight burden categories: climate change, energy, health, housing, legacy pollution, transportation, water and wastewater, and workforce development. Census tracts exceeding specified thresholds in any category receive a disadvantaged designation, which determines eligibility for Justice40 Initiative funding.

**Access:** Downloadable census-tract-level data. Interactive web map at screeningtool.geoplatform.gov. No programmatic API, but data files are publicly available.

**Civic Pulse application:** CEJST’s disadvantaged designation has direct policy implications — it affects which federal investments flow into a community. Voters in designated tracts may want to know they qualify for targeted resources. The eight-category breakdown also provides a structured overview of community challenges. However, CEJST uses a binary threshold (designated or not), which loses nuance. Science for Georgia’s work has shown that a fractional scoring approach within each category is more informative.

**URL:** https://screeningtool.geoplatform.gov/

-----

### 5.3 EPA — Toxic Release Inventory (TRI)

The TRI tracks the management of certain toxic chemicals by industrial and federal facilities. Facilities that manufacture, process, or otherwise use listed chemicals above certain thresholds must report to TRI annually. Data includes the names and locations of facilities, the chemicals they release, the amounts released to air, water, and land, and transfers to off-site locations.

**Access:** TRI Explorer and Envirofacts tools for interactive query. Bulk data downloads. Programmatic access via the Envirofacts API.

**Civic Pulse application:** TRI data is facility-specific and geocoded, making it possible to show voters exactly which industrial operations in their community are releasing which chemicals and in what quantities. Trend data shows whether releases are increasing or decreasing. This is the kind of concrete, local data that Science for Georgia’s community projects (South Fulton, Augusta, DeKalb County) have demonstrated voters find valuable and actionable.

**URL:** https://www.epa.gov/toxics-release-inventory-tri-program

-----

### 5.4 Georgia Environmental Protection Division (EPD) — GOMAS

The Georgia Environmental Monitoring and Assessment System (GOMAS) is a web-accessible repository of water quality chemistry, physical, and biological data collected by EPD’s Watershed Protection Branch and by entities under contract or permit with EPD. Water quality monitoring in Georgia began in the 1960s.

**What it covers:** Water quality parameters measured in streams, rivers, and lakes across the state, including dissolved oxygen, nutrients, bacteria, sediment, and toxics. The system includes PFAS monitoring results (initiated in 2021 for groundwater-dependent small public water systems). Users can search by monitoring station number, waterbody name, county, watershed boundary (Hydrological Unit Codes, River Basin), and other parameters.

**Access:** Public database portal at gomaspublic.gaepd.org allows users to search and export data. Works best in Google Chrome.

**Civic Pulse application:** For communities near waterways, GOMAS provides the authoritative state-level water quality data. EPD’s biennial 305(b)/303(d) Integrated Report lists every impaired waterbody in Georgia with the pollutant causing impairment — a direct answer to “is my local creek/river polluted, and with what?” The PFAS StoryMap (published via ArcGIS) addresses a growing community concern about forever chemicals in drinking water. This data is most relevant for county commission and city council races in communities with water quality concerns.

**URLs:** https://gomaspublic.gaepd.org/ (data portal), https://epd.georgia.gov/water-quality-assessment (assessment reports)

-----

### 5.5 Georgia EPD — Hazardous Waste Sites

EPD maintains a priority list of hazardous waste sites requiring cleanup funding from the Georgia Hazardous Waste Trust Fund. Science for Georgia’s environmental justice research has shown that the EPD’s prioritization does not currently incorporate environmental justice criteria, meaning communities with high environmental burden may not be prioritized for cleanup.

**Civic Pulse application:** Mapping hazardous waste site locations alongside community demographic and health data (from EJScreen, CEJST, or the EJI) allows voters to see whether their community faces legacy pollution challenges. This is relevant for any local race where land use, zoning, or environmental remediation may be on the agenda.

-----

### 5.6 Science for Georgia — Health & Environmental Burden Index

Science for Georgia (Sci4Ga), a 501(c)(3) operating out of Atlanta, has created a composite health and environmental burden index that contextualizes national data from EJScreen and CEJST with Georgia-specific information. Published as an interactive ArcGIS map, it provides a burden score by census tract and overlays TRI facilities, EPD hazardous waste sites, and CEJST designations.

Science for Georgia’s work is not a data source per se, but it validates the approach and demonstrates community demand. Their projects in South Fulton, Augusta, and DeKalb County — each connecting environmental data to health outcomes and community advocacy — prove that accessible local data drives civic engagement. Their finding that the existing federal tools (EJScreen and CEJST) have significant usability and analytical limitations (EJScreen shows only one factor at a time; CEJST uses a binary threshold that loses nuance) directly informs how Civic Pulse should design its environmental data presentation.

**Key data integration lesson from Sci4Ga:** Their ArcGIS StoryMap linking pollution data to education outcomes demonstrates the value of cross-domain data presentation — showing environmental, health, and education data side by side lets communities see patterns that no single dataset reveals. Civic Pulse should enable this kind of multi-factor view without drawing causal conclusions.

**URL:** https://scienceforgeorgia.org/data-for-georgia/

-----

### 5.7 Department of Housing and Urban Development (HUD)

HUD provides data on affordable housing, homelessness (Point-in-Time counts), fair market rents, and housing choice vouchers by metro area and county. Qualified Census Tracts (QCTs) — tracts where at least 50% of households have income less than 60% of Area Median Gross Income — are designated annually by HUD and serve as a foundational layer for other mapping tools including CEJST.

**Civic Pulse application:** Fair Market Rent data is useful for understanding housing affordability at the local level. QCT designations, also available through the GDAC dashboards for Georgia, help identify concentrations of housing need.

**URL:** https://www.huduser.gov/portal/datasets/

-----

### 5.8 Federal Highway Administration / NHTSA — Traffic Safety

Local traffic safety data, including fatal crash statistics by county and city from the Fatality Analysis Reporting System (FARS), is relevant for local government races where road safety is an issue.

**URL:** https://www.nhtsa.gov/research-data/fatality-analysis-reporting-system-fars

-----

## 6. Fiscal Transparency and Government Spending

For local races, how government spends money is often the most directly relevant data category. These sources show where tax dollars go, what local governments earn, and how compensation compares across jurisdictions. Georgia is particularly well-served in this category due to the Transparency in Government Act and UGA’s TED partnership with the General Assembly.

### 6.1 TED — Tax and Expenditure Data Center for Georgia Local Governments

TED is a fiscal transparency platform maintained by UGA’s Carl Vinson Institute of Government in partnership with the Georgia General Assembly. It provides detailed revenue, expenditure, and financial data for Georgia’s counties, cities, and school districts. A companion site, TED Financial Documents, hosts actual budget and audit documents uploaded by local governments under HB 122.

**What it covers:** Tax revenues by source (property tax, SPLOST, LOST, HOST, and other local option sales taxes), expenditures by function (public safety, public works, general government, etc.), fund balances, millage rates, and financial trends over time. Data is available for counties, municipalities, and school districts. The financial documents portal hosts annual operating budgets, audited financial statements, and asset forfeiture reports for local governments with budgets over one million dollars.

**Access:** Interactive web dashboards with map views. Data can be exported. The financial documents site provides downloadable PDFs of budgets and audits. No API.

**Civic Pulse application:** For city council, county commission, and school board races, TED data is directly relevant to the policy decisions voters are evaluating. It answers questions like: How much does my county spend on public safety versus parks? How has the millage rate changed over the past decade? What’s the SPLOST revenue trend? The TED data on local option sales taxes (SPLOST, LOST, HOST, MOST, ELOST) is uniquely important in Georgia, where these taxes are frequently on the ballot and fund significant local infrastructure. Showing SPLOST revenue trends and how the money was spent is directly relevant to voter decisions on renewals.

**URLs:** https://ted.cviog.uga.edu/ (data portal), https://ted.cviog.uga.edu/financial-documents/welcome (financial documents)

-----

### 6.2 Open.Georgia.gov — State Financial Transparency

Open.Georgia.gov is the state’s Transparency in Government Act (TIGA) portal, mandated by SB 300 (2008) and administered by the Georgia Department of Audits and Accounts (DOAA).

**What it covers:** Salaries and travel reimbursements for all state employees and local board of education employees (over 1 million records across 300+ organizations), payments and obligations made by state organizations, professional services expenditures, and user fees collected by state departments. Data spans fiscal years going back to at least 2010.

**Access:** Searchable web interface with downloadable data. No API.

**Civic Pulse application:** For school board races, the education salary data is directly relevant — voters can see how teacher compensation in their district compares to others. SPLOST reports (mandated by HB 1013) are also posted here.

**URL:** https://open.ga.gov/

-----

### 6.3 Georgia Data Analytics Center (GDAC) — Budget Dashboards

GDAC provides Tableau dashboards covering state revenue trends by source and tax type, expenditure patterns by agency and vendor, state employee payroll and base salary rates, ARPA federal funds allocation, and QBE enrollment and school funding data.

**Civic Pulse application:** The QBE education funding dashboard shows per-district state funding, which is directly relevant to school board campaigns. State revenue trends by source help voters understand the fiscal environment their local government operates within.

**URL:** https://gdac.georgia.gov/budget

-----

## 7. Geographic and Boundary Data

Correctly matching a voter’s address to their specific jurisdictions — county, city, school district, voting precinct — determines which data is relevant to them. Georgia’s 159 counties (second most of any state), cities that cross county lines, and school districts that sometimes align with neither city nor county boundaries make this matching layer critical.

### 7.1 Census Bureau — TIGER/Line Shapefiles and Geocoding API

The Census Bureau provides authoritative boundary files for all census geographies (states, counties, tracts, block groups, places) and a Geocoding API that translates addresses to FIPS codes. FIPS codes are the universal geographic identifier across all federal data sources.

**Civic Pulse application:** The Geocoding API is the front door to the community data feature. A voter enters an address, the API returns FIPS codes (state, county, tract, block group, place), and those codes serve as the lookup key into all cached economic, crime, education, and health data. School district matching requires the separate NCES EDGE boundary files.

**URL:** https://geocoding.geo.census.gov/geocoder/

-----

### 7.2 Georgia GIO — State GIS Data Hub

The Georgia Geospatial Information Office (GIO) maintains a GIS data hub with spatial datasets covering the state, including administrative boundaries (county, city, voting precinct, school district), parcels, transportation, environmental features, and census geography. This is the authoritative source for Georgia political and administrative boundary data.

**Access:** ArcGIS-based data hub with GeoServices, WMS, and WFS APIs. Data downloadable in CSV, KML, GeoJSON, GeoTIFF, and other formats.

**Civic Pulse application:** The GIS layers for county, city, and school district boundaries are essential for the “look up my community” feature. Precinct-level data could support electoral analysis features in later phases. The GIO hub supplements Census TIGER data with Georgia-specific boundary layers that may be more current.

**URL:** https://data-hub.gio.georgia.gov/

-----

### 7.3 Georgia Department of Community Affairs (DCA) Open Data

ArcGIS-based open data portal with housing, community development, and grant data. Includes data on qualified housing tax credit projects, community development block grants, and other DCA-administered programs.

**URL:** https://data-georgia-dca.opendata.arcgis.com/

-----

### 7.4 Georgia General Assembly — Legislation Tracker

While not a statistical data source, tracking legislation related to local government authority, education funding formulas, and tax policy changes provides essential context for local races. The Georgia Open Data Project (gaodp.org) has built a RESTful API for General Assembly activity data.

**URL:** https://gaodp.org/

-----

## 8. Implementation Strategy

### 8.1 Architecture: Batch and Cache

Most of these datasets update annually or quarterly. The most practical architecture is a periodic ETL pipeline that pulls data from source APIs, normalizes it, and stores it in Civic Pulse’s PostgreSQL database. This avoids rate limit issues, provides consistent response times, and allows Civic Pulse to present data even if a source API is temporarily unavailable.

The pipeline should run on a schedule matched to each source’s update frequency: monthly for BLS LAUS and Georgia DOL unemployment data, annually for Census ACS, GOSA education data, and GBI crime data, and ad hoc for newly discovered local portals. FIPS codes and NCES LEA IDs serve as the universal join keys linking all datasets together.

### 8.2 The GeorgiaData.org Shortcut

For a Georgia-focused launch, GeorgiaData.org effectively functions as a pre-built data warehouse. It has already aggregated county-level data from the GBI, Census, BLS, DPH, DOL, and other sources into a consistent format. Rather than integrating with a dozen separate agencies from day one, Civic Pulse could start by ingesting GeorgiaData.org’s county datasets and supplement with direct agency data where greater granularity or timeliness is needed — specifically GOSA for school-level education data, GBI for agency-level crime data, and DOL for monthly unemployment updates.

### 8.3 Tiered Implementation Plan

**Tier 1 — Core community snapshot (launch feature):**

For economic data, pull median income, poverty rate, unemployment rate, population trend, educational attainment, SNAP/TANF participation, and vital statistics from GeorgiaData.org county downloads, supplemented by FRED or direct Census API calls for tract-level detail. For education, use GOSA downloadable data for school-level assessment scores, graduation rates, enrollment, and per-pupil spending. For public safety, use GBI UCR county-level index crime trends via GeorgiaData.org’s normalized version. For fiscal transparency, use TED for local government revenue and expenditure breakdowns, millage rates, and SPLOST data.

**Tier 2 — Enriched context (following initial launch):**

Add Georgia DOL Labor Market Explorer monthly unemployment updates and Area Labor Profiles, GDAC population projections and QBE funding by district, Open.Georgia.gov school board employee salaries, GaDOE CCRPI school-level accountability scores and School Climate Star Ratings, FBI Crime Data Explorer API for trend analysis, BEA regional price parities for cost of living context, and FRED county series for house price index trends.

**Tier 3 — Deep dives (demand-driven):**

Add EPA EJScreen environmental indicators at the block group level, CEJST disadvantaged community designations, CDC/ATSDR Environmental Justice Index for cumulative health impact scores, Georgia DPH OASIS for county and tract-level health indicators, EPA TRI facility-level toxic release data, Georgia EPD GOMAS for water quality, CDC PLACES for health outcomes, HUD for housing affordability, NHTSA FARS for traffic fatality data, and local open data portals (Fulton County, City of Atlanta, etc.).

### 8.4 Georgia-Specific Considerations

Georgia’s 159 counties mean county-level data is often the most natural unit for local races, but many Georgia cities cross county lines and school districts sometimes align with neither. The GIO boundary data is essential for correctly matching a voter’s address to the right set of jurisdictions.

GOSA’s A-F School Grades are a Georgia-specific construct voters may already be familiar with. Presenting these alongside the underlying metrics provides both accessibility and depth.

The TED data on local option sales taxes is uniquely important in Georgia, where SPLOST, LOST, HOST, MOST, and ELOST taxes are frequently on the ballot. Showing revenue trends and spending patterns for these taxes is directly relevant to voter decisions on renewals — one of the most common ballot questions in Georgia local elections.

-----

## 9. Apolitical Presentation Principles

These guidelines ensure the data remains factual and non-editorial across all domains.

**Never use color coding that implies judgment.** Red/green scales inherently suggest “bad” and “good.” Instead, use neutral color ramps (e.g., light to dark blue) for magnitude and directional arrows for trend.

**Never rank communities against each other.** The FBI explicitly warns against this for crime data, and the same principle applies broadly. Instead, show each community’s data alongside state and national benchmarks for context.

**Always present both sides of multi-dimensional indicators.** For example, if showing that per-pupil spending is above the state average, also show outcomes (graduation rate, proficiency). High spending and poor outcomes tells a different story than high spending and strong outcomes — but the voter should draw that conclusion, not the platform.

**Enable cross-domain viewing without asserting causation.** Science for Georgia’s work linking pollution data to education outcomes demonstrates that voters find multi-factor views valuable. Civic Pulse should enable showing environmental, health, and education data side by side, but should never state or imply causal relationships — present the data and let voters see the patterns.

**Include sample sizes, confidence intervals, and reporting coverage where available.** ACS estimates for small geographies have wide margins of error. GBI crime data depends on agency reporting compliance. Displaying these quality indicators prevents voters from over-interpreting the data.

**Use consistent time frames.** When comparing across indicators, use the same or similar time periods. Always show trends (current, 5 years ago, 10 years ago) and comparisons (state/national average), not isolated snapshots.

**Source attribution on every display.** Every data view should include the source agency name, data vintage (e.g., “2019-2023 American Community Survey 5-Year Estimates”), and a brief plain-language explanation of what the measure means and how it was collected. This builds trust and helps voters understand the data’s limitations.

-----

## 10. API Access Summary

|Source          |API Available      |Auth Required    |Cost|Local Granularity     |Update Frequency|
|----------------|-------------------|-----------------|----|----------------------|----------------|
|Census ACS      |Yes (REST)         |Free API key     |Free|Block group           |Annual          |
|BLS LAUS        |Yes (REST)         |Free registration|Free|County, city          |Monthly         |
|FRED            |Yes (REST)         |Free API key     |Free|County                |Varies          |
|BEA             |Yes (REST)         |Free API key     |Free|County, metro         |Annual          |
|FBI UCR         |Yes (REST)         |data.gov key     |Free|Agency (city/county)  |Quarterly       |
|BJS NIBRS       |Yes (SODA)         |None             |Free|Agency                |Annual          |
|NCES CCD        |ArcGIS + files     |None             |Free|School, district      |Annual          |
|NAEP            |Yes (REST)         |None             |Free|State, 27 cities      |Biennial        |
|CDC PLACES      |ArcGIS + files     |None             |Free|Census tract          |Annual          |
|CDC/ATSDR EJI   |Files              |None             |Free|Census tract          |Annual          |
|EPA EJScreen    |ArcGIS + API       |None             |Free|Block group           |Annual          |
|CEJST           |Files              |None             |Free|Census tract          |Periodic        |
|EPA TRI         |REST (Envirofacts) |None             |Free|Facility              |Annual          |
|HUD             |Files + some API   |Varies           |Free|County, metro         |Annual          |
|USDA ERS        |Files only         |None             |Free|County                |Annual          |
|NHTSA FARS      |Files + API        |None             |Free|County, city          |Annual          |
|GeorgiaData.org |No (downloads)     |None             |Free|County                |Varies          |
|TED (UGA/CVIOG) |No (downloads)     |None             |Free|County, city, district|Annual          |
|GBI UCR         |No (PDFs + tool)   |None             |Free|County, agency        |Annual          |
|GOSA            |No (downloads)     |None             |Free|School, district      |Annual          |
|GaDOE CCRPI     |No (downloads)     |None             |Free|School, district      |Annual          |
|Open.Georgia.gov|No (downloads)     |None             |Free|Agency, employee      |Annual          |
|GDAC            |No (Tableau)       |None             |Free|County, agency        |Varies          |
|GA DOL Explorer |No (downloads)     |None             |Free|County, MSA           |Monthly         |
|GA DPH OASIS    |No (query + export)|None             |Free|County, tract         |Varies          |
|GA GIO          |ArcGIS (WMS/WFS)   |None             |Free|Precinct, district    |As needed       |
|GA EPD GOMAS    |No (query + export)|None             |Free|Monitoring station    |Ongoing         |

All sources listed are free to use and produced by U.S. government agencies, state agencies, or publicly funded university research programs. No licensing restrictions apply to the data itself, though API terms of service require attribution and prohibit excessive request rates. Georgia state sources generally lack APIs but provide downloadable files suitable for the batch-and-cache architecture.