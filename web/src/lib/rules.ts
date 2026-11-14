// The advisor rules. This is a port of A.evaluate in Lorestar/Lorestar_Advisor.lua: both are tested
// against tests/rules_cases.json, so change them together. All prices are copper per unit.

export interface RuleItem {
  id: number;
  qty: number;
  quality?: number | null;
  classID?: number | null;
  vendor?: number | null;
  stack?: number | null;
  bound?: boolean | null;
}

export interface RulePrice {
  med?: number | null;
  p10?: number | null;
  m?: number | null;
  n?: number | null;
  q?: number | null;
}

export interface RuleRecipes {
  learnedCount?: number | null;
  learnedMax?: number | null;
  unlearnedCount?: number | null;
}

export interface RuleCtx {
  price?: RulePrice | null;
  recipes?: RuleRecipes | null;
  freeSlots?: number | null;
}

export interface RuleConfig {
  ahCut: number;
  ahRatio: number;
  minGainPerItem: number;
  minListings: number;
  craftsToKeep: number;
  saturation: number;
  lowFreeSlots: number;
  maxSpread: number;
  keepIds: number[];
}

export type Action = 'keep' | 'sell_ah' | 'vendor' | 'discard' | 'review';
export type Confidence = 'high' | 'medium' | 'low';

export interface Advice {
  action: Action;
  keepQty: number;
  sellQty: number;
  unit: number;
  total: number;
  reason: string;
  confidence: Confidence;
  notes: string[];
  slotsFreed: number;
}

export const DEFAULTS: RuleConfig = {
  ahCut: 0.05, // the Auction House keeps this share of a sale
  ahRatio: 1.5, // the AH price (after the cut) must be at least this many times the vendor price
  minGainPerItem: 2, // and beat the vendor by at least this much per unit
  minListings: 3, // fewer listings than this: the AH price is not reliable
  craftsToKeep: 10, // keep reagents for this many crafts of the recipes you know
  saturation: 0.25, // holding more than this share of the listed units: selling would move the price
  lowFreeSlots: 4, // at or below this many free slots, worthless items are discarded
  maxSpread: 4, // median above this many times the p10: the median is not trusted, the p10 is used
  keepIds: [6948], // Hearthstone
};

export const REASONS: Record<string, string> = {
  keep_list: 'On the keep list',
  quest: 'Quest item',
  recipe_item: 'Recipe or pattern: learn it or sell it, your call',
  reagent_learned: 'Reagent for a recipe you know',
  ah_better: 'The Auction House pays clearly more than the vendor',
  ah_only: 'The vendor pays nothing, the Auction House has a price',
  vendor_better: 'The vendor pays about the same as the Auction House',
  vendor_only: 'No Auction House price known',
  bound_vendor: 'Bound to you: it cannot be auctioned',
  no_value: 'No sell value',
};

export const NOTES: Record<string, string> = {
  unlearned_recipes: 'used by recipes you have not learned',
  check_upgrade: 'gear: check that it is not an upgrade first',
  thin_market: 'few Auction House listings: the price is not reliable',
  saturation: 'you hold a big share of the market: the price would drop',
  wide_spread: 'the median is far above the cheap end: priced at the cheap end instead',
};

export const ACTION_LABEL: Record<Action, string> = {
  keep: 'Keep',
  sell_ah: 'Sell on AH',
  vendor: 'Vendor',
  discard: 'Discard',
  review: 'Review',
};

export function evaluate(item: RuleItem, ctx: RuleCtx = {}, over: Partial<RuleConfig> = {}): Advice {
  const cfg = { ...DEFAULTS, ...over };
  const qty = item.qty ?? 0;
  const vendor = item.vendor ?? 0;
  const stack = item.stack ?? 1;
  const price = ctx.price ?? null;
  const recipes = ctx.recipes ?? {};
  const notes: string[] = [];

  const result = (action: Action, keepQty: number, sellQty: number, unit: number, reason: string, confidence: Confidence): Advice => {
    let slotsFreed = 0;
    if (sellQty > 0 && (action === 'sell_ah' || action === 'vendor' || action === 'discard')) {
      slotsFreed = Math.ceil(qty / stack) - Math.ceil(keepQty / stack);
    }
    return { action, keepQty, sellQty, unit, total: sellQty * unit, reason, confidence, notes, slotsFreed };
  };

  if (cfg.keepIds.includes(item.id)) return result('keep', qty, 0, 0, 'keep_list', 'high');
  if (item.classID === 12) return result('keep', qty, 0, 0, 'quest', 'high');
  if (item.classID === 9) return result('review', qty, 0, 0, 'recipe_item', 'medium');

  let keepQty = 0;
  if ((recipes.learnedCount ?? 0) > 0) keepQty = Math.min(qty, (recipes.learnedMax ?? 1) * cfg.craftsToKeep);
  const surplus = qty - keepQty;
  if (surplus <= 0) return result('keep', qty, 0, 0, 'reagent_learned', 'high');

  if ((recipes.unlearnedCount ?? 0) > 0) notes.push('unlearned_recipes');
  if ((item.quality ?? 0) >= 2 && (item.classID === 2 || item.classID === 4)) notes.push('check_upgrade');

  // Some markets are bimodal: most units listed at silly prices while the cheap ones are what sells.
  let ref = price && price.med != null ? price.med : null;
  let wide = false;
  if (ref !== null && price && price.p10 != null && price.p10 > 0 && ref > price.p10 * cfg.maxSpread) {
    ref = price.p10;
    wide = true;
  }
  const net = ref !== null ? ref * (1 - cfg.ahCut) : null;
  const thin = price !== null && (price.n ?? 0) < cfg.minListings;
  const saturated = price !== null && (price.q ?? 0) > 0 && surplus > cfg.saturation * (price.q ?? 0);

  if (net !== null && !item.bound && (vendor === 0 || net >= vendor * cfg.ahRatio) && net - vendor >= cfg.minGainPerItem) {
    let confidence: Confidence = 'high';
    if (wide) {
      confidence = 'low';
      notes.push('wide_spread');
    }
    if (thin) {
      confidence = 'low';
      notes.push('thin_market');
    } else if (saturated && confidence === 'high') {
      confidence = 'medium';
    }
    if (saturated) notes.push('saturation');
    return result('sell_ah', keepQty, surplus, Math.floor(net), vendor === 0 ? 'ah_only' : 'ah_better', confidence);
  }

  if (vendor > 0) {
    let reason = 'vendor_only';
    if (item.bound && price) reason = 'bound_vendor';
    else if (price) reason = 'vendor_better';
    return result('vendor', keepQty, surplus, vendor, reason, 'high');
  }

  let action: Action = (ctx.freeSlots ?? 99) <= cfg.lowFreeSlots ? 'discard' : 'review';
  if ((recipes.unlearnedCount ?? 0) > 0) action = 'review';
  return result(action, keepQty, surplus, 0, 'no_value', 'medium');
}
