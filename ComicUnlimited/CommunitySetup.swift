import Foundation

// El texto que arma la base de datos de la comunidad en Supabase (se pega una sola vez en el "SQL Editor").
// Crea tres tablas (perfiles, amigos y comentarios) y las reglas de privacidad:
// - cada uno solo puede crear, cambiar o borrar lo suyo;
// - los comentarios y puntajes los ven solo vos y tus amigos (los que se agregaron mutuamente);
// - los nombres de usuario los ve cualquiera que haya entrado (para poder agregarse).

enum CommunitySetup {
    static let sql = """
    -- Cómic Unlimited: comunidad (pegar todo en Supabase → SQL Editor → Run)

    create table if not exists public.profiles (
      id uuid primary key references auth.users(id) on delete cascade,
      username text unique not null check (username ~ '^[a-z0-9_]{3,24}$'),
      created_at timestamptz not null default now()
    );

    create table if not exists public.follows (
      follower uuid not null references public.profiles(id) on delete cascade,
      followee uuid not null references public.profiles(id) on delete cascade,
      created_at timestamptz not null default now(),
      primary key (follower, followee),
      check (follower <> followee)
    );

    create table if not exists public.reviews (
      user_id uuid not null references public.profiles(id) on delete cascade,
      comic_key text not null,
      cv_id integer,
      metron_id integer,
      kind text,
      title text not null,
      cover_url text,
      rating integer check (rating between 1 and 5),
      thumbs integer check (thumbs in (-1, 1, 2)),
      comment text check (char_length(comment) <= 4000),
      updated_at timestamptz not null default now(),
      primary key (user_id, comic_key)
    );

    create index if not exists reviews_comic_key on public.reviews (comic_key);
    create index if not exists reviews_updated on public.reviews (updated_at desc);

    alter table public.profiles enable row level security;
    alter table public.follows enable row level security;
    alter table public.reviews enable row level security;

    -- ¿Son amigos? (se agregaron los dos)
    create or replace function public.are_friends(a uuid, b uuid) returns boolean
    language sql stable security definer set search_path = public as $$
      select exists (select 1 from follows where follower = a and followee = b)
         and exists (select 1 from follows where follower = b and followee = a);
    $$;

    drop policy if exists "perfiles: ver" on public.profiles;
    drop policy if exists "perfiles: crear el mío" on public.profiles;
    drop policy if exists "perfiles: cambiar el mío" on public.profiles;
    create policy "perfiles: ver" on public.profiles for select to authenticated using (true);
    create policy "perfiles: crear el mío" on public.profiles for insert to authenticated with check (id = auth.uid());
    create policy "perfiles: cambiar el mío" on public.profiles for update to authenticated using (id = auth.uid());

    drop policy if exists "amigos: ver los míos" on public.follows;
    drop policy if exists "amigos: agregar" on public.follows;
    drop policy if exists "amigos: sacar" on public.follows;
    create policy "amigos: ver los míos" on public.follows for select to authenticated
      using (follower = auth.uid() or followee = auth.uid());
    create policy "amigos: agregar" on public.follows for insert to authenticated with check (follower = auth.uid());
    create policy "amigos: sacar" on public.follows for delete to authenticated using (follower = auth.uid());

    drop policy if exists "comentarios: ver los míos y de amigos" on public.reviews;
    drop policy if exists "comentarios: escribir los míos" on public.reviews;
    drop policy if exists "comentarios: cambiar los míos" on public.reviews;
    drop policy if exists "comentarios: borrar los míos" on public.reviews;
    create policy "comentarios: ver los míos y de amigos" on public.reviews for select to authenticated
      using (user_id = auth.uid() or public.are_friends(auth.uid(), user_id));
    create policy "comentarios: escribir los míos" on public.reviews for insert to authenticated with check (user_id = auth.uid());
    create policy "comentarios: cambiar los míos" on public.reviews for update to authenticated using (user_id = auth.uid());
    create policy "comentarios: borrar los míos" on public.reviews for delete to authenticated using (user_id = auth.uid());
    """
}
