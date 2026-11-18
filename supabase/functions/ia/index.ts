// IA Claude do app: só a leitura da ficha por foto. A chave da Anthropic fica só aqui.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { cabecalhosCors, json } from '../_shared/cors.ts'

function chaveServico(): string {
  const legado = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('CHAVE_SERVICO')
  if (legado) return legado
  try { return Object.values(JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}'))[0] as string } catch { return '' }
}
const admin = createClient(Deno.env.get('SUPABASE_URL')!, chaveServico())
const MODELO = Deno.env.get('MODELO_IA') ?? 'claude-sonnet-5-5'

async function config(chave: string, padrao: number) {
  const { data } = await admin.from('config').select('valor').eq('chave', chave).maybeSingle()
  return Number(data?.valor) || padrao
}

Deno.serve(async (req) => {
  const cors = cabecalhosCors(req)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json({ erro: 'use POST' }, 405, cors)
  if (cors['Access-Control-Allow-Origin'] === 'null') return json({ erro: 'origem não permitida' }, 403, cors)

  // Só conta logada (o app exige conta); limite diário pelo plano
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  const { data: u } = token ? await admin.auth.getUser(token) : { data: { user: null } }
  if (!u?.user) return json({ erro: 'entre na sua conta para usar a leitura por foto' }, 401, cors)
  const { data: plano } = await admin.rpc('plano', { uid: u.user.id })
  const limite = plano === 'pro' ? await config('ia_dia_pro', 60) : await config('ia_dia_gratis', 10)
  const chave = 'u:' + u.user.id
  const { data: usado, error } = await admin.rpc('consumir_ia', { p_chave: chave, p_limite: limite })
  if (error) return json({ erro: 'falha ao registrar uso' }, 500, cors)
  if (usado === -1) return json({ erro: 'limite_ia', limite }, 429, cors)

  let corpo: Record<string, unknown>
  try { corpo = await req.json() } catch { return json({ erro: 'JSON inválido' }, 400, cors) }
  if (JSON.stringify(corpo).length > 6_000_000) return json({ erro: 'imagem grande demais' }, 413, cors)
  // Só leitura de foto: o pedido precisa trazer uma imagem
  const msgs = Array.isArray(corpo.messages) ? corpo.messages as { content?: unknown }[] : []
  if (!msgs.some((m) => Array.isArray(m.content) && (m.content as { type?: string }[]).some((b) => b?.type === 'image'))) {
    return json({ erro: 'pedido sem foto' }, 400, cors)
  }
  corpo.model = MODELO
  delete corpo.modelo
  corpo.max_tokens = Math.min(Number(corpo.max_tokens) || 2048, 4096)
  delete corpo.stream

  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': Deno.env.get('ANTHROPIC_API_KEY')!, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify(corpo),
  })
  return new Response(r.body, { status: r.status, headers: { ...cors, 'content-type': 'application/json', 'x-ia-usado': String(usado), 'x-ia-limite': String(limite) } })
})
