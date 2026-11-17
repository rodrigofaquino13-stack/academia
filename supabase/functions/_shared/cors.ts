export function cabecalhosCors(req: Request): Record<string, string> {
  const origem = req.headers.get('Origin') ?? ''
  const lista = (Deno.env.get('ORIGENS') ?? '').split(',').map((s) => s.trim()).filter(Boolean)
  const permitida = !lista.length || lista.includes(origem)
  return {
    'Access-Control-Allow-Origin': permitida ? origem || '*' : 'null',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    Vary: 'Origin',
  }
}
export const json = (dados: unknown, status: number, cors: Record<string, string>) =>
  new Response(JSON.stringify(dados), { status, headers: { ...cors, 'content-type': 'application/json' } })
