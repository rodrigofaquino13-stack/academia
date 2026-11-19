# Treino Feito

App de treino de academia que funciona no navegador e pode ser instalado no celular.

- 876 exercícios em português com demonstração animada
- Fichas de treino com séries, repetições, carga e descanso
- Registro de cargas por série, histórico e evolução (1RM estimado)
- Timer de descanso com som e vibração
- Funciona offline depois do primeiro acesso

**Abrir:** https://rodrigofaquino13-stack.github.io/academia/

No celular, abra o link e use "Adicionar à tela inicial" para instalar.

Este repositório contém só o site publicado. Imagens dos exercícios: Free Exercise DB (domínio público).

## Novidades

- **Treino por objetivo**: assistente com 7 perguntas (objetivo, nível, dias, tempo, local, foco e restrições) que monta a divisão completa, com séries, repetições e descanso de acordo com o objetivo.
- **Variação**: trocar qualquer exercício por um equivalente (no treino, na ficha e no assistente) e variar a ficha inteira com um toque.
- **Modo personal**: o personal cadastra alunos, monta as fichas e manda o treino por link no WhatsApp. O aluno abre sem cadastro, com o nome e a cor do personal, e devolve o progresso por outro link.
- **Ficha por foto**: foto da ficha (papel, escrita à mão ou print) vira fichas do app. É o único recurso com IA, com limite diário por conta. Está desligado: para ligar, crie o segredo `IA_LIGADA=1` no Supabase e gere o app com `VITE_IA=1` (veja `supabase/CONFIGURAR.md`).
- **Progressão automática**: o app sugere a carga do próximo treino.

- **Perfil do aluno**: diário (água, refeições, remédios e suplementos, sono, energia, anotações), peso e medidas com gráfico, dieta com estimativa de metas e cadastro da academia. O personal pode mandar a dieta junto com o treino e recebe peso e adesão no relatório.
- **Avaliação por conversa**: depois do cadastro o app pergunta se a pessoa já tem ficha. Quem tem fotografa (a IA lê, único uso de IA do app) ou digita; quem não tem responde uma conversa com botões (objetivo, nível, dias, tempo, local, foco, dores) e o gerador do app monta as fichas, sem custo de IA.
- **Acompanhamento ao vivo**: o convite vai junto no link do treino; com a autorização do aluno, o personal vê treinos, cardio, peso, medidas e o resumo do diário sem link de volta (anotações e remédios nunca saem da conta do aluno), manda treinos novos direto pelo app e recebe alerta de aluno sem treinar há 5 dias ou mais, com mensagem pronta no WhatsApp.
- **Desafio do mês**: o personal cria uma meta de dias de treino; o aluno vê o próprio progresso e o personal vê o ranking e compartilha no WhatsApp.
- **Treino que se ajusta ao dia**: check-in antes do treino (sono, energia, dor) deixa o treino mais leve num dia ruim; aviso quando a carga de um exercício fica parada 3 semanas, com sugestão de trocar a variação ou fazer uma semana leve.
- **Sequência e lembretes**: semanas seguidas batendo a meta e lembretes de treino por notificação do app (Web Push) nos dias e hora escolhidos; não avisa se a pessoa já treinou no dia. As chaves de envio são geradas pela função `push` e um agendador do Supabase (pg_cron) dispara a cada 15 minutos.
- **Cardio**: esteira, corrida, bike, elíptico e outros com tempo, distância, ritmo, intensidade e calorias; entra na semana, no histórico e no relatório para o personal.
- **Conta obrigatória**: tela de início e acesso só com conta (Google ou e-mail e senha, com confirmação do e-mail e "Esqueci a senha"). Funciona offline depois de entrar; ao sair, os dados saem do aparelho e ficam na conta. Treino enviado pelo personal fica guardado até o aluno entrar.
- **Conta para todos**: entrar com Google, Apple ou link no e-mail, cadastro rápido no primeiro acesso, fichas/histórico/perfil/diário salvos na nuvem e sincronizados entre aparelhos, e exclusão da conta.
- **App da academia (white label)**: o dono cria a academia com nome, logo, cor e mensagem; os alunos abrem o link `?a=endereco` e veem o app com a marca dela (inclusive o ícone ao instalar). Painel do dono com alunos ativos e parados (mensagem pronta no WhatsApp), treinos por semana, professores e ranking do mês. Professores entram por convite e ficam com alunos ilimitados enquanto a licença estiver em dia (30 dias de teste).
- **Demonstração para visitas**: `?demo` abre sem login com dados fictícios, troca entre as visões de dono, professor e aluno e personaliza com o nome, a cor e o logo da academia visitada.
- **Conta do personal e plano Pro**: login por código no e-mail, alunos sincronizados entre aparelhos, plano grátis com 3 alunos e Pro vendido pela Hotmart. A configuração está em `supabase/CONFIGURAR.md`.
