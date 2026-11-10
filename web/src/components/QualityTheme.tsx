import { useEffect, useState } from 'preact/hooks';

const QUALITIES = ['Poor', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'];

const THEMES = [
  { id: 'hybrid', label: 'Hybrid' },
  { id: 'official', label: 'Official WoW' },
  { id: 'earth', label: 'Earth tones' },
];

// Lets you compare the three quality-color sets; the choice is remembered in localStorage.
export default function QualityTheme() {
  const [theme, setTheme] = useState('hybrid');

  useEffect(() => {
    const saved = document.documentElement.dataset.quality;
    if (saved) setTheme(saved);
  }, []);

  function choose(id: string) {
    setTheme(id);
    document.documentElement.dataset.quality = id;
    try {
      localStorage.setItem('lorestar-quality', id);
    } catch {}
  }

  return (
    <div class="flex flex-wrap items-center gap-4">
      <label class="flex items-center gap-2 font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
        Quality colors
        <select
          value={theme}
          onChange={(e) => choose((e.target as HTMLSelectElement).value)}
          class="rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1 text-[var(--color-text)]"
        >
          {THEMES.map((t) => (
            <option value={t.id}>{t.label}</option>
          ))}
        </select>
      </label>
      <span class="flex items-center gap-3 font-heading text-xs">
        {QUALITIES.map((q, i) => (
          <span style={{ color: `var(--color-quality-${i})` }}>{q}</span>
        ))}
      </span>
    </div>
  );
}
