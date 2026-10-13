create database if not exists merdian_fraud;
use merdian_fraud;

create table premiums(
    member_id varchar(20) not null,
    premium_month char(7) not null,
    plan_id varchar(10),
    premium_amount decimal(10, 2),
    payment_status varchar(15),
    feed_month char(7),
    primary key (member_id, premium_month));

create table claim_lines(
    claim_id varchar(20) not null,
    line_number int not null,
    procedure_code varchar(10), 
    modifier varchar(10),
    units int,
    billed_amount decimal(10, 2),
    allowed_amount decimal(10, 2),
    paid_amount decimal(10, 2),
    line_status varchar(15),
    feed_month char(7),
    primary key (claim_id, line_number));
    
create table claims(
    claim_id varchar(20) not null,
    member_id varchar(20) not null,
    provider_id varchar(10),
    claim_type varchar(20),
    place_of_service varchar(50),
    service_from_date date,
    service_to_date date,
    received_date date,
    processed_date date,
    primary_diagnosis varchar(20),
    secondary_diagnosis varchar(10),
    total_billed decimal(10, 2),
    total_allowed decimal(10, 2),
    total_paid decimal(10, 2),
    member_responsibility decimal(10, 2),
    claim_status varchar(10), 
    denial_code varchar(10),
    submission_channel varchar(20),
    original_claim_id varchar(20),
    feed_month char(7),
    telehealth_flag varchar(5),
    version_count int, 
    first_seen_feed char(7),
    is_adjustment boolean,
    days_to_submit int,
    processing_days int, 
    received_before_service boolean,
    primary key (claim_id));
SELECT constraint_name, table_name, referenced_table_name
FROM information_schema.referential_constraints
WHERE constraint_schema = DATABASE();
    
-- loading csv files
alter table claim_lines add foreign key (claim_id) references claims (claim_id);
set global local_infile = 1; 
-- Premiums 
show variables like 'local_infile';
load data local infile "C:/Users/munic/Desktop/Oriana Data Analytics Internship/Final Project/Dataset/preprocessed/premiums_clean.csv"
into table premiums
fields terminated by ',' optionally enclosed by '"'
lines terminated by '\n'
ignore 1 lines
(member_id, premium_month, plan_id, premium_amount, payment_status, @feed_month)
set feed_month = trim(trailing '\r' from@feed_month);

-- claims
load data local infile "C:/Users/munic/Desktop/Oriana Data Analytics Internship/Final Project/Dataset/preprocessed/claims_clean.csv"
into table claims
fields terminated by ',' optionally enclosed by '"'
lines terminated by '\n'
ignore 1 lines
(claim_id, member_id, provider_id, claim_type, place_of_service,
 service_from_date, service_to_date, received_date, @processed_date,
 primary_diagnosis, @secondary_diagnosis,
 total_billed, total_allowed, total_paid, member_responsibility,
 claim_status, @denial_code, submission_channel, @original_claim_id,
 feed_month, @telehealth_flag, version_count, first_seen_feed,
 @is_adjustment, days_to_submit, @processing_days, @received_before_service)
set processed_date          = nullif(@processed_date, ''),
    secondary_diagnosis     = nullif(@secondary_diagnosis, ''),
    denial_code             = nullif(@denial_code, ''),
    original_claim_id       = nullif(@original_claim_id, ''),
    telehealth_flag         = nullif(@telehealth_flag, ''),
    is_adjustment           = (@is_adjustment = 'True'),
    processing_days         = cast(nullif(@processing_days, '') as decimal(10,0)),
    received_before_service = (trim(trailing '\r' from @received_before_service) = 'True');
    
load data local infile "C:/Users/munic/Desktop/Oriana Data Analytics Internship/Final Project/Dataset/preprocessed/claim_lines_clean.csv"
into table claim_lines
fields terminated by ',' optionally enclosed by '"'
lines terminated by '\n'
ignore 1 lines
(claim_id, line_number, procedure_code, @modifier, units,
 billed_amount, allowed_amount, paid_amount, line_status, @feed_month)
set modifier   = nullif(@modifier, ''),
    feed_month = trim(trailing '\r' from @feed_month);
    
-- checking the claims load

select count(*) from claims;
select count(*) from claims where processed_date is null; -- expect 866 (the Pending claims)
select count(denial_code) as Denail_code from claims;
select count(secondary_diagnosis) as Secondary_Diagnosis from claims;
select count(original_claim_id) as Original_Claim_Id from claims;
select count(telehealth_flag) as TeleHealth_Flag from claims;
select sum(is_adjustment) as IS_Adjustment from claims;
select sum(received_before_service) as Received_before_Service from claims;
select sum(total_billed) as Total_Billed from claims;
select sum(total_paid) as Total_Paid from claims;

-- checking the claim_lines load

select count(*) from claim_lines;
select sum(billed_amount) as Billed_Amount from claim_lines;
select count(modifier) as Modifier from claim_lines;
select count(*) as Procedure_code from claim_lines where procedure_code = '0110';

-- checking the claims and claim_lines joins correctly
-- claim Lines with no parent claim
select count(*) as lines_without_claim from claim_lines l left join claims c on c.claim_id = l.claim_id where c.claim_id is null;
-- Claims with no lines
select count(*) as claims_without_lines from claims c left join claim_lines l on l.claim_id = c.claim_id where l.claim_id is null;
-- Billed: claim total vs sum of its lines
select c.claim_id, c.total_billed, sum(l.billed_amount) as lines_billed 
from claims c  left join claim_lines l on l.claim_id = c.claim_id 
group by c.claim_id, c.total_billed having round(c.total_billed, 2) <> round(sum(l.billed_amount), 2) limit 20;

