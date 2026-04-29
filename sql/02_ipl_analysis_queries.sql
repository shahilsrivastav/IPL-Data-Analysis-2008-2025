-- Create the database
CREATE DATABASE ipl_analysis;
USE ipl_analysis;

-- ─────────────────────────────────────
-- TABLE 1: dim_teams
-- ─────────────────────────────────────

CREATE TABLE dim_teams (
    team_id    INT          PRIMARY KEY,
    team_name  VARCHAR(100) NOT NULL
);

-- ─────────────────────────────────────
-- TABLE 2: dim_players
-- ─────────────────────────────────────

CREATE TABLE dim_players (
    player_id   INT          PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL
);

-- ─────────────────────────────────────
-- TABLE 3: dim_matches
-- ─────────────────────────────────────

CREATE TABLE dim_matches (
    match_id         INT          PRIMARY KEY,
    date             DATE,
    season           VARCHAR(20),
    season_year      INT,
    tournament       VARCHAR(100),
    batting_team     VARCHAR(100),
    bowling_team     VARCHAR(100),
    venue            VARCHAR(150),
    city             VARCHAR(100),
    day              INT,
	month            INT,
	year             INT,
    match_type       VARCHAR(100),
    stage            VARCHAR(50),
    toss_winner      VARCHAR(100),
    toss_decision    VARCHAR(20),
    match_won_by     VARCHAR(100),
    win_outcome      VARCHAR(100),
    result_type      VARCHAR(50),
    player_of_match  VARCHAR(100),
    method           VARCHAR(50),
    superover_winner VARCHAR(100),
	balls_per_over   INT,
	overs            INT,
    runs_target      INT,
    event_match_no   VARCHAR(100),
	match_number     VARCHAR(100),
	umpire           VARCHAR(100)
);

-- ─────────────────────────────────────
-- TABLE 4: fact_deliveries
-- ─────────────────────────────────────

CREATE TABLE fact_deliveries (
    delivery_id      BIGINT       PRIMARY KEY,
    match_id         INT,
    innings          INT,
    over_number      INT,
    ball             INT,
    ball_no          INT,
    batter           VARCHAR(100),
    bowler           VARCHAR(100),
    non_striker      VARCHAR(100),
    bat_pos          INT,
    batter_runs      INT,
    balls_faced      INT,
    valid_ball       INT,
    extras           INT,
    total_runs       INT,
    runs_conceded    INT,
    extra_type       VARCHAR(50),
    dismissal_type   VARCHAR(50),
    dismissed_batter VARCHAR(100),
    fielders         VARCHAR(200),
    is_four          TINYINT,
    is_six           TINYINT,
    is_boundary      TINYINT,
    is_wicket        TINYINT,
    is_dot           TINYINT,
    phase            VARCHAR(20),
    FOREIGN KEY (match_id) REFERENCES dim_matches(match_id)
);


SELECT * FROM FACT_DELIVERIES;

-- Shows batting totals with boundary counts and strike rate

SELECT
    batter,
    SUM(batter_runs) AS total_runs,
    SUM(valid_ball) AS balls_faced,
    SUM(is_four) AS fours,
    SUM(is_six) AS sixes,
    COUNT(DISTINCT match_id) AS matches_played,
    ROUND(
		SUM(batter_runs) * 100.0 /
        NULLIF(SUM(valid_ball), 0), 2) AS strike_rate
FROM fact_deliveries
GROUP BY batter
ORDER BY total_runs DESC
LIMIT 10;

-- Shows bowling details by economy rate
-- Economy = runs per over (6 balls)

SELECT
    bowler,
    SUM(runs_conceded) AS total_runs_given,
    SUM(valid_ball) AS balls_bowled,
    SUM(is_wicket) AS wickets,
    ROUND(
        SUM(runs_conceded) * 6.0 /
        NULLIF(SUM(valid_ball), 0), 2) AS economy_rate,
    ROUND(
        SUM(valid_ball) * 1.0 /
        NULLIF(SUM(is_wicket), 0), 2) AS bowling_strike_rate
FROM fact_deliveries
GROUP BY bowler
HAVING balls_bowled >= 500
ORDER BY economy_rate ASC
LIMIT 10;

-- RANK() with PARTITION BY creates a separate ranking per season
-- shows batter rank, runs
SELECT
    season_year,
    batter,
    season_runs,
    season_rank
