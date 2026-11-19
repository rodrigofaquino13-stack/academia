# Como ligar a nuvem e o plano Pro

Sem esta configuração o app funciona só no aparelho, como hoje. Com ela, o personal entra com o e-mail, os alunos ficam na nuvem, o plano grátis aceita até 3 alunos e o Pro é vendido pela Hotmart.

## 1. Supabase (banco e login)

1. Crie uma conta em supabase.com e um projeto novo (plano grátis, região São Paulo). Guarde a senha do banco.
2. Em **SQL Editor**, rode os arquivos da pasta `migrations/` em ordem (cole o conteúdo e clique em **Run**): primeiro `20261117000000_academia.sql`, depois `20261117010000_perfil_aluno.sql` e por último `20261117020000_conta_usuario.sql`.
3. Em **Authentication > Sign In / Providers**, deixe **Email** ligado.
4. Em **Authentication > Emails > Templates**, nos modelos **Magic link** e **Confirm signup**, troque o texto por algo assim (o importante é o `{{ .Token }}`, que é o código que o personal digita no app):

   ```
   <h2>Seu código para entrar no Treino Feito</h2>
   <p style="font-size:28px;letter-spacing:4px"><b>{{ .Token }}</b></p>
   <p>Ele vale por 1 hora. Se não foi você, ignore este e-mail.</p>
   ```
5. Em **Authentication > URL Configuration**, coloque em Site URL: `https://rodrigofaquino13-stack.github.io/academia/`
6. Antes de lançar: em **Authentication > Emails > SMTP Settings**, ligue um serviço de e-mail próprio (Resend ou Brevo têm plano grátis). O envio padrão do Supabase manda poucos e-mails por hora e serve só para teste.
7. Em **Project Settings > API**, copie a **Project URL** e a chave **anon / publishable**. Essa chave é pública (vai dentro do app). A chave **service_role / secret** nunca deve sair do Supabase.

## 1b. Login com Google e Apple (opcional)

**Google**
1. Em console.cloud.google.com, crie um projeto (ex.: Academia).
2. Em **Google Auth Platform**, preencha a marca (nome do app, e-mail de suporte), escolha público **Externo** e publique o app (os escopos de e-mail e perfil não exigem verificação).
3. Em **Clientes**, crie um cliente OAuth do tipo **Aplicativo da Web** com o URI de redirecionamento `https://SEU_PROJECT_REF.supabase.co/auth/v1/callback`.
4. No Supabase, em **Authentication > Sign In / Providers > Google**, ligue o provedor e cole o Client ID e o Client Secret.

**Apple**: exige o Apple Developer Program (assinatura anual da Apple). Com ele, crie um Services ID com "Sign in with Apple" e configure em **Providers > Apple**.

Depois, gere o app com `VITE_LOGIN=google` (ou `google,apple`) para os botões aparecerem.

## 2. Funções do servidor (IA e Hotmart)

No computador, dentro da pasta do projeto:

```bash
npm i -g supabase
supabase login
supabase link --project-ref SEU_PROJECT_REF        # o código que aparece na Project URL
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  # chave criada em console.anthropic.com
supabase secrets set ORIGENS=https://rodrigofaquino13-stack.github.io
supabase functions deploy ia --no-verify-jwt
# Pelo painel: Edge Functions > Deploy a new function > Via editor, cole o conteúdo de ia/index.ts
# (com o _shared/cors.ts embutido), nome "ia", e desligue "Verify JWT with legacy secret".
# A função só chama a Anthropic com o segredo IA_LIGADA=1 (sem ele, responde 503 e não gasta nada).
# Depois, gere o app com VITE_IA=1 para mostrar a ficha por foto.
supabase functions deploy hotmart --no-verify-jwt
```

## 3. Hotmart (assinatura)

1. Crie o produto **Academia Pro** como **assinatura** mensal, com o preço que quiser. Anote o **ID do produto** e o **link do checkout** (`https://pay.hotmart.com/...`).
2. Em **Ferramentas > Webhook (API e notificações)**, cadastre:
   - URL: `https://SEU_PROJECT_REF.supabase.co/functions/v1/hotmart`
   - Versão: **2.0.0**
   - Produto: Academia Pro
   - Eventos: compra aprovada, compra completa, compra cancelada, compra reembolsada, chargeback, compra expirada, compra em protesto e cancelamento de assinatura.
3. Na aba **Autenticação** da tela de Webhook, copie o **Hottok** e rode:

```bash
supabase secrets set HOTMART_HOTTOK=o_hottok_copiado HOTMART_PRODUTO=id_do_produto
```

A liberação é pelo e-mail: quem compra com o mesmo e-mail que usa no app vira Pro em segundos. Ao cancelar, continua Pro até o fim do mês pago. Reembolso e chargeback tiram o Pro na hora.

## 4. Publicar o app com a nuvem ligada

Mande para o Claude a Project URL, a chave anon/publishable, o link do checkout e o preço; ou gere você mesmo:

```bash
VITE_SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co \
VITE_SUPABASE_ANON_KEY=sua_chave_publica \
VITE_CHECKOUT_URL=https://pay.hotmart.com/SEU_CODIGO \
VITE_PRECO_PRO="R$ 39,90 por mês" \
VITE_IA=1 \
VITE_LOGIN=google \
npm run build
```

`VITE_IA=1` liga a identificação de aparelho por foto, que usa a função `ia` do passo 2. Sem essa linha o recurso fica escondido no app; o usuário nunca precisa colocar chave de API.

## Ajustes sem mexer no código

Na tabela `config` (Supabase > Table Editor):

| chave | padrão | o que é |
|---|---|---|
| limite_alunos_gratis | 3 | alunos no plano grátis |
| ia_dia_anonimo | 5 | leituras por foto por dia para quem não tem conta (alunos) |
| ia_dia_gratis | 10 | leituras por dia para personal grátis |
| ia_dia_pro | 60 | leituras por dia para personal Pro |

Para dar Pro manualmente (cortesia, parceiro): em `assinaturas`, insira uma linha com o e-mail, status `ativa` e `valida_ate` vazio.


## Lembretes por notificação

1. Rode `migrations/20261118020000_lembretes_push.sql` (cria as tabelas e o agendamento a cada 15 min).
2. Publique a função `push` (painel: Via editor, com o `_shared/cors.ts` embutido) e desligue "Verify JWT with legacy secret".
3. Pronto: as chaves VAPID são criadas pela própria função na primeira chamada. No iPhone, o aluno precisa instalar o app na tela de início.


## Academias (white label)

1. Rode `migrations/20261118030000_academias.sql` (já rodada em produção).
2. O dono cria a academia no app: Ajustes > "Criar o app da minha academia" (nome, endereço, cor, logo, mensagem). Ganha 30 dias de teste.
3. Links: alunos abrem `…/academia/?a=ENDERECO`; professores entram por `…/academia/?a=ENDERECO&prof=CODIGO` (o painel gera os dois).
4. Quando a academia pagar, estenda a licença no SQL Editor:
   `update academias set ativa_ate = now() + interval '1 month' where slug = 'ENDERECO';`
   Com a licença vencida, o painel avisa e os professores voltam ao limite do plano grátis.

## Demonstração para visitas

Abra `…/academia/?demo` (ou `?demo&nome=Academia%20X&cor=E4572E`). Abre sem login, com dados fictícios guardados à parte no aparelho.
A barra do topo troca a visão (Dono, Professor, Aluno), personaliza nome, cor e logo e mostra a tela de entrada do aluno. "Sair da demonstração" volta ao app normal.
