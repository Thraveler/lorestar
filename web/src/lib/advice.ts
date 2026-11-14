import type { AdviceInput } from './db';
import { evaluate, type Advice } from './rules.ts';

export interface Mismatch {
  id: number;
  name: string | null;
  web: Advice;
  inGame: NonNullable<AdviceInput['inGame']>;
}

// The web engine's advice for every bag item.
export function adviceByItem(inputs: AdviceInput[]): Map<number, Advice> {
  return new Map(inputs.map((i) => [i.item.id, evaluate(i.item, i.ctx)]));
}

// Items where what the addon recommended in game differs from what the web engine says now.
// Differences are expected when the data changed after the addon ran (a newer scan, more recipes).
export function compareAdvice(inputs: AdviceInput[], web: Map<number, Advice>): { compared: number; mismatches: Mismatch[] } {
  let compared = 0;
  const mismatches: Mismatch[] = [];
  for (const i of inputs) {
    const w = web.get(i.item.id);
    if (!w || !i.inGame) continue;
    compared += 1;
    const g = i.inGame;
    if (w.action !== g.action || w.keepQty !== (g.keep_qty ?? 0) || w.sellQty !== (g.sell_qty ?? 0)) {
      mismatches.push({ id: i.item.id, name: i.name, web: w, inGame: g });
    }
  }
  return { compared, mismatches };
}