FROM (
    SELECT
        m.season_year,
        f.batter,
        SUM(f.batter_runs)              AS season_runs,
        RANK() OVER (
            PARTITION BY m.season_year
            ORDER BY SUM(f.batter_runs) DESC
        )                               AS season_rank
    FROM fact_deliveries f
    JOIN dim_matches m
        ON f.match_id = m.match_id
    GROUP BY m.season_year, f.batter
) ranked
WHERE season_rank <= 3
ORDER BY season_year ASC, season_rank ASC;

-- Shows how a batter's score built up delivery by delivery in a match
-- Change the match_id value to explore different matches

SELECT
    match_id,
    batter,
    over_number,
    ball,
    batter_runs AS runs_this_ball,
    SUM(batter_runs) OVER (
        PARTITION BY match_id, batter
        ORDER BY over_number, ball
        ROWS BETWEEN UNBOUNDED PRECEDING
             AND CURRENT ROW
    ) AS running_total
FROM fact_deliveries
WHERE match_id = 335982
ORDER BY batter, over_number, ball;

-- A CTE (WITH clause)
-- Step 1: count POM awards per player
-- Step 2: rank them
-- Step 3: filter top 15
WITH pom_counts AS (
    SELECT
        player_of_match AS player,
        COUNT(*) AS pom_count,
        COUNT(DISTINCT season_year) AS seasons_active
    FROM dim_matches
    WHERE player_of_match IS NOT NULL
      AND player_of_match != 'none'
    GROUP BY player_of_match
),
pom_ranked AS (
    SELECT
        player,
        pom_count,
        seasons_active,
        RANK() OVER (ORDER BY pom_count DESC) AS rnk
    FROM pom_counts
)
SELECT
    player,
    pom_count,
    seasons_active
FROM pom_ranked
WHERE rnk <= 15
ORDER BY pom_count DESC;

-- Compares win rate when toss winner bats vs fields
-- CASE WHEN inside SUM() counts rows matching a condition
SELECT
    toss_decision,
    COUNT(*) AS total_matches,
    SUM(
        CASE
            WHEN toss_winner = match_won_by
            THEN 1 ELSE 0
        END
    ) AS toss_won_and_match_won,
    ROUND(
        SUM(
			CASE
				WHEN toss_winner = match_won_by
                THEN 1 ELSE 0 END
			)* 100.0 / COUNT(*), 2) AS win_percentage
FROM dim_matches
GROUP BY toss_decision
ORDER BY win_percentage DESC;

-- Compares the same bowler's performance across all 3 phases
-- Shows phase as a column for easy comparison
-- Change WHERE f.phase to 'Powerplay' or 'Middle' to see the same analysis for other phases.
SELECT
    bowler,
    phase,
    SUM(valid_ball) AS balls,
    SUM(runs_conceded) AS runs,
    SUM(is_wicket) AS wickets,
    ROUND(
        SUM(runs_conceded) * 6.0 /
        NULLIF(SUM(valid_ball), 0), 2) AS economy,
    ROUND(
        SUM(is_dot) * 100.0 /
        NULLIF(SUM(valid_ball), 0), 2) AS dot_ball_pct
FROM fact_deliveries 
WHERE phase = 'Powerplay'
GROUP BY bowler, phase
HAVING balls >= 120
ORDER BY economy ASC
LIMIT 15;

-- Joins fact_deliveries to dim_matches to get venue information
-- Calculates average runs per match per venue
SELECT
    m.venue,
    m.city,
    COUNT(DISTINCT m.match_id) AS matches_played,
    SUM(f.total_runs) AS total_runs_scored,
    ROUND(
        SUM(f.total_runs) /
        NULLIF(COUNT(DISTINCT m.match_id), 0), 0) AS avg_runs_per_match,
    SUM(f.is_six) AS total_sixes,
    ROUND(
        SUM(f.is_six) * 1.0 /
        NULLIF(COUNT(DISTINCT m.match_id), 0), 1) AS avg_sixes_per_match
FROM fact_deliveries f
JOIN dim_matches m
    ON f.match_id = m.match_id
GROUP BY m.venue, m.city
HAVING matches_played >= 10
ORDER BY avg_runs_per_match DESC
LIMIT 15;


