# zocdoc-search

Playwright script that searches Zocdoc for NYC neurologists and pulmonologists
who accept Aetna and offer video visits, then writes `results.json`,
`results.md`, and a screenshot per specialty.

```sh
npm i playwright            # or use a global install via NODE_PATH
node search.mjs             # both specialties
node search.mjs neurologists
HEADED=1 node search.mjs    # watch the browser
```

Zocdoc's markup changes often. If the script reports zero cards, open the
screenshot and adjust the selectors in `scrapeCards`.
