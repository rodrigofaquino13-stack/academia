# Academia

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
- **Cardio**: esteira, corrida, bike, elíptico e outros com tempo, distância, ritmo, intensidade e calorias; entra na semana, no histórico e no relatório para o personal.
- **Conta obrigatória**: tela de início e acesso só com conta (Google, Apple ou link no e-mail). Funciona offline depois de entrar; ao sair, os dados saem do aparelho e ficam na conta. Treino enviado pelo personal fica guardado até o aluno entrar.
- **Conta para todos**: entrar com Google, Apple ou link no e-mail, cadastro rápido no primeiro acesso, fichas/histórico/perfil/diário salvos na nuvem e sincronizados entre aparelhos, e exclusão da conta.
- **Conta do personal e plano Pro**: login por código no e-mail, alunos sincronizados entre aparelhos, plano grátis com 3 alunos e Pro vendido pela Hotmart. A configuração está em `supabase/CONFIGURAR.md`.
