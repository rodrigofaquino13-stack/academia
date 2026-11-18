-- Acompanhamento ao vivo: o aluno autoriza o personal a ver os dados dele (treinos, cardio, peso, diário).
-- O convite vai no link do treino; o aluno aceita no app; o personal passa a ler a linha do aluno em "dados".

create table if not exists public.convites (
  codigo text primary key,
  personal_id uuid not null references auth.users (id) on delete cascade,
  aluno_id text not null,           -- id do aluno na lista do personal
  personal_nome text,
  criado_em timestamptz not null default now()
);
alter table public.convites enable row level security;
create policy "convites do personal" on public.convites for all to authenticated
  using (personal_id = auth.uid()) with check (personal_id = auth.uid());

create table if not exists public.vinculos (
  personal_id uuid not null references auth.users (id) on delete cascade,
  aluno_uid uuid not null references auth.users (id) on delete cascade,
  aluno_id text not null,
  personal_nome text,
  criado_em timestamptz not null default now(),
  primary key (personal_id, aluno_uid)
);
alter table public.vinculos enable row level security;
create policy "vínculo visível às duas partes" on public.vinculos for select to authenticated
  using (personal_id = auth.uid() or aluno_uid = auth.uid());
create policy "qualquer parte encerra o vínculo" on public.vinculos for delete to authenticated
  using (personal_id = auth.uid() or aluno_uid = auth.uid());

-- O personal lê só o necessário de quem o autorizou: treinos, cardio, medidas, academia, dieta e o resumo do diário.
-- Anotações e itens do diário (remédios, suplementos, hábitos) nunca saem da conta do aluno.
create or replace function public.dados_alunos() returns table (aluno_uid uuid, atualizado_em bigint, estado jsonb)
language sql security definer stable set search_path = public as $$
  select d.user_id, d.atualizado_em, jsonb_build_object(
    'sessoes', coalesce(d.estado->'sessoes', '[]'::jsonb),
    'cardios', coalesce(d.estado->'cardios', '[]'::jsonb),
    'medidas', coalesce(d.estado->'medidas', '[]'::jsonb),
    'academia', d.estado->'academia',
    'dieta', d.estado->'dieta',
    'diario', (select coalesce(jsonb_object_agg(k, v - 'nota' - 'itens'), '{}'::jsonb)
               from jsonb_each(case when jsonb_typeof(d.estado->'diario') = 'object' then d.estado->'diario' else '{}'::jsonb end) as e(k, v))
  )
  from public.dados d
  join public.vinculos v on v.aluno_uid = d.user_id and v.personal_id = auth.uid()
$$;
revoke execute on function public.dados_alunos() from public, anon;
grant execute on function public.dados_alunos() to authenticated;

-- Aluno aceita o convite (o código vale 30 dias e uma vez)
create or replace function public.aceitar_convite(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare c public.convites;
begin
  if auth.uid() is null then raise exception 'não autenticado'; end if;
  select * into c from public.convites where codigo = p_codigo and criado_em > now() - interval '30 days';
  if not found then raise exception 'convite inválido ou vencido'; end if;
  if c.personal_id = auth.uid() then raise exception 'convite do próprio personal'; end if;
  insert into public.vinculos (personal_id, aluno_uid, aluno_id, personal_nome)
    values (c.personal_id, auth.uid(), c.aluno_id, c.personal_nome)
    on conflict (personal_id, aluno_uid) do update set aluno_id = excluded.aluno_id, personal_nome = excluded.personal_nome;
  delete from public.convites where codigo = p_codigo;
  return json_build_object('personal_id', c.personal_id, 'aluno_id', c.aluno_id, 'personal_nome', c.personal_nome);
end $$;
revoke execute on function public.aceitar_convite(text) from public, anon;
grant execute on function public.aceitar_convite(text) to authenticated;

-- Treino enviado pelo app (sem precisar de link): o aluno vê ao abrir e aceita
create table if not exists public.envios (
  id uuid primary key default gen_random_uuid(),
  personal_id uuid not null references auth.users (id) on delete cascade,
  aluno_uid uuid not null references auth.users (id) on delete cascade,
  pacote jsonb not null,
  criado_em timestamptz not null default now()
);
alter table public.envios enable row level security;
create policy "personal envia a aluno vinculado" on public.envios for insert to authenticated
  with check (personal_id = auth.uid() and exists (select 1 from public.vinculos v where v.personal_id = auth.uid() and v.aluno_uid = envios.aluno_uid));
create policy "envio visível às duas partes" on public.envios for select to authenticated
  using (personal_id = auth.uid() or aluno_uid = auth.uid());
create policy "envio apagado por qualquer parte" on public.envios for delete to authenticated
  using (personal_id = auth.uid() or aluno_uid = auth.uid());

-- Desafio do mês do personal, visto pelos alunos vinculados
create table if not exists public.desafios (
  personal_id uuid primary key references auth.users (id) on delete cascade,
  mes text not null,                -- 'AAAA-MM'
  meta int not null check (meta between 1 and 31),
  titulo text,
  atualizado_em timestamptz not null default now()
);
alter table public.desafios enable row level security;
create policy "personal gerencia o desafio" on public.desafios for all to authenticated
  using (personal_id = auth.uid()) with check (personal_id = auth.uid());
create policy "aluno vinculado vê o desafio" on public.desafios for select to authenticated
  using (exists (select 1 from public.vinculos v where v.aluno_uid = auth.uid() and v.personal_id = desafios.personal_id));
