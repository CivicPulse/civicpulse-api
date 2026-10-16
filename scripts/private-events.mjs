import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const review=JSON.parse(readFileSync(new URL('../data/import-repairs/private-events.json',import.meta.url)));
export const privateLocationPlaceholder=review.placeholder;
export const privateEventFields=new Set(`id title start end category location address description note sample sourceUrl sourceChecked organizer sourceLabel sourceGroup sourceEventId sourceCalendar organizationId calendarIds allDay endTimeUnknown isVirtual addressPrivate coordinates`.split(' '));

export function normalizeReviewedPrivateEvents(events, sourceBytes) {
  if (createHash('sha256').update(sourceBytes).digest('hex')!==review.sourceSha256)
    throw new Error('Mobilize source snapshot changed; private-event normalization requires review');
  const reviewed=new Set(review.privateEventIds);
  return events.map(event=>{
    if (event.addressPrivate!==true) return event;
    if (!reviewed.has(event.id)) throw new Error(`Unreviewed private event: ${event.id}`);
    if (event.coordinates!=null) throw new Error('Reviewed private event unexpectedly contains coordinates');
    const payload=Object.fromEntries(Object.entries(event).filter(([key])=>privateEventFields.has(key)));
    payload.address=review.placeholder;
    payload.location=review.placeholder;
    // Do not attach nested provenance to public private-event payloads. Source
    // bytes and the reviewed normalization manifest remain outside public output.
    return payload;
  });
}
