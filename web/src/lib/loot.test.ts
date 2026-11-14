import { test } from 'node:test';
import assert from 'node:assert/strict';
import { groupBySource, groupByPlace, cellPercent } from './loot.ts';
import type { LootRecord } from './db.ts';

const rec = (over: Partial<LootRecord>): LootRecord => ({
  map_id: 1442, zone: 'Stonetalon Mountains', cell_x: 26, cell_y: 23, source: 'obj:1731', source_type: 'obj', source_id: 1731,
  opens: 4, subzone: 'Mirkfallon Lake', items: [], ...over,
});
const item = (item_id: number, qty: number, med: number | null, vendor: number | null, name = `Item ${item_id}`) => ({
  item_id, qty, name, vendor, med, listings: med === null ? null : 10,
});

test('a source is merged across places and its value is per window opened', () => {
  const groups = groupBySource([
    rec({ cell_x: 26, opens: 4, items: [item(2770, 4, 100, 5)] }),
    rec({ cell_x: 27, opens: 6, items: [item(2770, 6, 100, 5), item(2589, 2, 20, 13)] }),
    rec({ source: 'npc:4018', source_type: 'npc', source_id: 4018, opens: 2, items: [item(5000, 3, null, 10)] }),
  ]);
  const obj = groups.find((g) => g.key === 'obj:1731')!;
  assert.equal(obj.opens, 10);
  assert.equal(obj.places.length, 2);
  assert.equal(obj.items.find((i) => i.item_id === 2770)!.qty, 10);
  assert.equal(obj.ahValue, 10 * 100 + 2 * 20);
  assert.equal(obj.ahPerOpen, 104);
  assert.equal(obj.vendorValue, 10 * 5 + 2 * 13);
  assert.equal(obj.label, 'Object #1731');
  assert.equal(obj.items[0].item_id, 2770); // sorted by AH value
  assert.equal(obj.anyUnpriced, false);
});

test('items without an AH price count as zero and are flagged', () => {
  const [g] = groupBySource([rec({ source: 'npc:4018', source_type: 'npc', source_id: 4018, opens: 2, items: [item(5000, 3, null, 10), item(5001, 1, 50, 2)] })]);
  assert.equal(g.ahValue, 50);
  assert.equal(g.anyUnpriced, true);
  assert.equal(g.type, 'npc');
  assert.equal(g.items.find((i) => i.item_id === 5000)!.perOpen, 1.5);
});

test('grouping by place merges the sources looted in the same cell', () => {
  const groups = groupByPlace([
    rec({ items: [item(1, 1, 100, 1)] }),
    rec({ source: 'npc:4018', source_type: 'npc', source_id: 4018, opens: 1, items: [item(2, 1, 40, 1)] }),
    rec({ cell_x: 10, opens: 3, items: [item(1, 3, 100, 1)] }),
  ]);
  assert.equal(groups.length, 2);
  const cell = groups.find((g) => g.key === '1442|26|23')!;
  assert.equal(cell.opens, 5);
  assert.equal(cell.items.length, 2);
  assert.match(cell.label, /Stonetalon Mountains · Mirkfallon Lake/);
  assert.match(cell.label, /x 53% · y 47%/);
  assert.deepEqual(cell.sources.map((x) => [x.source, x.opens]), [['obj:1731', 4], ['npc:4018', 1]]);
});

test('an unknown position and an unknown source are labelled', () => {
  const [place] = groupByPlace([rec({ cell_x: -1, cell_y: -1, source: '?', source_type: null, source_id: null, items: [item(1, 1, 10, 1)] })]);
  assert.match(place.label, /Unknown position/);
  const [source] = groupBySource([rec({ source: '?', source_type: null, source_id: null })]);
  assert.equal(source.label, 'Unknown source');
  assert.equal(source.type, 'unknown');
});

test('cell percentages and an empty list', () => {
  assert.equal(cellPercent(0), 1);
  assert.equal(cellPercent(49), 99);
  assert.equal(cellPercent(-1), null);
  assert.deepEqual(groupBySource([]), []);
});