-- SELECT
--     COUNT(*)                        AS claims_with_difference,
--     SUM(ABS(diff) > 0.01)           AS bigger_than_one_cent,
--     MAX(ABS(diff))                  AS largest_difference,
--     SUM(diff)                       AS net_difference
-- FROM (
--     SELECT c.claim_id,
--            ROUND(c.total_billed - SUM(l.billed_amount), 2) AS diff
--     FROM claims c
--     JOIN claim_lines l ON l.claim_id = c.claim_id
--     GROUP BY c.claim_id, c.total_billed
--     HAVING diff <> 0
-- ) t;

-- check allowed and paid
-- Allowed

select count(*) as claims_off, max(abs(diff)) as largest_difference, sum(diff) as net_difference
from (
    select c.claim_id, round(c.total_allowed - sum(l.allowed_amount), 2) as diff from claims c
    join claim_lines l on l.claim_id = c.claim_id group by c.claim_id, c.total_allowed having diff <> 0) t;

--  Paid
select count(*) as claims_off, max(abs(diff)) as largest_difference, sum(diff) as net_difference
from (
    select c.claim_id, round(c.total_paid - sum(l.paid_amount), 2) as diff from claims c
    join claim_lines l on l.claim_id = c.claim_id group by c.claim_id, c.total_paid having diff <> 0) t;
    
-- look at the providers
-- How many providers, and how many claims have no provider
select count(distinct provider_id) as Providers, sum(provider_id is null) as Claims_Without_Provider from claims;
-- Claims per provider, biggest first
select provider_id, count(*) as claims, sum(total_billed) as Billed from claims group by provider_id order by claims desc limit 15;

-- check provider size and ID groups
-- Do the provider IDs fall into different groups?

select left(provider_id, 2) as id_prefix, count(distinct provider_id) as Providers, count(*) as Claims from claims group by id_prefix;
-- How many providers are small?
select case when n < 10 then '1. under 10'
			when n < 30 then '2. 10 - 29'
            when n < 100 then '3. 30 - 99'
            else  '4. 100+' end as Size_Band ,
		count(*) as Providers, sum(n) as Claims
from(select provider_id , count(*) as n from claims group by provider_id) t group by Size_Band order by Size_Band;

-- profile P9001 and list the exact column values
--  P9001 compared with all other providers
select case when provider_id = 'P9001' then 'P9001' else 'all others' end as Grp,
count(*) as Claims, round(avg(total_billed), 2) as Avg_Billed, round(avg(total_paid), 2) as Avg_Paid, 
round(100 * count(denial_code) / count(*), 1) as Pct_With_Denial_Code,
round(avg(processing_days), 1) as Avg_Processing_Days, round(avg(days_to_submit), 1) as Avg_Days_To_Submit from claims group by Grp; 
-- The exact values in the status and type columns
select claim_status, count(*) from claims group by claim_status;
select claim_type, count(*) from claims group by claim_type;
select submission_channel, count(*) from claims group by submission_channel;

-- The provider comparison table (providers with 30+ claims)
select provider_id, count(*) as Claims, round(sum(total_billed), 2) as Billed, round(sum(total_allowed), 2) as Allowed, 
round(sum(total_paid), 2) as Paid, round(avg(total_billed), 2) as Avg_Billed_Per_Claim,
round(100 * sum(total_paid) / nullif(sum(total_allowed), 0), 1) as Paid_Pct_Of_Allowed,
round(100 * sum(denial_code is not null) / count(*), 1) as Denial_Rate_Pct, round(avg(processing_days), 2) as Avg_Processing_Days,
round(avg(days_to_submit), 2) as Avg_Days_To_Submit from claims group by provider_id having count(*) >= 30 order by Billed desc;

-- who stands out
-- Highest denial rates
select provider_id, count(*) as Claims, round(100 * sum(denial_code is not null) / count(*), 1) as Denial_Rate_Pct 
from claims group by provider_id having count(*) >= 30 order by Denial_Rate_Pct desc limit 10;

-- Slowest processing
select provider_id, count(*) as Claims, round(avg(processing_days), 1) as Avg_Processing_Days from claims
group by provider_id having count(*) >= 30 order by Avg_Processing_Days desc limit 10;
-- Lowest share of allowed amount actually paid
select provider_id, count(*) as Claims, round(100 * sum(total_paid) / nullif(sum(total_allowed), 0), 1) as Paid_Pct_Of_Allowed
from claims group by provider_id having  count(*) >= 30 order by Paid_Pct_Of_Allowed asc limit 10;

-- explain the providers with unusually high billed per claim
-- P2086 and P2044 bill about double per claim. This shows what they bill for.
-- Claim type mix for the high-billing providers (claim-level, uses claims only)

select provider_id, claim_type, count(*) as Claims, round(sum(total_billed), 2) as Billed from claims
where provider_id in ('P2086', 'P2044', 'P2003', 'P2035') group by provider_id, claim_type order by provider_id, Claims desc;
-- Their top procedures (line-level, uses claim_lines amounts only)
select c.provider_id, l.procedure_code, count(*) as Claim_lines, round(sum(l.billed_amount), 2) as Billed from claim_lines l 
join claims c on c.claim_id = l.claim_id where c.provider_id in('P2086', 'P2044') group by c.provider_id, l.procedure_code order by c.provider_id, Billed desc;

-- check that your filter didn’t lose data
select count(*) as providers_compared, sum(n) as claims_covered
from (select provider_id, count(*) as n from claims group by provider_id having n >= 30) t;
