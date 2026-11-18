-- Academias (white label): marca própria, painel do dono e professores convidados.
-- O dono cria a academia no app; os professores entram pelo link de convite;
-- o painel junta os alunos de todos os professores (só nome, telefone e datas de treino).

create table if not exists public.academias (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  nome text not null check (char_length(nome) between 2 and 60),
  cor text not null default '#5B82FF' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  logo text check (logo is null or (logo like 'data:image/%' and char_length(logo) <= 200000)),
  boas_vindas text check (boas_vindas is null or char_length(boas_vindas) <= 200),
  dono uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- código do link de convite de professor (não é público)
  codigo text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 12),
  -- licença: 30 dias de teste; depois quem vende o app estende esta data quando a academia paga
  ativa_ate timestamptz not null default now() + interval '30 days',
  criado_em timestamptz not null default now()
);
create unique index if not exists academias_um_dono on public.academias (dono);
alter table public.academias enable row level security;

drop policy if exists "dono vê a academia" on public.academias;
drop policy if exists "dono cria a academia" on public.academias;
drop policy if exists "dono edita a academia" on public.academias;
drop policy if exists "dono apaga a academia" on public.academias;
create policy "dono vê a academia" on public.academias for select to authenticated using (dono = auth.uid());
create policy "dono cria a academia" on public.academias for insert to authenticated with check (dono = auth.uid());
create policy "dono edita a academia" on public.academias for update to authenticated using (dono = auth.uid()) with check (dono = auth.uid());
create policy "dono apaga a academia" on public.academias for delete to authenticated using (dono = auth.uid());
-- o dono só mexe na aparência; licença, código e endereço ficam fora do alcance dele
revoke insert, update on public.academias from anon, authenticated;
grant insert (slug, nome, cor, logo, boas_vindas) on public.academias to authenticated;
grant update (nome, cor, logo, boas_vindas) on public.academias to authenticated;

create table if not exists public.academia_professores (
  academia_id uuid not null references public.academias (id) on delete cascade,
  professor uuid not null references auth.users (id) on delete cascade,
  nome text,
  entrou_em timestamptz not null default now(),
  primary key (academia_id, professor)
);
create unique index if not exists academia_professores_um on public.academia_professores (professor);
alter table public.academia_professores enable row level security;
drop policy if exists "dono e professor veem" on public.academia_professores;
drop policy if exists "dono remove, professor sai" on public.academia_professores;
create policy "dono e professor veem" on public.academia_professores for select to authenticated
  using (professor = auth.uid() or exists (select 1 from public.academias a where a.id = academia_id and a.dono = auth.uid()));
create policy "dono remove, professor sai" on public.academia_professores for delete to authenticated
  using (professor = auth.uid() or exists (select 1 from public.academias a where a.id = academia_id and a.dono = auth.uid()));
revoke insert, update on public.academia_professores from anon, authenticated;

/* ---------- Funções ---------- */

-- Marca pública da academia (tela de entrada do link ?a=slug). Sem código nem dono.
create or replace function public.marca_academia(p_slug text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'slug', slug, 'nome', nome, 'cor', cor, 'logo', logo, 'boasVindas', boas_vindas)
  from academias where slug = lower(p_slug)
$$;
grant execute on function public.marca_academia(text) to anon, authenticated;

-- Academia da conta: como dono (com código e licença) ou como professor (só a marca)
create or replace function public.minha_academia() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select json_build_object('id', id, 'slug', slug, 'nome', nome, 'cor', cor, 'logo', logo, 'boasVindas', boas_vindas,
      'papel', 'dono', 'codigo', codigo, 'ativaAte', ativa_ate) from academias where dono = auth.uid()),
    (select json_build_object('id', a.id, 'slug', a.slug, 'nome', a.nome, 'cor', a.cor, 'logo', a.logo, 'boasVindas', a.boas_vindas, 'papel', 'professor')
      from academia_professores p join academias a on a.id = p.academia_id where p.professor = auth.uid())
  )
$$;

