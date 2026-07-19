create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'Información',
  description text not null,
  event_date date,
  event_time time,
  location text,
  expires_at date,
  pinned boolean not null default false,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

alter table public.announcements enable row level security;

create policy "Public can read published announcements"
on public.announcements for select
using (published = true and (expires_at is null or expires_at >= current_date));

create policy "Authenticated users can manage announcements"
on public.announcements for all
to authenticated
using (auth.uid() = created_by)
with check (auth.uid() = created_by);
