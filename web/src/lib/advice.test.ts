import { test } from 'node:test';
import assert from 'node:assert/strict';
import { adviceByItem, compareAdvice } from './advice.ts';
import type { AdviceInput } from './db.ts';

const input = (id: number, qty: number, vendor: number, inGame: AdviceInput['inGame']): AdviceInput => ({
  name: `Item ${id}`,
  item: { id, qty, quality: 1, classID: 7, vendor, stack: 20, bound: false },
  ctx: { price: null, recipes: { learnedCount: 0, learnedMax: 0, unlearnedCount: 0 }, freeSlots: 10 },
  inGame,
});

test('items without saved in-game advice are not compared', () => {
  const inputs = [input(1, 5, 10, null)];
  const { compared, mismatches } = compareAdvice(inputs, adviceByItem(inputs));
  assert.equal(compared, 0);
  assert.equal(mismatches.length, 0);
});

test('matching advice produces no mismatches', () => {
  const inputs = [input(1, 5, 10, { action: 'vendor', keep_qty: 0, sell_qty: 5, unit: 10, reason: 'vendor_only', confidence: 'high' })];
  const { compared, mismatches } = compareAdvice(inputs, adviceByItem(inputs));
  assert.equal(compared, 1);
  assert.equal(mismatches.length, 0);
});

test('a different action or quantity is reported', () => {
  const inputs = [
    input(1, 5, 10, { action: 'sell_ah', keep_qty: 0, sell_qty: 5, unit: 30, reason: 'ah_better', confidence: 'high' }),
    input(2, 5, 10, { action: 'vendor', keep_qty: 2, sell_qty: 3, unit: 10, reason: 'vendor_only', confidence: 'high' }),
  ];
  const { compared, mismatches } = compareAdvice(inputs, adviceByItem(inputs));
  assert.equal(compared, 2);
  assert.deepEqual(mismatches.map((m) => m.id), [1, 2]);
});
