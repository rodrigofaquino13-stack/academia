-- Cadastro de alunos da academia.
-- Antes: cada aluno só existia na lista de um personal. Agora a academia tem a própria lista:
--   * o aluno se cadastra sozinho pelo link ou QR da academia e escolhe o personal;
--   * o dono cadastra, importa da planilha, troca de personal e desativa quem cancelou;
--   * os alunos que os personais cadastram no app entram na lista sozinhos;
--   * o dono que também dá treino aparece como personal da própria academia.
-- Ligar um aluno a um personal cria a linha dele na lista do personal (tabela alunos), que chega
-- ao app do personal na próxima sincronização. Se o aluno já tem conta, liga também o acompanhamento.
-- Pode rodar mais de uma vez.

create table if not exists public.academia_alunos (
  id uuid primary key default gen_random_uuid(),
  academia_id uuid not null references public.academias (id) on delete cascade,
  aluno_uid uuid references auth.users (id) on delete set null,      -- conta do aluno, quando ele entra pelo link da academia
  nome text not null check (char_length(nome) between 1 and 60),
  telefone text check (telefone is null or char_length(telefone) <= 30),
  personal_id uuid references auth.users (id) on delete set null,
  aluno_id text,                                                      -- id do aluno na lista do personal (tabela alunos)
  ativo boolean not null default true,
  origem text not null default 'dono' check (origem in ('dono', 'planilha', 'qr', 'personal')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists academia_alunos_academia on public.academia_alunos (academia_id);
create unique index if not exists academia_alunos_conta on public.academia_alunos (academia_id, aluno_uid) where aluno_uid is not null;
create unique index if not exists academia_alunos_personal on public.academia_alunos (personal_id, aluno_id) where aluno_id is not null;
alter table public.academia_alunos enable row level security;
-- sem políticas: só as funções abaixo leem e gravam
revoke all on public.academia_alunos from anon, authenticated;

/* ---------- Apoio (não ficam disponíveis para o app) ---------- */

create or replace function public.agora_ms() returns bigint
language sql volatile as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

-- Telefone só com os dígitos, sem o 55 do Brasil: "(31) 99999-0000" e "+55 31 999990000" viram o mesmo
create or replace function public.tel_chave(t text) returns text
language sql immutable as $$
  select case when d = '' then null when length(d) >= 12 and d like '55%' then substr(d, 3) else d end
  from (select regexp_replace(coalesce(t, ''), '\D', '', 'g') as d) x
$$;

-- Quem pode ser personal de alunos da academia: os personais convidados e o próprio dono
create or replace function public.equipe_academia(p_academia uuid) returns table (uid uuid, nome text, dono boolean)
language sql stable security definer set search_path = public as $$
  select a.dono, coalesce(nullif(pf.nome, ''), split_part(pf.email, '@', 1), 'Dono'), true
    from academias a left join perfis pf on pf.id = a.dono where a.id = p_academia
  union all
  select p.professor, coalesce(nullif(p.nome, ''), nullif(pf.nome, ''), split_part(pf.email, '@', 1)), false
    from academia_professores p left join perfis pf on pf.id = p.professor where p.academia_id = p_academia
$$;

-- Cria (ou devolve) a linha do aluno na lista do personal e, se o aluno tem conta, liga o acompanhamento
create or replace function public.ligar_personal(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r academia_alunos; agora bigint := agora_ms(); nome_p text;
begin
  select * into r from academia_alunos where id = p_id;
  if not found or r.personal_id is null or not r.ativo then return; end if;
  if r.aluno_id is null then
    r.aluno_id := 'ac-' || r.id::text;
    update academia_alunos set aluno_id = r.aluno_id where id = r.id;
  end if;
  insert into alunos (personal_id, id, nome, telefone, criado_em, atualizado_em)
    values (r.personal_id, r.aluno_id, r.nome, r.telefone, agora, agora)
    on conflict (personal_id, id) do update set nome = excluded.nome, telefone = coalesce(excluded.telefone, alunos.telefone),
      apagado = false, atualizado_em = greatest(alunos.atualizado_em + 1, excluded.atualizado_em);
  if r.aluno_uid is not null and r.aluno_uid <> r.personal_id then
    select e.nome into nome_p from equipe_academia(r.academia_id) e where e.uid = r.personal_id;
    insert into vinculos (personal_id, aluno_uid, aluno_id, personal_nome)
      values (r.personal_id, r.aluno_uid, r.aluno_id, nome_p)
      on conflict (personal_id, aluno_uid) do update set aluno_id = excluded.aluno_id, personal_nome = excluded.personal_nome;
  end if;
end $$;

-- Tira o aluno da lista do personal (as fichas ficam guardadas para o caso de voltar) e desliga o acompanhamento
create or replace function public.desligar_personal(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r academia_alunos;
begin
  select * into r from academia_alunos where id = p_id;
  if not found or r.personal_id is null then return; end if;
  if r.aluno_id is not null then
    update alunos set apagado = true, atualizado_em = greatest(atualizado_em + 1, agora_ms())
      where personal_id = r.personal_id and id = r.aluno_id;
  end if;
  if r.aluno_uid is not null then delete from vinculos where personal_id = r.personal_id and aluno_uid = r.aluno_uid; end if;
end $$;

-- Academia do dono que está chamando
create or replace function public.academia_do_dono() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare a uuid;
begin
  if auth.uid() is null then raise exception 'SEM_LOGIN' using errcode = 'P0001'; end if;
  select id into a from academias where dono = auth.uid();
  if a is null then raise exception 'SEM_ACADEMIA' using errcode = 'P0001'; end if;
  return a;
end $$;

revoke execute on function public.equipe_academia(uuid), public.ligar_personal(uuid), public.desligar_personal(uuid),
  public.academia_do_dono(), public.agora_ms() from public, anon, authenticated;

/* ---------- Aluno: autocadastro pelo link ou QR da academia ---------- */

-- Personais que o aluno pode escolher (só nomes). O dono entra se já dá treino a alguém.
create or replace function public.personais_academia(p_slug text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('uid', e.uid, 'nome', e.nome) order by e.dono, e.nome), '[]'::json)
  from academias a cross join lateral equipe_academia(a.id) e
  where a.slug = lower(p_slug)
    and (not e.dono or exists (select 1 from alunos x where x.personal_id = e.uid and not x.apagado)
                     or exists (select 1 from academia_alunos y where y.academia_id = a.id and y.personal_id = e.uid and y.ativo))
$$;

-- Cadastro do próprio aluno. Se o dono já tinha cadastrado o mesmo telefone, junta com esse cadastro.
create or replace function public.entrar_como_aluno(p_slug text, p_nome text, p_telefone text, p_personal uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare a academias; r academia_alunos; nome_p text; tel text := nullif(trim(coalesce(p_telefone, '')), '');
begin
  if auth.uid() is null then raise exception 'SEM_LOGIN' using errcode = 'P0001'; end if;
  if char_length(trim(coalesce(p_nome, ''))) < 2 then raise exception 'NOME' using errcode = 'P0001'; end if;
  select * into a from academias where slug = lower(p_slug);
  if not found then raise exception 'ACADEMIA' using errcode = 'P0001'; end if;
  if a.dono = auth.uid() or exists (select 1 from academia_professores where academia_id = a.id and professor = auth.uid()) then
    raise exception 'E_EQUIPE' using errcode = 'P0001';
  end if;
  if p_personal is not null and not exists (select 1 from equipe_academia(a.id) e where e.uid = p_personal) then
    raise exception 'PERSONAL' using errcode = 'P0001';
  end if;

  select * into r from academia_alunos where academia_id = a.id and aluno_uid = auth.uid();
  if not found and tel_chave(tel) is not null then
    select * into r from academia_alunos
      where academia_id = a.id and aluno_uid is null and tel_chave(telefone) = tel_chave(tel)
      order by ativo desc, criado_em limit 1;
  end if;

  if r.id is null then
    insert into academia_alunos (academia_id, aluno_uid, nome, telefone, personal_id, origem)
      values (a.id, auth.uid(), left(trim(p_nome), 60), left(tel, 30), p_personal, 'qr') returning * into r;
  else
    -- trocou de personal: sai da lista do anterior
    if p_personal is not null and r.personal_id is distinct from p_personal then
      perform desligar_personal(r.id);
      update academia_alunos set personal_id = p_personal, aluno_id = null where id = r.id;
    end if;
    update academia_alunos set aluno_uid = auth.uid(), nome = left(trim(p_nome), 60), telefone = coalesce(left(tel, 30), telefone),
      ativo = true, atualizado_em = now() where id = r.id returning * into r;
  end if;
  perform ligar_personal(r.id);
  select * into r from academia_alunos where id = r.id;
  select e.nome into nome_p from equipe_academia(a.id) e where e.uid = r.personal_id;
  return json_build_object('id', r.id, 'academia', a.nome, 'personalId', r.personal_id, 'personalNome', nome_p, 'alunoId', r.aluno_id,
    'personalPid', (select pf.pid from perfis pf where pf.id = r.personal_id), 'personalTel', (select pf.telefone from perfis pf where pf.id = r.personal_id));
end $$;

-- Cadastro do aluno nesta academia (para o app saber se já pediu)
create or replace function public.minha_matricula(p_slug text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', r.id, 'ativo', r.ativo, 'personalId', r.personal_id, 'alunoId', r.aluno_id,
    'personalNome', (select e.nome from equipe_academia(a.id) e where e.uid = r.personal_id))
  from academias a join academia_alunos r on r.academia_id = a.id and r.aluno_uid = auth.uid()
  where a.slug = lower(p_slug)
$$;

/* ---------- Dono: cadastro e manutenção ---------- */

create or replace function public.aluno_academia_salvar(p_id uuid, p_nome text, p_telefone text, p_personal uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare ac uuid := academia_do_dono(); r academia_alunos; tel text := nullif(trim(coalesce(p_telefone, '')), '');
begin
  if char_length(trim(coalesce(p_nome, ''))) < 1 then raise exception 'NOME' using errcode = 'P0001'; end if;
  if p_personal is not null and not exists (select 1 from equipe_academia(ac) e where e.uid = p_personal) then
    raise exception 'PERSONAL' using errcode = 'P0001';
  end if;
  if p_id is null then
    insert into academia_alunos (academia_id, nome, telefone, personal_id, origem)
      values (ac, left(trim(p_nome), 60), left(tel, 30), p_personal, 'dono') returning * into r;
  else
    select * into r from academia_alunos where id = p_id and academia_id = ac;
    if not found then raise exception 'ALUNO' using errcode = 'P0001'; end if;
    if r.personal_id is distinct from p_personal then
      perform desligar_personal(r.id);
      update academia_alunos set personal_id = p_personal, aluno_id = null where id = r.id;
    end if;
    update academia_alunos set nome = left(trim(p_nome), 60), telefone = left(tel, 30), atualizado_em = now()
      where id = r.id returning * into r;
    -- nome e telefone novos também na lista do personal
    if r.personal_id is not null and r.aluno_id is not null then
      update alunos set nome = r.nome, telefone = r.telefone, atualizado_em = greatest(atualizado_em + 1, agora_ms())
        where personal_id = r.personal_id and id = r.aluno_id and not apagado;
    end if;
  end if;
  perform ligar_personal(r.id);
  return r.id;
end $$;

-- Desativar (cancelou a matrícula) tira o aluno da lista do personal; reativar devolve, com as fichas
create or replace function public.aluno_academia_ativo(p_id uuid, p_ativo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare ac uuid := academia_do_dono();
begin
  if not exists (select 1 from academia_alunos where id = p_id and academia_id = ac) then raise exception 'ALUNO' using errcode = 'P0001'; end if;
  if p_ativo then
    update academia_alunos set ativo = true, atualizado_em = now() where id = p_id;
    perform ligar_personal(p_id);
  else
    perform desligar_personal(p_id);
    update academia_alunos set ativo = false, atualizado_em = now() where id = p_id;
  end if;
end $$;

-- Importação da planilha: [{nome, telefone, personal}] onde personal é o nome ou o e-mail.
-- Telefone que já existe atualiza o cadastro em vez de duplicar.
create or replace function public.alunos_academia_importar(p_linhas jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare ac uuid := academia_do_dono(); l jsonb; nome text; tel text; ref text; pid uuid; r academia_alunos;
  criados int := 0; atualizados int := 0; ignorados int := 0; sem_personal int := 0; novo uuid;
begin
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) > 3000 then raise exception 'PLANILHA' using errcode = 'P0001'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    nome := left(trim(coalesce(l->>'nome', '')), 60);
    tel := left(nullif(trim(coalesce(l->>'telefone', '')), ''), 30);
    ref := lower(trim(coalesce(l->>'personal', '')));
    if char_length(nome) < 2 then ignorados := ignorados + 1; continue; end if;
    pid := null;
    if ref <> '' then
      select e.uid into pid from equipe_academia(ac) e left join perfis pf on pf.id = e.uid
        where lower(pf.email) = ref or lower(e.nome) = ref limit 1;
      if pid is null then  -- só o primeiro nome, se não houver dois iguais
        select min(e.uid::text)::uuid into pid from equipe_academia(ac) e
          where lower(split_part(e.nome, ' ', 1)) = split_part(ref, ' ', 1)
          having count(*) = 1;
      end if;
      if pid is null then sem_personal := sem_personal + 1; end if;
    end if;
    r := null;
    if tel_chave(tel) is not null then
      select * into r from academia_alunos where academia_id = ac and tel_chave(telefone) = tel_chave(tel) order by ativo desc, criado_em limit 1;
    end if;
    if r.id is not null then
      if pid is not null and r.personal_id is null then
        update academia_alunos set personal_id = pid, aluno_id = null where id = r.id;
      end if;
      update academia_alunos set ativo = true, atualizado_em = now() where id = r.id;
      perform ligar_personal(r.id);
      atualizados := atualizados + 1;
    else
      insert into academia_alunos (academia_id, nome, telefone, personal_id, origem)
        values (ac, nome, tel, pid, 'planilha') returning id into novo;
      perform ligar_personal(novo);
      criados := criados + 1;
    end if;
  end loop;
  return json_build_object('criados', criados, 'atualizados', atualizados, 'ignorados', ignorados, 'semPersonal', sem_personal);
end $$;

/* ---------- Painel do dono, agora a partir da lista da academia ---------- */
-- Junta à lista os alunos que os personais cadastraram no app, e devolve as datas de treino dos últimos 120 dias.
-- Datas vêm da conta do aluno (quem se cadastrou pelo link) ou do que o personal recebeu dele.
-- Não inclui cargas, fichas, dieta, medidas nem diário.
drop function if exists public.painel_academia();
create or replace function public.painel_academia() returns json
language plpgsql security definer set search_path = public as $$
declare ac uuid; limite bigint := ((extract(epoch from now() - interval '120 days')) * 1000)::bigint;
begin
  select id into ac from academias where dono = auth.uid();
  if ac is null then return null; end if;

  -- alunos cadastrados pelos personais (e pelo dono no modo personal) entram na lista
  insert into academia_alunos (academia_id, nome, telefone, personal_id, aluno_id, origem)
    select ac, coalesce(nullif(left(trim(x.nome), 60), ''), 'Aluno'), left(x.telefone, 30), x.personal_id, x.id, 'personal'
    from alunos x join equipe_academia(ac) e on e.uid = x.personal_id
    where not x.apagado
    on conflict do nothing;

  -- o personal apagou o aluno no app: se foi ele que cadastrou, sai da lista; senão fica sem personal
  update academia_alunos y set ativo = false, atualizado_em = now()
    from alunos x where y.academia_id = ac and y.ativo and y.origem = 'personal'
      and x.personal_id = y.personal_id and x.id = y.aluno_id and x.apagado;
  update academia_alunos y set personal_id = null, aluno_id = null, atualizado_em = now()
    from alunos x where y.academia_id = ac and y.ativo and y.origem <> 'personal'
      and x.personal_id = y.personal_id and x.id = y.aluno_id and x.apagado;

  return json_build_object(
    'professores', (select coalesce(json_agg(json_build_object('uid', e.uid, 'nome', e.nome, 'dono', e.dono) order by e.dono, e.nome), '[]'::json)
                    from equipe_academia(ac) e),
    'alunos', (select coalesce(json_agg(json_build_object(
        'id', y.id, 'prof', y.personal_id, 'nome', y.nome, 'tel', y.telefone,
        'criado', (extract(epoch from y.criado_em) * 1000)::bigint,
        'ativo', y.ativo, 'conta', y.aluno_uid is not null, 'origem', y.origem,
        'fichas', coalesce(jsonb_array_length(x.fichas), 0),
        't', d.t, 'ult', d.ult
      ) order by y.nome), '[]'::json)
      from academia_alunos y
      left join alunos x on x.personal_id = y.personal_id and x.id = y.aluno_id and not x.apagado
      left join dados dd on dd.user_id = y.aluno_uid
      cross join lateral (
        select coalesce(json_agg(distinct z.t order by z.t) filter (where z.t > limite), '[]'::json) as t, max(z.t) as ult
        from (
          select (s->>'inicio')::bigint from jsonb_array_elements(coalesce(x.sessoes, '[]')) s where jsonb_typeof(s->'inicio') = 'number'
          union all
          select (c->>1)::bigint from jsonb_array_elements(coalesce(x.cardios, '[]')) c where jsonb_typeof(c) = 'array' and jsonb_typeof(c->1) = 'number'
          union all
          select (s->>'inicio')::bigint from jsonb_array_elements(case when jsonb_typeof(dd.estado->'sessoes') = 'array' then dd.estado->'sessoes' else '[]' end) s
            where jsonb_typeof(s->'inicio') = 'number'
          union all
          select (c->>'inicio')::bigint from jsonb_array_elements(case when jsonb_typeof(dd.estado->'cardios') = 'array' then dd.estado->'cardios' else '[]' end) c
            where jsonb_typeof(c->'inicio') = 'number'
        ) z(t)
      ) d
      where y.academia_id = ac)
  );
end $$;

revoke execute on function public.personais_academia(text), public.entrar_como_aluno(text, text, text, uuid), public.minha_matricula(text),
  public.aluno_academia_salvar(uuid, text, text, uuid), public.aluno_academia_ativo(uuid, boolean),
  public.alunos_academia_importar(jsonb), public.painel_academia() from public, anon;
grant execute on function public.personais_academia(text), public.entrar_como_aluno(text, text, text, uuid), public.minha_matricula(text),
  public.aluno_academia_salvar(uuid, text, text, uuid), public.aluno_academia_ativo(uuid, boolean),
  public.alunos_academia_importar(jsonb), public.painel_academia() to authenticated;
