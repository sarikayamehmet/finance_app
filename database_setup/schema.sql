-- USAGE: sqlite3 /tmp/finance.db < schema.sql

-- set up and load main tables

.separator ","

drop table if exists buckets;
create table buckets (
  bucketid integer primary key autoincrement,
  bucketname text not null,
  buckettype text not null,
  initialbalancecents integer
);

.import buckets_starter.csv buckets

drop table if exists entries;
create table entries (
  entryid integer primary key autoincrement,
  description text not null,
  amountcents integer,
  srcbucket integer,
  destbucket integer,
  date text
);

.import entries_starter.csv entries

drop table if exists proportions;
create table proportions (
  proportionid integer not null,
  proportionbucketid integer not null,
  percent integer not null
);

.import proportions_starter.csv proportions

-- create views

drop view if exists entries_labeled;
create view entries_labeled as
select entryid, description, amountcents, date, src.bucketid as srcbucketid, src.bucketname as srcbucketname, src.buckettype as srcbuckettype, dest.bucketid as destbucketid, dest.bucketname as destbucketname, dest.buckettype as destbuckettype
from entries
  join buckets as src
    on entries.srcbucket = src.bucketid
  join buckets as dest
    on entries.destbucket = dest.bucketid
  order by entryid asc;

drop view if exists proportions_labeled;
create view proportions_labeled as
select proportionid, p.bucketname as proportionname, proportionbucketid, b.bucketname as bucketname, b.buckettype as buckettype, percent
from proportions
  join buckets as p
    on proportions.proportionid = p.bucketid
  join buckets as b
    on proportions.proportionbucketid = b.bucketid;

drop view if exists double_entries;
create view double_entries as 
select entryid, description, amountcents, date, destbucket as bucket from entries
  union
select entryid, description, -amountcents as amountcents, date, srcbucket as bucket from entries;

drop view if exists double_entries_labeled;
create view double_entries_labeled as
select
  entryid, description, amountcents, date, bucketid, bucketname, buckettype
from double_entries
  join buckets
    on bucket = bucketid;

drop view if exists double_entries_labeled_expand_proportions_fully;
create view double_entries_labeled_expand_proportions_fully as
select
    entryid,
    description,
    amountcents * percent / 100.0 as amountcents,
    date,
    p.proportionbucketid as bucketid,
    p.bucketname as bucketname,
    p.buckettype as buckettype
  from double_entries_labeled as de
  join proportions_labeled as p 
    on de.bucketid = p.proportionid
  where de.buckettype = "proportion"
union
select
  entryid,
  description,
  cast(amountcents as real) as amountcents,
  date,
  bucketid,
  bucketname,
  buckettype
  from double_entries_labeled where buckettype <> "proportion";

drop view if exists double_entries_labeled_expand_proportions;
create view double_entries_labeled_expand_proportions as
select
  entryid,
  min(description) as description,
  sum(amountcents) as amountcents,
  min(date),
  bucketid,
  min(bucketname) as bucketname,
  min(buckettype) as buckettype
from double_entries_labeled_expand_proportions_fully
group by entryid, bucketid;

drop view if exists entries_with_bucket_changes;
create view entries_with_bucket_changes as
select
  entries_cross_buckets.entryid as entryid,
  date,
  bucketid_for_change,
  bucketname_for_change,
  case when de.amountcents isnull then 0.0 else de.amountcents end as amountcents
from
  (select entryid, date, buckets.bucketid as bucketid_for_change, buckets.bucketname as bucketname_for_change
    from entries, buckets where buckets.buckettype = "internal") as entries_cross_buckets
  left outer join
  double_entries_labeled_expand_proportions as de
  on entries_cross_buckets.entryid = de.entryid and entries_cross_buckets.bucketid_for_change = de.bucketid;

drop view if exists net_change;
create view net_change as
select
  bucketid,
  sum(amountcents) as net_change_fractional,
  cast(round(sum(amountcents)) as integer) as net_change
from double_entries_labeled_expand_proportions
group by bucketid;

drop view if exists buckets_with_net_change;
create view buckets_with_net_change as
select 
  b.bucketid as bucketid,
  b.bucketname as bucketname,
  b.buckettype as buckettype,
  b.initialbalancecents as initialbalancecents,
  case when nc.net_change isnull then 0 else nc.net_change end as net_change,
  case when nc.net_change isnull then initialbalancecents else initialbalancecents + nc.net_change end as finalbalancecents
from buckets as b
  left outer join net_change as nc
    on b.bucketid = nc.bucketid
where b.buckettype <> "proportion";

drop view if exists bucket_proportion_combos;
create view bucket_proportion_combos as
select
  bid, bname, pid, pname,
  case when percent isnull then 0 else percent end as percent
from
  (select b.bucketid as bid, b.bucketname as bname, p.bucketid as pid, p.bucketname as pname from
    (select * from buckets where buckettype = "internal") as b,
    (select * from buckets where buckettype = "proportion") as p )
  left outer join proportions_labeled
  on bid = proportionbucketid and pid = proportionid;
