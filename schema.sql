-- FamilyHub production database
-- Run this entire file in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.families(
 id uuid primary key default gen_random_uuid(),
 name text not null,
 invite_code text unique not null,
 created_at timestamptz not null default now()
);

create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 family_id uuid not null references public.families(id) on delete cascade,
 display_name text not null,
 email text,
 role text not null default 'member' check(role in ('admin','member')),
 created_at timestamptz not null default now()
);

create table if not exists public.messages(
 id uuid primary key default gen_random_uuid(),
 family_id uuid not null references public.families(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 4000),
 created_at timestamptz not null default now()
);

create table if not exists public.tasks(
 id uuid primary key default gen_random_uuid(),
 family_id uuid not null references public.families(id) on delete cascade,
 created_by uuid not null references auth.users(id) on delete cascade,
 assigned_to uuid not null references auth.users(id) on delete cascade,
 title text not null check(char_length(title) between 1 and 500),
 done boolean not null default false,
 created_at timestamptz not null default now()
);

create table if not exists public.photos(
 id uuid primary key default gen_random_uuid(),
 family_id uuid not null references public.families(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 path text not null,
 url text not null,
 created_at timestamptz not null default now()
);

create index if not exists profiles_family_idx on public.profiles(family_id);
create index if not exists messages_family_idx on public.messages(family_id,created_at);
create index if not exists tasks_family_idx on public.tasks(family_id,created_at);
create index if not exists photos_family_idx on public.photos(family_id,created_at);

alter table public.families enable row level security;
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
alter table public.tasks enable row level security;
alter table public.photos enable row level security;

create or replace function public.my_family_id()
returns uuid language sql stable security definer set search_path=public
as $$ select family_id from public.profiles where id=auth.uid() $$;

create or replace function public.is_family_member(fid uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and family_id=fid) $$;

create or replace function public.is_family_admin(fid uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and family_id=fid and role='admin') $$;

-- Admin creates the first family after signing up.
create or replace function public.create_family(p_name text,p_code text)
returns public.families
language plpgsql security definer set search_path=public
as $$
declare f public.families;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 if exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Already in a family'; end if;
 if length(trim(p_name))<2 or length(trim(p_code))<6 then raise exception 'Invalid family name or code'; end if;
 if exists(select 1 from public.families where invite_code=trim(p_code)) then raise exception 'Invite code already exists'; end if;
 insert into public.families(name,invite_code) values(trim(p_name),trim(p_code)) returning * into f;
 insert into public.profiles(id,family_id,display_name,email,role)
 values(auth.uid(),f.id,coalesce((auth.jwt()->'user_metadata'->>'display_name'),'Admin'),auth.email(),'admin');
 return f;
end $$;

-- Existing family members use this invite code after signup.
create or replace function public.join_family(p_code text,p_name text)
returns public.families
language plpgsql security definer set search_path=public
as $$
declare f public.families;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 select * into f from public.families where invite_code=trim(p_code);
 if f.id is null then raise exception 'Invalid family invite code'; end if;
 if exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Already in a family'; end if;
 insert into public.profiles(id,family_id,display_name,email,role)
 values(auth.uid(),f.id,trim(p_name),auth.email(),'member');
 return f;
end $$;

grant execute on function public.create_family(text,text) to authenticated;
grant execute on function public.join_family(text,text) to authenticated;
grant execute on function public.my_family_id() to authenticated;
grant execute on function public.is_family_member(uuid) to authenticated;
grant execute on function public.is_family_admin(uuid) to authenticated;

create policy "family members can read own family" on public.families for select to authenticated
using(id=public.my_family_id());

create policy "members read profiles" on public.profiles for select to authenticated
using(family_id=public.my_family_id());

create policy "members read messages" on public.messages for select to authenticated
using(family_id=public.my_family_id());
create policy "members send messages" on public.messages for insert to authenticated
with check(family_id=public.my_family_id() and user_id=auth.uid());

create policy "members read tasks" on public.tasks for select to authenticated
using(family_id=public.my_family_id());
create policy "members create tasks" on public.tasks for insert to authenticated
with check(family_id=public.my_family_id() and created_by=auth.uid() and assigned_to in(select id from public.profiles where family_id=public.my_family_id()));
create policy "members update tasks" on public.tasks for update to authenticated
using(family_id=public.my_family_id())
with check(family_id=public.my_family_id());
create policy "admins delete tasks" on public.tasks for delete to authenticated
using(public.is_family_admin(family_id));

create policy "members read photos" on public.photos for select to authenticated
using(family_id=public.my_family_id());
create policy "members add photos" on public.photos for insert to authenticated
with check(family_id=public.my_family_id() and user_id=auth.uid());
create policy "members delete photos" on public.photos for delete to authenticated
using(family_id=public.my_family_id() and (user_id=auth.uid() or public.is_family_admin(family_id)));

-- Storage: create bucket named family-photos and make it PRIVATE in the Storage UI.
-- These policies restrict object paths to the caller's family UUID.
create policy "family photo read" on storage.objects for select to authenticated
using(bucket_id='family-photos' and public.is_family_member((storage.foldername(name))[1]::uuid));

create policy "family photo upload" on storage.objects for insert to authenticated
with check(bucket_id='family-photos' and public.is_family_member((storage.foldername(name))[1]::uuid));

create policy "family photo delete" on storage.objects for delete to authenticated
using(bucket_id='family-photos' and public.is_family_member((storage.foldername(name))[1]::uuid));

-- Realtime
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.photos;
