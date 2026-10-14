// Writes test/golden/segments.json: how the desktop's Intl.Segmenter splits test/golden/corpus.txt
// into sentences and words. Node built-ins only. Run: node tool/segmenter_golden.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const corpus = readFileSync('test/golden/corpus.txt', 'utf8').replace(/\r\n/g, '\n');
// One paragraph per line, plus the whole file once so that line breaks are covered too.
const texts = [...corpus.split('\n').filter((line) => line !== ''), corpus];

const split = (locale, granularity, text) =>
  Array.from(new Intl.Segmenter(locale, { granularity }).segment(text), (s) => ({
    index: s.index,
    segment: s.segment,
    ...(granularity === 'word' ? { isWordLike: s.isWordLike } : {}),
  }));

const golden = [];
for (const granularity of ['sentence', 'word']) {
  for (const text of texts) {
    const en = split('en', granularity, text);
    // The reader passes the document language; ICU applies no tailoring for either.
    if (JSON.stringify(en) !== JSON.stringify(split('de', granularity, text))) {
      throw new Error(`en and de differ for: ${text}`);
    }
    golden.push({ granularity, text, segments: en });
  }
}
writeFileSync('test/golden/segments.json', JSON.stringify(golden, null, 1) + '\n');
console.log(`${golden.length} cases, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}`);
