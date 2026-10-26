-- Campus Pulse hosted backend for Supabase.
-- Run this entire file once in Supabase Dashboard > SQL Editor > New query.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  branch text not null default '',
  role text not null default 'student' check (role in ('student','club','admin')),
  club_name text not null default '',
  purpose text not null default '',
  verified boolean not null default false,
  id_card_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null default 'Club event',
  event_date date not null,
  event_time text not null default '',
  venue text not null,
  description text not null,
  image_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  payment_received boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'Campus',
  event_date date not null,
  event_time text not null default '',
  venue text not null,
  description text not null,
  organizer text not null default '',
  poster_path text not null default '',
  source_promotion_id uuid unique references public.promotions(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.event_images (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  year integer not null,
  image_path text not null,
  alt_text text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists promotions_user_status_idx on public.promotions(user_id,status);
create index if not exists events_date_idx on public.events(event_date);
create index if not exists event_images_event_year_idx on public.event_images(event_id,year desc);

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

create or replace function public.is_verified_club()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'club' and p.verified);
$$;

revoke execute on function public.is_admin() from public,anon;
grant execute on function public.is_admin() to authenticated;
revoke execute on function public.is_verified_club() from public,anon;
grant execute on function public.is_verified_club() to authenticated;

create or replace function public.create_campus_profile()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  requested_role text;
  requested_branch text;
begin
  requested_role := case when new.raw_user_meta_data->>'account_type' = 'club' then 'club' else 'student' end;
  requested_branch := coalesce(new.raw_user_meta_data->>'branch','');
  if requested_branch not in ('Mining Engineering','Materials and Metallurgical Engineering','Information Technology','Computer Science and Engineering','Chemical Engineering','Biotechnology','M.Tech','Ph.D.') then
    raise exception 'Choose a valid NIT Raipur branch.';
  end if;
  if requested_role = 'club' and (coalesce(trim(new.raw_user_meta_data->>'club_name'),'') = '' or coalesce(trim(new.raw_user_meta_data->>'purpose'),'') = '') then
    raise exception 'Club accounts need a club name and purpose.';
  end if;
  insert into public.profiles(id,full_name,email,branch,role,club_name,purpose)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),new.email),
    lower(new.email),
    requested_branch,
    requested_role,
    coalesce(trim(new.raw_user_meta_data->>'club_name'),''),
    coalesce(trim(new.raw_user_meta_data->>'purpose'),'')
  );
  return new;
end;
$$;

drop trigger if exists campus_profile_after_signup on auth.users;
create trigger campus_profile_after_signup
after insert on auth.users
for each row execute procedure public.create_campus_profile();

create or replace function public.protect_profile_fields()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() = old.id and not public.is_admin() then
    if new.id is distinct from old.id or new.email is distinct from old.email
      or new.role is distinct from old.role or new.verified is distinct from old.verified
      or new.created_at is distinct from old.created_at
      or new.full_name is distinct from old.full_name
      or new.branch is distinct from old.branch
      or new.club_name is distinct from old.club_name
      or new.purpose is distinct from old.purpose then
      raise exception 'Account identity and verification fields cannot be changed by the account owner.';
    end if;
    if old.verified and new.id_card_path is distinct from old.id_card_path then
      raise exception 'A verified ID record cannot be changed by the account owner.';
    end if;
    if new.id_card_path is not null and split_part(new.id_card_path,'/',1) <> old.id::text then
      raise exception 'College ID files must stay in the account owner folder.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_campus_profile on public.profiles;
create trigger protect_campus_profile
before update on public.profiles
for each row execute procedure public.protect_profile_fields();

alter table public.profiles enable row level security;
alter table public.promotions enable row level security;
alter table public.events enable row level security;
alter table public.event_images enable row level security;

revoke all on public.profiles,public.promotions,public.events,public.event_images from anon,authenticated;
grant select on public.events,public.event_images to anon,authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.promotions to authenticated;
grant insert,update,delete on public.events,public.event_images to authenticated;

