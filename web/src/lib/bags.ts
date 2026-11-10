import type { BagRow } from './db';

// A simple comparison, NOT a recommendation: the rules engine does not exist yet.
export type Signal = 'ah-higher' | 'close' | 'vendor-higher' | 'no-data';

export const SIGNAL_LABEL: Record<Signal, string> = {
  'ah-higher': 'AH higher',
  close: 'Close',
  'vendor-higher': 'Vendor ≥ AH',
  'no-data': 'No AH data',
};

export function signal(r: Pick<BagRow, 'vendor' | 'med'>): Signal {
  if (r.med === null || r.med === undefined) return 'no-data';
  const vendor = r.vendor ?? 0;
  if (vendor === 0 || r.med >= vendor * 1.5) return 'ah-higher';
  if (r.med <= vendor) return 'vendor-higher';
  return 'close';
}

// Listings under this count make a price unreliable.
export const THIN_LISTINGS = 5;
