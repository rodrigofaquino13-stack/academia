# Servidor de IA do Academia

O app lê fotos (ficha e aparelho) com a IA Claude. Em produção a chave da API não pode ficar no app, então ela fica neste servidor.

1. Crie uma conta grátis na Cloudflare e instale o Wrangler: `npm i -g wrangler` e `wrangler login`.
2. Nesta pasta: `wrangler secret put ANTHROPIC_API_KEY` (cole a chave criada em console.anthropic.com).
3. Publique: `wrangler deploy`. Ele mostra um endereço como `https://academia-ia.SEU-USUARIO.workers.dev`.
4. No app, em Ajustes > Leitura por foto, cole esse endereço no campo do servidor. Para já sair embutido no app, gere o build com `VITE_IA_URL=https://academia-ia.SEU-USUARIO.workers.dev npm run build`.

Se publicar o app em outro domínio, acrescente o domínio em `ORIGENS` no `wrangler.toml` (separado por vírgula).
A trava de origem impede o uso a partir de outros sites, mas não de scripts. Antes de abrir para muitos usuários, ponha um limite de gastos no console da Anthropic e, se quiser, um limite de pedidos por IP na Cloudflare.
