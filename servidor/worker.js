/**
 * Servidor de IA do app Academia (Cloudflare Worker).
 * Recebe o pedido do app, troca o modelo e o limite de tokens pelos permitidos e repassa à API da Anthropic com a sua chave.
 * Variáveis: ANTHROPIC_API_KEY (secreta), ORIGENS (ex.: "https://rodrigofaquino13-stack.github.io"), MODELO (opcional).
 */
export default {
  async fetch(req, env) {
    const origem = req.headers.get('Origin') || ''
    const permitidas = (env.ORIGENS || '').split(',').map((s) => s.trim()).filter(Boolean)
    const liberada = permitidas.includes(origem)
    const cors = {
      'Access-Control-Allow-Origin': liberada ? origem : 'null',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'content-type',
      Vary: 'Origin',
    }
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    if (req.method !== 'POST') return new Response('Use POST', { status: 405, headers: cors })
    if (!liberada) return new Response('Origem não permitida', { status: 403, headers: cors })

    let body
    try { body = await req.json() } catch { return new Response('JSON inválido', { status: 400, headers: cors }) }
    if (JSON.stringify(body).length > 6_000_000) return new Response('Imagem grande demais', { status: 413, headers: cors })

    body.model = env.MODELO || 'claude-sonnet-5-5'
    body.max_tokens = Math.min(Number(body.max_tokens) || 2048, 4096)
    delete body.stream

    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify(body),
    })
    return new Response(r.body, { status: r.status, headers: { ...cors, 'content-type': 'application/json' } })
  },
}
