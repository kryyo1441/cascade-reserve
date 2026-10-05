// Minimal self-check for the decimal-conversion helpers - the one place a wrong divisor
// silently shows numbers 1,000,000x off instead of erroring. Run with `npx tsx lib/format.test.ts`.
import assert from "node:assert";
import { fmtEurs, fmtNotes, fmtWadPct, fmtWeight, shortAddr } from "./format";

assert.strictEqual(fmtEurs("1000"), "10 EURS"); // 1000 raw / 1e2 = 10 EURS
assert.strictEqual(fmtNotes("1000000000"), "10 notes"); // 1e9 raw / 1e8 = 10 notes
assert.strictEqual(fmtWadPct("278095238095238095238"), "27,809.52%");
assert.strictEqual(fmtWeight("1000000000000000000"), "100%");
assert.strictEqual(fmtWeight("0"), "0%");
assert.strictEqual(shortAddr("0x72B49a461900e11632C95dfa563e7173438D4e3E"), "0x72B4…4e3E");

console.log("format.test.ts: all assertions passed");
