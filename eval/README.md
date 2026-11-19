# Prompt eval

Measures the quality levels (model, effort and instruction add-on) on a fixed set of cases, so prompt changes can be re-tested.

- `cases.json`: 32 cases. Czech and English text written by a Ukrainian speaker (calques, word order, missing se/si, articles, prepositions, collocations), already-natural control texts that must stay nearly unchanged, casual chat that must stay casual, a formal email in each language, 6 translations (Czech to English, English to Czech, Ukrainian to Czech) and 2 typed instructions. Each case has `id`, `kind` (`grammar`, `translate` or `instruction`), `group` (report grouping), `target` (translate) or `instruction`, `text` and a `note` on what a native editor would fix (the judge sees it as a hint).
- `run.py`: builds the system prompt like `Engine.systemPrompt` (action prompt, then the level add-on, then the content rules), wraps the text like `Engine.wrap`, runs `claude -p` with the app's flags from a temp directory (4 at a time), applies `Engine.checkLayout`, then has `opus` score every output blind (identical outputs merged, order shuffled, config hidden) on errors fixed, naturalness, meaning, register and over-editing (5 = none).
- `results/`: committed reports. Drafts, raw JSON and the call cache go to `results/draft/` (ignored by git).

## Run

```sh
python3 -I eval/run.py
python3 -I eval/run.py --configs medium,sonnet-base,high-low,high-medium,max-medium,max-high
python3 -I eval/run.py --cases cs-missing-se,en-give-me-know --no-judge
```

Defaults to the chosen levels (`medium,high-medium,max-high`). Configs, add-ons and the judge model live at the top of `run.py`. The prompt strings there are copies of `Settings.swift` and `Engine.swift`; the script warns when they drift. Outputs and judge scores are cached by model, effort, system prompt and text, so a re-run only calls Claude for what changed (delete `results/draft/cache.json` for fresh samples).

## Levels

Medium: `haiku`, no `--effort`, no add-on (today's prompts). High: `sonnet`, effort `medium`, the `high` add-on. Max: `opus`, effort `medium`, the `max` add-on. The add-on goes right after the action prompt, before the content rules. Effort `low` for High and `high` for Max scored the same or lower in the draft passes; latest results: `results/2026-11-19-142544.md`.

## Cost

Calls go through your own Claude Code login: on a subscription they count against your plan's limits, with an API key they are billed. A full pass of 3 levels is about 130 calls (96 outputs, 32 opus judge calls); the report shows the list-price equivalent per config.

## Caveats

One sample per case and a single judge: differences under about 0.2 are noise. The judge is `opus`, the same model as Max, so it may favour Max slightly.