-- Professor aceita o convite (sai de outra academia, se estava)
create or replace function public.entrar_academia(p_codigo text, p_nome text default null) returns json
language plpgsql security definer set search_path = public as $$
declare a academias;
begin
  if auth.uid() is null then raise exception 'SEM_LOGIN' using errcode = 'P0001'; end if;
  select * into a from academias where codigo = p_codigo;
  if not found then raise exception 'CONVITE_INVALIDO' using errcode = 'P0001'; end if;
  if a.dono = auth.uid() then raise exception 'E_DONO' using errcode = 'P0001'; end if;
  delete from academia_professores where professor = auth.uid() and academia_id <> a.id;
  insert into academia_professores (academia_id, professor, nome) values (a.id, auth.uid(), left(nullif(trim(p_nome), ''), 60))
    on conflict (academia_id, professor) do update set nome = coalesce(excluded.nome, academia_professores.nome);
  return json_build_object('id', a.id, 'slug', a.slug, 'nome', a.nome, 'cor', a.cor, 'logo', a.logo, 'boasVindas', a.boas_vindas, 'papel', 'professor');
end $$;

-- Dono troca o código do convite (o link antigo para de funcionar)
create or replace function public.novo_convite_professor() returns text
language sql security definer set search_path = public as $$
  update academias set codigo = substr(md5(random()::text || clock_timestamp()::text), 1, 12)
  where dono = auth.uid() returning codigo
$$;

-- Painel do dono: professores e alunos deles com as datas de treino dos últimos 120 dias.
-- Não inclui cargas, fichas, dieta, medidas nem diário.
create or replace function public.painel_academia() returns json
language sql stable security definer set search_path = public as $$
  with a as (select * from academias where dono = auth.uid()),
  profs as (
    select p.professor as uid, coalesce(nullif(p.nome, ''), nullif(pf.nome, ''), split_part(pf.email, '@', 1)) as nome, p.entrou_em
    from academia_professores p join a on a.id = p.academia_id left join perfis pf on pf.id = p.professor
  ),
  limite as (select (extract(epoch from now() - interval '120 days') * 1000)::bigint as ms)
  select case when not exists (select 1 from a) then null else json_build_object(
    'professores', (select coalesce(json_agg(json_build_object('uid', uid, 'nome', nome, 'entrouEm', entrou_em) order by nome), '[]'::json) from profs),
    'alunos', (select coalesce(json_agg(json_build_object(
        'id', x.id, 'prof', x.personal_id, 'nome', x.nome, 'tel', x.telefone, 'criado', x.criado_em,
        't', (select coalesce(json_agg(t order by t), '[]'::json) from (
               select (s->>'inicio')::bigint as t from jsonb_array_elements(x.sessoes) s where jsonb_typeof(s->'inicio') = 'number'
               union all
               select (c->>1)::bigint from jsonb_array_elements(x.cardios) c where jsonb_typeof(c) = 'array' and jsonb_typeof(c->1) = 'number'
             ) d, limite where d.t > limite.ms),
        'ult', (select max(t) from (
               select (s->>'inicio')::bigint as t from jsonb_array_elements(x.sessoes) s where jsonb_typeof(s->'inicio') = 'number'
               union all
               select (c->>1)::bigint from jsonb_array_elements(x.cardios) c where jsonb_typeof(c) = 'array' and jsonb_typeof(c->1) = 'number'
             ) d2)
      )), '[]'::json) from alunos x join profs on x.personal_id = profs.uid where not x.apagado)
  ) end
$$;

-- Professores e o dono de academia com licença em dia têm alunos ilimitados (a academia paga)
create or replace function public.plano(uid uuid default auth.uid()) returns text
language sql stable security definer set search_path = public as $$
  select case when exists (
    select 1 from assinaturas a join perfis p on a.email = p.email
    where p.id = uid and a.status in ('ativa', 'cancelada') and (a.valida_ate is null or a.valida_ate > now())
  ) or exists (
    select 1 from academias ac where ac.ativa_ate > now() and (ac.dono = uid
      or exists (select 1 from academia_professores ap where ap.academia_id = ac.id and ap.professor = uid))
  ) then 'pro' else 'gratis' end
$$;
