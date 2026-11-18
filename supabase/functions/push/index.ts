// Lembretes de treino por notificação (Web Push). Sem chaves para configurar: as chaves VAPID
// são criadas aqui na primeira chamada e guardadas em push_config (só o servidor lê).
//   { acao: 'chave' }   -> chave pública para o app se inscrever
//   { acao: 'teste' }   -> manda uma notificação agora para os aparelhos do usuário logado
//   { acao: 'enviar' }  -> chamada pelo agendador (cron) a cada 15 min, com o cabeçalho x-cron
import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'
import { cabecalhosCors, json } from '../_shared/cors.ts'

function chaveServico(): string {
  const legado = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('CHAVE_SERVICO')
  if (legado) return legado
  try { return Object.values(JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}'))[0] as string } catch { return '' }
}
const admin = createClient(Deno.env.get('SUPABASE_URL')!, chaveServico())
const APP = Deno.env.get('APP_URL') ?? 'https://rodrigofaquino13-stack.github.io/academia/'
const CONTATO = 'mailto:suporte-app-academia@googlegroups.com'

type Config = { publica: string; privada: string; token_cron: string }
async function config(): Promise<Config> {
  const { data } = await admin.from('push_config').select('publica, privada, token_cron').eq('id', 1).single()
  if (data?.publica && data?.privada) return data as Config
  const k = webpush.generateVAPIDKeys()
  await admin.from('push_config').update({ publica: k.publicKey, privada: k.privateKey }).eq('id', 1).is('publica', null)
  const { data: d2 } = await admin.from('push_config').select('publica, privada, token_cron').eq('id', 1).single()
  return d2 as Config
}

/** Hora local do aparelho: dia da semana (0 = domingo), data e minutos do dia. */
export function agoraNoFuso(fuso: string, agora = new Date()) {
  let f: Intl.DateTimeFormat
  try { f = new Intl.DateTimeFormat('en-CA', { timeZone: fuso, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', weekday: 'short', hourCycle: 'h23' }) }
  catch { return agoraNoFuso('America/Sao_Paulo', agora) }
  const p = Object.fromEntries(f.formatToParts(agora).map((x) => [x.type, x.value]))
  return { dia: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday), data: `${p.year}-${p.month}-${p.day}`, min: Number(p.hour) * 60 + Number(p.minute) }
}
/** Na janela do lembrete (até 20 min depois da hora, o agendador roda a cada 15). */
export function naHora(hora: string, dias: number[], fuso: string, agora = new Date()) {
  const l = agoraNoFuso(fuso, agora)
  const [h, m] = hora.split(':').map(Number)
  const alvo = h * 60 + m
  return { ok: dias.includes(l.dia) && l.min >= alvo && l.min < alvo + 20, data: l.data }
}

type Ficha = { id: string; nome: string; itens?: unknown[] }
type Estado = { fichas?: Ficha[]; sessoes?: { inicio: number; fichaId?: string | null }[]; cardios?: { inicio: number }[] }
/** Mensagem do lembrete; null se a pessoa já treinou hoje. */
function mensagem(e: Estado | null, data: string, fuso: string) {
  const diaDe = (t: number) => agoraNoFuso(fuso, new Date(t)).data
  const sessoes = e?.sessoes ?? []
  if (sessoes.some((s) => diaDe(s.inicio) === data) || (e?.cardios ?? []).some((c) => diaDe(c.inicio) === data)) return null
  const fichas = (e?.fichas ?? []).filter((f) => f.itens?.length)
  let body = 'Seu treino está te esperando. Bora manter a sequência!'
  if (fichas.length) {
    const ult = [...sessoes].reverse().find((s) => fichas.some((f) => f.id === s.fichaId))
    const i = ult ? fichas.findIndex((f) => f.id === ult.fichaId) : -1
    body = `Hoje é dia de ${fichas[(i + 1) % fichas.length].nome}. Bora!`
  }
  return { title: 'Hora de treinar', body, url: APP, tag: 'lembrete-treino' }
}

async function enviarPara(cfg: Config, linhas: { endpoint: string; inscricao: webpush.PushSubscription }[], payload: unknown) {
  webpush.setVapidDetails(CONTATO, cfg.publica, cfg.privada)
  let ok = 0
  for (const l of linhas) {
    try { await webpush.sendNotification(l.inscricao, JSON.stringify(payload), { TTL: 3600, urgency: 'normal' }); ok++ }
    catch (e) {
      const st = (e as { statusCode?: number }).statusCode
      if (st === 404 || st === 410) await admin.from('push_inscricoes').delete().eq('endpoint', l.endpoint)  // aparelho desinscrito
    }
  }
  return ok
}

Deno.serve(async (req) => {
  const cors = cabecalhosCors(req)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  let corpo: { acao?: string } = {}
  try { corpo = req.method === 'POST' ? await req.json() : { acao: new URL(req.url).searchParams.get('acao') ?? 'chave' } } catch { /* vazio */ }
  const cfg = await config()

  if (corpo.acao === 'chave') return json({ publica: cfg.publica }, 200, cors)

  if (corpo.acao === 'teste') {
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
    const { data: u } = token ? await admin.auth.getUser(token) : { data: { user: null } }
    if (!u?.user) return json({ erro: 'entre na sua conta' }, 401, cors)
    const { data } = await admin.from('push_inscricoes').select('endpoint, inscricao').eq('user_id', u.user.id)
    const ok = await enviarPara(cfg, data ?? [], { title: 'Lembretes ligados', body: 'É assim que o aviso de treino vai aparecer.', url: APP, tag: 'lembrete-teste' })
    return json({ enviados: ok }, 200, cors)
  }

  if (corpo.acao === 'enviar') {
    if (req.headers.get('x-cron') !== cfg.token_cron) return json({ erro: 'não autorizado' }, 401, cors)
    const { data: inscricoes } = await admin.from('push_inscricoes').select('endpoint, user_id, inscricao, dias, hora, fuso, ultimo_envio')
    const agora = new Date()
    const devidos = (inscricoes ?? []).map((i) => ({ i, h: naHora(i.hora, i.dias, i.fuso, agora) })).filter(({ i, h }) => h.ok && i.ultimo_envio !== h.data)
    if (!devidos.length) return json({ enviados: 0 }, 200, cors)
    const usuarios = [...new Set(devidos.map(({ i }) => i.user_id))]
    const { data: dados } = await admin.from('dados').select('user_id, estado').in('user_id', usuarios)
    let enviados = 0
    for (const { i, h } of devidos) {
      const estado = (dados ?? []).find((d) => d.user_id === i.user_id)?.estado as Estado | undefined
      const msg = mensagem(estado ?? null, h.data, i.fuso)
      if (msg) enviados += await enviarPara(cfg, [i], msg)
      await admin.from('push_inscricoes').update({ ultimo_envio: h.data }).eq('endpoint', i.endpoint)
    }
    return json({ enviados }, 200, cors)
  }
  return json({ erro: 'ação desconhecida' }, 400, cors)
})
