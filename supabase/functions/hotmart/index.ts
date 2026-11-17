// Recebe os avisos da Hotmart e liga/desliga o plano Pro pelo e-mail do comprador.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { interpretarHotmart } from '../_shared/hotmart.ts'

const admin = createClient(Deno.env.get('SUPABASE_URL')!, (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('CHAVE_SERVICO'))!)
const resposta = (texto: string, status = 200) => new Response(texto, { status })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return resposta('use POST', 405)
  let corpo: Record<string, unknown>
  try { corpo = await req.json() } catch { return resposta('JSON inválido', 400) }

  const hottok = req.headers.get('x-hotmart-hottok') ?? String(corpo.hottok ?? '')
  const esperado = Deno.env.get('HOTMART_HOTTOK')
  if (!esperado || hottok !== esperado) return resposta('hottok inválido', 401)

  const evento = String(corpo.event ?? 'DESCONHECIDO')
  const id = String(corpo.id ?? '') || `${evento}:${crypto.randomUUID()}`
  const mudanca = interpretarHotmart(corpo, { produto: Deno.env.get('HOTMART_PRODUTO') || undefined })

  // Guarda o aviso; se já chegou antes (a Hotmart reenvia), não processa de novo
  const { error: dup } = await admin.from('hotmart_eventos').insert({ id, evento, email: mudanca?.email ?? null, payload: corpo })
  if (dup?.code === '23505') return resposta('já processado')
  if (dup) return resposta('erro ao registrar', 500)
  if (!mudanca) return resposta('ignorado')

  const linha: Record<string, unknown> = {
    email: mudanca.email, status: mudanca.status, assinante: mudanca.assinante, produto: mudanca.produto, atualizado_em: new Date().toISOString(),
  }
  if (mudanca.validaAte !== undefined) linha.valida_ate = mudanca.validaAte
  const { error } = await admin.from('assinaturas').upsert(linha, { onConflict: 'email' })
  return error ? resposta('erro ao salvar', 500) : resposta('ok')
})
