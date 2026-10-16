/** Small dependency-free client for the Supabase Data API. Works in Astro and Node. */
export class ApiError extends Error {
  constructor(status, detail) {
    super(detail.message || `API request failed (${status})`);
    this.name = 'ApiError';
    this.status = status;
    this.code = detail.code;
    this.detail = detail;
  }
}
export function createCivicPulseClient({ url, publishableKey, accessToken, fetch: request = globalThis.fetch }) {
  if (!url || !publishableKey) throw new Error('Supabase URL and publishable key are required');
  const base = new URL('/rest/v1/', url);
  async function call(path, body) {
    const token = typeof accessToken === 'function' ? await accessToken() : accessToken;
    const headers = { apikey: publishableKey, Accept: 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await request(new URL(path, base), {
      method: body === undefined ? 'GET' : 'POST', headers, cache: 'no-store',
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await response.text();
    let data;
    try { data = text ? JSON.parse(text) : null; }
    catch { throw new ApiError(response.status, { message: 'API returned a non-JSON response' }); }
    if (!response.ok) throw new ApiError(response.status, data || {});
    return data;
  }
  async function list(table, kind, { limit = 100, offset = 0 } = {}) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 1000 || !Number.isInteger(offset) || offset < 0)
      throw new Error('Use limit 1..1000 and a nonnegative offset');
    const query = new URLSearchParams({ select: '*', order: 'kind.asc,id.asc', limit: String(limit), offset: String(offset) });
    if (kind) query.set('kind', `eq.${kind}`);
    return call(`${table}?${query}`);
  }
  return {
    role: () => call('rpc/cms_role', {}),
    publicationManifest: () => call('rpc/publication_manifest', {}),
    listPublished: (kind, page) => list('content', kind, page),
    listDrafts: (kind, page) => list('cms_drafts', kind, page),
    async getDraft(kind, id) {
      const query = new URLSearchParams({ kind: `eq.${kind}`, id: `eq.${id}`, select: '*', limit: '1' });
      return (await call(`cms_drafts?${query}`))[0] || null;
    },
    saveDraft: (kind, payload, expectedRevision) => call('rpc/save_draft', {
      p_kind: kind, p_id: payload.id, p_payload: payload, p_expected_revision: expectedRevision,
    }),
    publish: (kind, id, expectedRevision) => call('rpc/publish', {
      p_kind: kind, p_id: id, p_expected_revision: expectedRevision,
    }),
    withdraw: (kind, id, expectedRevision) => call('rpc/withdraw', {
      p_kind: kind, p_id: id, p_expected_revision: expectedRevision,
    }),
    layerGeoJSON: (id, { limit = 500, offset = 0, bounds } = {}) => call('rpc/layer_geojson', {
      p_layer_id: id, p_limit: limit, p_offset: offset,
      ...(bounds ? { p_west: bounds[0], p_south: bounds[1], p_east: bounds[2], p_north: bounds[3] } : {}),
    }),
  };
}
