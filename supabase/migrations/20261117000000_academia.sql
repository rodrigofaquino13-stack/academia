-- Academia: personal trainers, alunos sincronizados, assinatura Pro (Hotmart) e uso da IA.

-- Valores de negócio ajustáveis sem mexer no código
create table public.config (chave text primary key, valor text not null);
insert into public.config values
  ('limite_alunos_gratis', '3'),
  ('ia_dia_anonimo', '5'),
  ('ia_dia_gratis', '10'),
  ('ia_dia_pro', '60');

-- Perfil do personal (criado automaticamente no primeiro login)
create table public.perfis (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  pid text,               -- id do personal usado nos links enviados aos alunos
  nome text,
  cor text,
  telefone text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index perfis_email on public.perfis (email);

-- Assinaturas vindas da Hotmart, ligadas pelo e-mail do comprador
create table public.assinaturas (
  email text primary key,
  status text not null check (status in ('ativa', 'cancelada', 'inativa')),
  valida_ate timestamptz,
  assinante text,
  produto text,
  atualizado_em timestamptz not null default now()
);

-- Registro bruto dos avisos da Hotmart (auditoria e para não processar duas vezes)
create table public.hotmart_eventos (
  id text primary key,
  evento text not null,
  email text,
  recebido_em timestamptz not null default now(),
  payload jsonb not null
);

-- Alunos de cada personal. Datas em milissegundos do aparelho (a edição mais recente vence).
create table public.alunos (
  personal_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  nome text not null default '',
  telefone text,
  fichas jsonb not null default '[]',
  sessoes jsonb not null default '[]',
  criado_em bigint,
  enviado_em bigint,
  relatorio_em bigint,
  atualizado_em bigint not null,
  apagado boolean not null default false,
  primary key (personal_id, id)
);

-- Contador diário de leituras por foto
create table public.ia_uso (
  chave text not null,
  dia date not null default current_date,
  n int not null default 0,
  primary key (chave, dia)
);

/* ---------- Funções ---------- */
create or replace function public.config_int(p text, padrao int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select valor::int from config where chave = p), padrao)
$$;

-- 'pro' enquanto houver assinatura ativa (ou cancelada, até o fim do período pago)
create or replace function public.plano(uid uuid default auth.uid()) returns text
language sql stable security definer set search_path = public as $$
  select case when exists (
    select 1 from assinaturas a join perfis p on a.email = p.email
    where p.id = uid and a.status in ('ativa', 'cancelada') and (a.valida_ate is null or a.valida_ate > now())
  ) then 'pro' else 'gratis' end
$$;

create or replace function public.minha_conta() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'email', p.email,
    'plano', plano(p.id),
    'status', a.status,
    'valida_ate', a.valida_ate,
    'limite_alunos', case when plano(p.id) = 'pro' then null else config_int('limite_alunos_gratis', 3) end,
    'ia_dia', case when plano(p.id) = 'pro' then config_int('ia_dia_pro', 60) else config_int('ia_dia_gratis', 10) end,
    'alunos', (select count(*) from alunos x where x.personal_id = p.id and not x.apagado)
  )
  from perfis p left join assinaturas a on a.email = p.email
  where p.id = auth.uid()
$$;

create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into perfis (id, email) values (new.id, lower(new.email)) on conflict (id) do nothing;
  return new;
end $$;
create trigger ao_criar_usuario after insert on auth.users for each row execute function public.novo_usuario();

-- Plano grátis: no máximo N alunos ativos. Alunos que já existem continuam editáveis.
create or replace function public.checar_limite_alunos() returns trigger
language plpgsql security definer set search_path = public as $$
declare lim int; qtd int;
begin
  -- gravação em nome de outro: deixa a regra de acesso (RLS) recusar
  if auth.uid() is not null and new.personal_id <> auth.uid() then return new; end if;
  if new.apagado then return new; end if;
  if exists (select 1 from alunos where personal_id = new.personal_id and id = new.id and not apagado) then return new; end if;
  if plano(new.personal_id) = 'pro' then return new; end if;
  lim := config_int('limite_alunos_gratis', 3);
  select count(*) into qtd from alunos where personal_id = new.personal_id and not apagado and id <> new.id;
  if qtd >= lim then
    raise exception 'LIMITE_PLANO' using errcode = 'P0001', hint = lim::text;
  end if;
  return new;
end $$;
create trigger limite_alunos before insert or update on public.alunos for each row execute function public.checar_limite_alunos();

-- Consome uma leitura da IA; devolve quantas já foram usadas hoje ou -1 se passou do limite
create or replace function public.consumir_ia(p_chave text, p_limite int) returns int
language plpgsql security definer set search_path = public as $$
declare usado int;
begin
  insert into ia_uso (chave, dia, n) values (p_chave, current_date, 1)
  on conflict (chave, dia) do update set n = ia_uso.n + 1 where ia_uso.n < p_limite
  returning n into usado;
  return coalesce(usado, -1);
end $$;

/* ---------- Segurança (RLS) ---------- */
alter table public.config enable row level security;
alter table public.perfis enable row level security;
alter table public.assinaturas enable row level security;
alter table public.hotmart_eventos enable row level security;
alter table public.alunos enable row level security;
alter table public.ia_uso enable row level security;

create policy "ler config" on public.config for select to authenticated using (true);
create policy "ver o próprio perfil" on public.perfis for select to authenticated using (id = auth.uid());
create policy "editar o próprio perfil" on public.perfis for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "ver a própria assinatura" on public.assinaturas for select to authenticated
  using (email = (select email from public.perfis where id = auth.uid()));
create policy "alunos do próprio personal" on public.alunos for all to authenticated
  using (personal_id = auth.uid()) with check (personal_id = auth.uid());

-- O e-mail do perfil não pode ser trocado pelo app (é a ligação com a compra)
revoke update on public.perfis from authenticated;
grant update (pid, nome, cor, telefone, atualizado_em) on public.perfis to authenticated;

revoke execute on function public.consumir_ia(text, int) from public, anon, authenticated;
revoke execute on function public.checar_limite_alunos() from public, anon, authenticated;
revoke execute on function public.novo_usuario() from public, anon, authenticated;
grant execute on function public.minha_conta() to authenticated;
grant execute on function public.plano(uuid) to authenticated;
