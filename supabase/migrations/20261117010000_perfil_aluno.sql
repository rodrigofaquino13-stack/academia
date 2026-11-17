-- Perfil do aluno no modo personal: dieta enviada, peso/medidas e resumo do diário recebidos, academia.
alter table public.alunos
  add column if not exists dieta jsonb,
  add column if not exists medidas jsonb not null default '[]',
  add column if not exists diario jsonb not null default '[]',
  add column if not exists academia text;
