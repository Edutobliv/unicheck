-- Session reports and summaries

-- Summary of attendance by session
create or replace view session_attendance_summary as
select
  s.id as session_id,
  s.teacher_code,
  extract(epoch from s.started_at)::bigint as started_at,
  extract(epoch from s.expires_at)::bigint as expires_at,
  s.offering_id,
  count(a.*) as total,
  count(*) filter (where a.status = 'present') as present,
  count(*) filter (where a.status = 'late') as late,
  count(*) filter (where a.status = 'excused') as excused,
  count(distinct a.student_code) as unique_students
from class_sessions s
left join attendance a on a.session_id = s.id
group by s.id, s.teacher_code, s.started_at, s.expires_at, s.offering_id
order by s.started_at desc;

-- Detailed attendee list for a given session (parameterized example)
-- select a.student_code, u.name, u.email, a.status, extract(epoch from a.at)::bigint as at
--   from attendance a
--   left join users u on u.code = a.student_code
--  where a.session_id = '<session-uuid>'
--  order by a.at asc;

