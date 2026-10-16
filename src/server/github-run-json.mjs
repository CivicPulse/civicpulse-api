import { parse } from 'lossless-json';

// Internal parsing boundary; not part of browser exports or source authority.
export const runIdentityLimits = Object.freeze({ rawBytes: 1048576, depth: 64, tokens: 32768, stringBytes: 65536 });
const invalid = () => Object.assign(new Error('invalid_github_run_identity'), { code: 'invalid_github_run_identity' });
const whitespace = character => character === ' ' || character === '\n' || character === '\r' || character === '\t';
const fullMatch = (pattern, value) => typeof value === 'string' && pattern.exec(value)?.[0] === value;

/** Iterative JSON token walk: resource bounds and ALL decoded duplicate keys.
 * lossless-json alone permits equal-valued duplicates. No numeric conversion or
 * input rewriting occurs here; the pinned parser still creates lossless values.
 */
function preflight(raw) {
  if (typeof raw !== 'string' || !raw.length || raw.length > runIdentityLimits.rawBytes || Buffer.byteLength(raw,'utf8') > runIdentityLimits.rawBytes) throw invalid();
  const stack = [];
  let index = 0, tokens = 0, rootConsumed = false;
  const consumeValue = () => {
    const parent = stack.at(-1);
    if (!parent) {
      if (rootConsumed) throw invalid();
      rootConsumed = true;
    } else {
      if (parent.state !== 'value' && parent.state !== 'valueOrEnd') throw invalid();
      parent.state = 'commaOrEnd';
    }
  };
  while (index < raw.length) {
    if (whitespace(raw[index])) { index++; continue; }
    if (++tokens > runIdentityLimits.tokens) throw invalid();
    const character = raw[index], parent = stack.at(-1);
    if (character === '"') {
      const start = index;
      let stringBytes = 0;
      const take = () => {
        const code = raw.charCodeAt(index);
        const pairedHigh = code >= 0xd800 && code <= 0xdbff && raw.charCodeAt(index+1) >= 0xdc00 && raw.charCodeAt(index+1) <= 0xdfff;
        const pairedLow = code >= 0xdc00 && code <= 0xdfff && raw.charCodeAt(index-1) >= 0xd800 && raw.charCodeAt(index-1) <= 0xdbff;
        stringBytes += pairedHigh ? 4 : pairedLow ? 0 : code < 0x80 ? 1 : code < 0x800 ? 2 : 3;
        if (stringBytes > runIdentityLimits.stringBytes) throw invalid();
        return raw[index++];
      };
      take(); // opening quote
      let closed = false;
      while (index < raw.length) {
        const c = take();
        if (c === '"') { closed = true; break; }
        if (c.charCodeAt(0) < 32) throw invalid();
        if (c === '\\') {
          const escape = take();
          if (escape === 'u') {
            if (!fullMatch(/^[0-9a-fA-F]{4}$/u,raw.slice(index,index+4))) throw invalid();
            for (let digit=0; digit<4; digit++) take();
          } else if (!escape || !'"\\/bfnrt'.includes(escape)) throw invalid();
        }
      }
      const literal = raw.slice(start,index);
      if (!closed) throw invalid();
      // Only an exactly delimited, escape-checked STRING is parsed natively.
      const text = JSON.parse(literal);
      if (parent?.type === 'object' && (parent.state === 'key' || parent.state === 'keyOrEnd')) {
        if (parent.keys.has(text)) throw invalid();
        parent.keys.add(text);
        parent.state = 'colon';
      } else consumeValue();
    } else if (character === '{' || character === '[') {
      consumeValue();
      if (stack.length >= runIdentityLimits.depth) throw invalid();
      stack.push(character === '{' ? { type:'object', state:'keyOrEnd', keys:new Set() } : { type:'array', state:'valueOrEnd' });
      index++;
    } else if (character === '}' || character === ']') {
      const type = character === '}' ? 'object' : 'array';
      const initial = type === 'object' ? 'keyOrEnd' : 'valueOrEnd';
      if (!parent || parent.type !== type || (parent.state !== initial && parent.state !== 'commaOrEnd')) throw invalid();
      stack.pop(); index++;
    } else if (character === ':') {
      if (!parent || parent.type !== 'object' || parent.state !== 'colon') throw invalid();
      parent.state = 'value'; index++;
    } else if (character === ',') {
      if (!parent || parent.state !== 'commaOrEnd') throw invalid();
      parent.state = parent.type === 'object' ? 'key' : 'value'; index++;
    } else {
      const start = index;
      while (index < raw.length && !whitespace(raw[index]) && !'{}[],:"'.includes(raw[index])) index++;
      const token = raw.slice(start,index);
      if (!['true','false','null'].includes(token) && !fullMatch(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/u,token)) throw invalid();
      consumeValue();
    }
  }
  if (stack.length || !rootConsumed) throw invalid();
}


// The optional parser is an internal test seam proving ordering. The public
// decoder supplies no override and always uses the pinned lossless dependency.
export function parseBoundedRunResponse(raw, parser = parse) {
  try {
    preflight(raw);
    return parser(raw);
  } catch { throw invalid(); }
}
