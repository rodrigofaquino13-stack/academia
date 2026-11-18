-- Lembretes de treino por notificação do app (Web Push).
-- As chaves VAPID são geradas pela própria função "push" na primeira chamada e ficam aqui,
-- numa tabela sem políticas (só o servidor lê). Ninguém precisa copiar chave nenhuma.
create extension if not exists pgcrypto;
create table if not exists public.push_config (
  id int primary key default 1 check (id = 1),
  publica text,
  privada text,
  token_cron text not null default encode(gen_random_bytes(24), 'hex')
);
alter table public.push_config enable row level security;
insert into public.push_config (id) values (1) on conflict do nothing;

-- Cada aparelho que ativou os lembretes
create table if not exists public.push_inscricoes (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  inscricao jsonb not null,
  dias int[] not null,              -- 0 = domingo ... 6 = sábado
  hora text not null,               -- 'HH:MM' no fuso do aparelho
  fuso text not null default 'America/Sao_Paulo',
  ultimo_envio date,
  criado_em timestamptz not null default now()
);
alter table public.push_inscricoes enable row level security;
create policy "lembretes do próprio usuário" on public.push_inscricoes for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A cada 15 minutos o banco chama a função que envia os lembretes da hora
create extension if not exists pg_net;
create extension if not exists pg_cron;
select cron.unschedule('lembretes-treino') where exists (select 1 from cron.job where jobname = 'lembretes-treino');
select cron.schedule('lembretes-treino', '*/15 * * * *', $$
  select net.http_post(
    url := 'https://fejuiddwyqlocdqodpln.supabase.co/functions/v1/push',
    headers := jsonb_build_object('content-type', 'application/json', 'x-cron', (select token_cron from public.push_config where id = 1)),
    body := '{"acao":"enviar"}'::jsonb
  );
$$);
