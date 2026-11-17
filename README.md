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
- **Identificar aparelho**: foto do aparelho mostra o que é, como regular e os exercícios. Aparece só quando o servidor de IA está publicado (veja `supabase/CONFIGURAR.md`).
- **Progressão automática**: o app sugere a carga do próximo treino.

- **Perfil do aluno**: diário (água, refeições, remédios e suplementos, sono, energia, anotações), peso e medidas com gráfico, dieta com estimativa de metas e cadastro da academia. O personal pode mandar a dieta junto com o treino e recebe peso e adesão no relatório.
- **Conta do personal e plano Pro**: login por código no e-mail, alunos sincronizados entre aparelhos, plano grátis com 3 alunos e Pro vendido pela Hotmart. A configuração está em `supabase/CONFIGURAR.md`.
