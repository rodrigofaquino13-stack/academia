// Leitura de fotos (ficha e aparelho) com a IA Claude. A chave da Anthropic fica só aqui.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { cabecalhosCors, json } from '../_shared/cors.ts'

const admin = createClient(Deno.env.get('SUPABASE_URL')!, (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('CHAVE_SERVICO'))!)
const MODELO = Deno.env.get('MODELO_IA') ?? 'claude-sonnet-5-5'

async function hash(texto: string) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto))
  return Array.from(new Uint8Array(b).slice(0, 12), (x) => x.toString(16).padStart(2, '0')).join('')
}
async function config(chave: string, padrao: number) {
  const { data } = await admin.from('config').select('valor').eq('chave', chave).maybeSingle()
  return Number(data?.valor) || padrao
}

Deno.serve(async (req) => {
  const cors = cabecalhosCors(req)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json({ erro: 'use POST' }, 405, cors)
  if (cors['Access-Control-Allow-Origin'] === 'null') return json({ erro: 'origem não permitida' }, 403, cors)

  // Quem está pedindo: personal logado (limite pelo plano) ou visitante (limite por IP)
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  let chave: string, limite: number
  const { data: u } = token ? await admin.auth.getUser(token) : { data: { user: null } }
  if (u?.user) {
    const { data: plano } = await admin.rpc('plano', { uid: u.user.id })
    limite = plano === 'pro' ? await config('ia_dia_pro', 60) : await config('ia_dia_gratis', 10)
    chave = 'u:' + u.user.id
  } else {
    const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'sem-ip'
    limite = await config('ia_dia_anonimo', 5)
    chave = 'ip:' + (await hash(ip))
  }
  const { data: usado, error } = await admin.rpc('consumir_ia', { p_chave: chave, p_limite: limite })
  if (error) return json({ erro: 'falha ao registrar uso' }, 500, cors)
  if (usado === -1) return json({ erro: 'limite_ia', limite }, 429, cors)

  let corpo: Record<string, unknown>
  try { corpo = await req.json() } catch { return json({ erro: 'JSON inválido' }, 400, cors) }
  if (JSON.stringify(corpo).length > 6_000_000) return json({ erro: 'imagem grande demais' }, 413, cors)
  corpo.model = MODELO
  corpo.max_tokens = Math.min(Number(corpo.max_tokens) || 2048, 4096)
  delete corpo.stream

  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': Deno.env.get('ANTHROPIC_API_KEY')!, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify(corpo),
  })
  return new Response(r.body, { status: r.status, headers: { ...cors, 'content-type': 'application/json', 'x-ia-usado': String(usado), 'x-ia-limite': String(limite) } })
})
