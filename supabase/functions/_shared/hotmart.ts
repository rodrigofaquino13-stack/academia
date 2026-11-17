/** Traduz um aviso (webhook 2.0) da Hotmart em mudança de assinatura. Função pura, sem dependências. */
export interface MudancaAssinatura {
  email: string
  status: 'ativa' | 'cancelada' | 'inativa'
  /** ISO; null = sem data; undefined = manter a que já existe */
  validaAte: string | null | undefined
  assinante?: string
  produto?: string
}

const ATIVAM = ['PURCHASE_APPROVED', 'PURCHASE_COMPLETE']
const ENCERRAM = ['PURCHASE_CANCELED', 'PURCHASE_REFUNDED', 'PURCHASE_CHARGEBACK', 'PURCHASE_EXPIRED', 'PURCHASE_PROTEST']
const DIA = 864e5

type Obj = Record<string, unknown>
const o = (v: unknown): Obj => (v && typeof v === 'object' ? (v as Obj) : {})
const ms = (v: unknown): number | null => {
  const n = typeof v === 'string' ? Date.parse(v) || Number(v) : Number(v)
  if (!isFinite(n) || n <= 0) return null
  return n < 1e12 ? n * 1000 : n // aceita segundos ou milissegundos
}

export function interpretarHotmart(corpo: unknown, opcoes: { produto?: string; agora?: number } = {}): MudancaAssinatura | null {
  const c = o(corpo), d = o(c.data)
  const evento = String(c.event ?? '')
  const agora = opcoes.agora ?? Date.now()
  const produto = o(d.product)
  const idProduto = produto.id != null ? String(produto.id) : undefined
  if (opcoes.produto && idProduto && idProduto !== opcoes.produto) return null

  const email = String(o(d.buyer).email ?? o(d.subscriber).email ?? '').trim().toLowerCase()
  if (!email.includes('@')) return null
  const assinatura = o(d.subscription)
  const assinante = String(o(assinatura.subscriber).code ?? o(d.subscriber).code ?? '') || undefined
  const proxima = ms(o(d.purchase).date_next_charge ?? d.date_next_charge)
  const base = { email, assinante, produto: idProduto }

  if (ATIVAM.includes(evento)) {
    // vale até a próxima cobrança + 3 dias de tolerância; sem data, 35 dias
    const ate = (proxima ?? agora + 32 * DIA) + 3 * DIA
    return { ...base, status: 'ativa', validaAte: new Date(ate).toISOString() }
  }
  if (ENCERRAM.includes(evento)) return { ...base, status: 'inativa', validaAte: new Date(agora).toISOString() }
  if (evento === 'SUBSCRIPTION_CANCELLATION') {
    // continua Pro até o fim do período já pago
    return { ...base, status: 'cancelada', validaAte: proxima ? new Date(proxima).toISOString() : undefined }
  }
  return null
}
