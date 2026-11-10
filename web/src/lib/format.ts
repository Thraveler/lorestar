// Copper to "1g 02s 03c" (zero parts omitted, except the last).
export function money(copper: number | null | undefined): string {
  if (copper === null || copper === undefined) return '—';
  const c = Math.round(copper);
  const g = Math.floor(c / 10000);
  const s = Math.floor((c % 10000) / 100);
  const cp = c % 100;
  const parts: string[] = [];
  if (g) parts.push(`${g}g`);
  if (g || s) parts.push(`${g ? String(s).padStart(2, '0') : s}s`);
  parts.push(`${g || s ? String(cp).padStart(2, '0') : cp}c`);
  return parts.join(' ');
}

export const nf = new Intl.NumberFormat('en-US');
