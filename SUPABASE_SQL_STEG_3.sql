-- STORD ACADEMY – Prototype 8, steg 3
-- Kjør denne EN GANG i Supabase SQL Editor.

create table if not exists public.instructor_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.instructor_users enable row level security;
revoke all on table public.instructor_users from anon, authenticated;

create or replace function public.is_instructor()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.instructor_users where user_id=auth.uid()); $$;
revoke all on function public.is_instructor() from public;
grant execute on function public.is_instructor() to authenticated;

create or replace function public.get_exam(p_access_code text)
returns table(attempt_id uuid, student_name text, exam_no integer, status text, started_at timestamptz, published boolean, total_points numeric, overall_comment text)
language sql security definer set search_path=public
as $$ select id, student_name, exam_no, status, started_at, published, total_points, overall_comment from public.attempts where access_code=upper(trim(p_access_code)) limit 1; $$;

create or replace function public.get_my_answers(p_attempt_id uuid,p_access_code text)
returns table(question_no integer,subquestion_no integer,answer_text text)
language sql security definer set search_path=public
as $$ select a.question_no,a.subquestion_no,a.answer_text from public.answers a join public.attempts t on t.id=a.attempt_id where t.id=p_attempt_id and t.access_code=upper(trim(p_access_code)); $$;

create or replace function public.get_result(p_access_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t public.attempts; r jsonb;
begin
 select * into t from public.attempts where access_code=upper(trim(p_access_code)) and published=true limit 1;
 if t.id is null then raise exception 'Resultatet er ikke publisert ennå'; end if;
 select jsonb_build_object('meta',jsonb_build_object('student_name',t.student_name,'exam_no',t.exam_no,'total_points',t.total_points,'overall_comment',t.overall_comment),
 'answers',coalesce(jsonb_agg(jsonb_build_object('question_no',a.question_no,'subquestion_no',a.subquestion_no,'answer_text',a.answer_text,'points',a.points,'instructor_comment',a.instructor_comment) order by a.question_no,a.subquestion_no),'[]'::jsonb)) into r
 from public.answers a where a.attempt_id=t.id;
 return r;
end; $$;

create or replace function public.instructor_list_attempts()
returns table(id uuid,student_name text,exam_no integer,status text,submitted_at timestamptz,published boolean)
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_instructor() then raise exception 'Ikke godkjent som instruktør'; end if;
 return query select a.id,a.student_name,a.exam_no,a.status,a.submitted_at,a.published from public.attempts a order by a.created_at desc;
end; $$;

create or replace function public.instructor_get_attempt(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t public.attempts; r jsonb;
begin
 if not public.is_instructor() then raise exception 'Ikke godkjent som instruktør'; end if;
 select * into t from public.attempts where id=p_attempt_id;
 if t.id is null then raise exception 'Prøven finnes ikke'; end if;
 select jsonb_build_object('meta',jsonb_build_object('student_name',t.student_name,'exam_no',t.exam_no,'overall_comment',t.overall_comment),
 'answers',coalesce(jsonb_agg(jsonb_build_object('question_no',a.question_no,'subquestion_no',a.subquestion_no,'answer_text',a.answer_text,'points',a.points,'instructor_comment',a.instructor_comment) order by a.question_no,a.subquestion_no),'[]'::jsonb)) into r
 from public.answers a where a.attempt_id=t.id;
 return r;
end; $$;

create or replace function public.instructor_publish_result(p_attempt_id uuid,p_grading jsonb,p_overall_comment text)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; total numeric:=0; has_points boolean:=false;
begin
 if not public.is_instructor() then raise exception 'Ikke godkjent som instruktør'; end if;
 for item in select * from jsonb_array_elements(p_grading) loop
   update public.answers set points=case when item->>'points' is null then null else (item->>'points')::numeric end,
     instructor_comment=coalesce(item->>'instructor_comment',''), updated_at=now()
   where attempt_id=p_attempt_id and question_no=(item->>'question_no')::integer and subquestion_no=(item->>'subquestion_no')::integer;
   if item->>'points' is not null then total:=total+(item->>'points')::numeric; has_points:=true; end if;
 end loop;
 update public.attempts set overall_comment=coalesce(p_overall_comment,''), total_points=case when has_points then total else null end, published=true, status='Rettet – resultat publisert' where id=p_attempt_id;
end; $$;

revoke all on function public.get_exam(text) from public;
revoke all on function public.get_my_answers(uuid,text) from public;
revoke all on function public.get_result(text) from public;
revoke all on function public.instructor_list_attempts() from public;
revoke all on function public.instructor_get_attempt(uuid) from public;
revoke all on function public.instructor_publish_result(uuid,jsonb,text) from public;
grant execute on function public.get_exam(text) to anon,authenticated;
grant execute on function public.get_my_answers(uuid,text) to anon,authenticated;
grant execute on function public.get_result(text) to anon,authenticated;
grant execute on function public.instructor_list_attempts() to authenticated;
grant execute on function public.instructor_get_attempt(uuid) to authenticated;
grant execute on function public.instructor_publish_result(uuid,jsonb,text) to authenticated;
