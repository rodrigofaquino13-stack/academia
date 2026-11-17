# Como ligar a nuvem e o plano Pro

Sem esta configuração o app funciona só no aparelho, como hoje. Com ela, o personal entra com o e-mail, os alunos ficam na nuvem, o plano grátis aceita até 3 alunos e o Pro é vendido pela Hotmart.

## 1. Supabase (banco e login)

1. Crie uma conta em supabase.com e um projeto novo (plano grátis, região São Paulo). Guarde a senha do banco.
2. Em **SQL Editor**, rode os arquivos da pasta `migrations/` em ordem (cole o conteúdo e clique em **Run**): primeiro `20261117000000_academia.sql`, depois `20261117010000_perfil_aluno.sql`.
3. Em **Authentication > Sign In / Providers**, deixe **Email** ligado.
4. Em **Authentication > Emails > Templates**, nos modelos **Magic link** e **Confirm signup**, troque o texto por algo assim (o importante é o `{{ .Token }}`, que é o código que o personal digita no app):

   ```
   <h2>Seu código para entrar no Academia</h2>
   <p style="font-size:28px;letter-spacing:4px"><b>{{ .Token }}</b></p>
   <p>Ele vale por 1 hora. Se não foi você, ignore este e-mail.</p>
   ```
5. Em **Authentication > URL Configuration**, coloque em Site URL: `https://rodrigofaquino13-stack.github.io/academia/`
6. Antes de lançar: em **Authentication > Emails > SMTP Settings**, ligue um serviço de e-mail próprio (Resend ou Brevo têm plano grátis). O envio padrão do Supabase manda poucos e-mails por hora e serve só para teste.
7. Em **Project Settings > API**, copie a **Project URL** e a chave **anon / publishable**. Essa chave é pública (vai dentro do app). A chave **service_role / secret** nunca deve sair do Supabase.

## 2. Funções do servidor (IA e Hotmart)

No computador, dentro da pasta do projeto:

```bash
npm i -g supabase
supabase login
supabase link --project-ref SEU_PROJECT_REF        # o código que aparece na Project URL
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  # chave criada em console.anthropic.com
supabase secrets set ORIGENS=https://rodrigofaquino13-stack.github.io
supabase functions deploy ia --no-verify-jwt
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
npm run build
```

## Ajustes sem mexer no código

Na tabela `config` (Supabase > Table Editor):

| chave | padrão | o que é |
|---|---|---|
| limite_alunos_gratis | 3 | alunos no plano grátis |
| ia_dia_anonimo | 5 | leituras por foto por dia para quem não tem conta (alunos) |
| ia_dia_gratis | 10 | leituras por dia para personal grátis |
| ia_dia_pro | 60 | leituras por dia para personal Pro |

Para dar Pro manualmente (cortesia, parceiro): em `assinaturas`, insira uma linha com o e-mail, status `ativa` e `valida_ate` vazio.