-- Public pages can read event listings and archive photos. Only the admin can change them.
drop policy if exists "Public can read events" on public.events;
create policy "Public can read events" on public.events for select to anon,authenticated using (true);
drop policy if exists "Admin manages events" on public.events;
create policy "Admin manages events" on public.events for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Public can read event photos" on public.event_images;
create policy "Public can read event photos" on public.event_images for select to anon,authenticated using (true);
drop policy if exists "Admin manages event photos" on public.event_images;
create policy "Admin manages event photos" on public.event_images for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Account owners can see/update their own safe profile fields; admins can review all profiles.
drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "Admins read all profiles" on public.profiles;
create policy "Admins read all profiles" on public.profiles for select to authenticated using (public.is_admin());
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "Admins update profiles" on public.profiles;
create policy "Admins update profiles" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Club members can submit pending promotion requests only after ID verification.
drop policy if exists "Verified clubs submit promotions" on public.promotions;
create policy "Verified clubs submit promotions" on public.promotions for insert to authenticated
with check (user_id = auth.uid() and status = 'pending' and payment_received = false and image_path like (auth.uid()::text || '/%') and public.is_verified_club());
drop policy if exists "Owners and admins read promotions" on public.promotions;
create policy "Owners and admins read promotions" on public.promotions for select to authenticated
using (user_id = auth.uid() or public.is_admin());
drop policy if exists "Admins update promotions" on public.promotions;
create policy "Admins update promotions" on public.promotions for update to authenticated
using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins delete promotions" on public.promotions;
create policy "Admins delete promotions" on public.promotions for delete to authenticated using (public.is_admin());

-- Storage buckets: event media is public; college IDs and pending banners stay private.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('event-media','event-media',true,5242880,array['image/jpeg','image/png','image/webp']),
 ('college-ids','college-ids',false,5242880,array['image/jpeg','image/png','image/webp']),
 ('promotion-banners','promotion-banners',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set name=excluded.name,public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Public reads for published posters/gallery. Writes require admin rights.
drop policy if exists "Public read event media" on storage.objects;
create policy "Public read event media" on storage.objects for select to anon,authenticated using (bucket_id = 'event-media');
drop policy if exists "Admins upload event media" on storage.objects;
create policy "Admins upload event media" on storage.objects for insert to authenticated with check (bucket_id = 'event-media' and public.is_admin());
drop policy if exists "Admins update event media" on storage.objects;
create policy "Admins update event media" on storage.objects for update to authenticated using (bucket_id = 'event-media' and public.is_admin()) with check (bucket_id = 'event-media' and public.is_admin());
drop policy if exists "Admins delete event media" on storage.objects;
create policy "Admins delete event media" on storage.objects for delete to authenticated using (bucket_id = 'event-media' and public.is_admin());

-- A user can upload/read/delete only their own college ID. Admins can review and remove it.
drop policy if exists "Owner uploads college ID" on storage.objects;
create policy "Owner uploads college ID" on storage.objects for insert to authenticated
with check (bucket_id = 'college-ids' and name = (auth.uid()::text || '/id-card'));
drop policy if exists "Owner or admin reads college ID" on storage.objects;
create policy "Owner or admin reads college ID" on storage.objects for select to authenticated
using (bucket_id = 'college-ids' and (name = (auth.uid()::text || '/id-card') or public.is_admin()));
drop policy if exists "Owner or admin deletes college ID" on storage.objects;
create policy "Owner or admin deletes college ID" on storage.objects for delete to authenticated
using (bucket_id = 'college-ids' and (name = (auth.uid()::text || '/id-card') or public.is_admin()));

-- Promotion banners are private until the admin approves them.
drop policy if exists "Verified club uploads promotion banner" on storage.objects;
create policy "Verified club uploads promotion banner" on storage.objects for insert to authenticated
with check (bucket_id = 'promotion-banners' and (storage.foldername(name))[1] = auth.uid()::text and public.is_verified_club());
drop policy if exists "Owner or admin reads promotion banner" on storage.objects;
create policy "Owner or admin reads promotion banner" on storage.objects for select to authenticated
using (bucket_id = 'promotion-banners' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
drop policy if exists "Owner or admin deletes promotion banner" on storage.objects;
create policy "Owner or admin deletes promotion banner" on storage.objects for delete to authenticated
using (bucket_id = 'promotion-banners' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
