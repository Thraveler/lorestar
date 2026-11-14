import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { evaluate, type RuleItem, type RuleCtx, type RuleConfig } from './rules.ts';

interface Case {
  name: string;
  item: RuleItem;
  ctx?: RuleCtx;
  cfg?: Partial<RuleConfig>;
  expect: Record<string, unknown> & { notesInclude?: string[] };
}

// The same file the Lua advisor is tested against: both engines must agree on every case.
const file = new URL('../../../tests/rules_cases.json', import.meta.url);
const cases: Case[] = JSON.parse(readFileSync(file, 'utf8')).cases;

test('the shared case file is loaded', () => {
  assert.ok(cases.length >= 15);
});

for (const c of cases) {
  test(c.name, () => {
    const result = evaluate(c.item, c.ctx ?? {}, c.cfg ?? {}) as unknown as Record<string, unknown>;
    for (const [field, want] of Object.entries(c.expect)) {
      if (field === 'notesInclude') {
        for (const note of want as string[]) assert.ok((result.notes as string[]).includes(note), `missing note ${note}`);
      } else {
        assert.equal(result[field], want, field);
      }
    }
  });
}
