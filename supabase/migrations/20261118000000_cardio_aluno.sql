-- Cardio que o aluno manda no relatório, guardado com o aluno do personal
alter table public.alunos add column if not exists cardios jsonb not null default '[]'::jsonb;
