-- Conta para todos os usuários: os dados do app (fichas, histórico, perfil, dieta, diário) ficam salvos por usuário.
create table if not exists public.dados (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  estado jsonb not null,
  atualizado_em bigint not null   -- ms do aparelho que salvou por último
);
alter table public.dados enable row level security;
create policy "dados do próprio usuário" on public.dados for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Excluir a própria conta (exigência da LGPD e da Apple). Apaga perfil, alunos e dados em cascata.
create or replace function public.excluir_conta() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'não autenticado'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke execute on function public.excluir_conta() from public, anon;
grant execute on function public.excluir_conta() to authenticated;
