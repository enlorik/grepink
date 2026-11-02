# Claim-specific evidence and research workspace

Diagnosis:
- The extractor copied all answer URLs to claims without citation ranges.
- Claim previews chose the first snippet for each URL, collapsing different quotes.
- Saved metadata and insertion merged by URL, losing claim/excerpt associations.
- The page reader omitted images and could present a keyword match as relevant evidence.
- Research shared the screen with both the original note and its evidence rail.

Tasks:
- [x] Carry the provider's overlapping citation records through extraction and review.
- [x] Persist distinct claim, URL and quote associations through saving and insertion.
- [x] Stop reusing the previous quote for a claim with no mapped evidence.
- [x] Show cited excerpts separately from exact page matches and unverified related text.
- [x] Extract useful article figures with captions, bounded public raster downloads and fallbacks.
- [x] Give research its own full-width workspace with answer + evidence and a return-to-note action.
- [ ] Test same-page/different-quote claims, unknown mappings, persistence, images and research navigation.
- [ ] Inspect rendered fixtures, verify CI and publish preview downloads.

Citation ranges and snippets come from the configured provider; matching text in
a page confirms that it appears there, not that the claim is logically proven.
Legacy notes without per-claim metadata cannot recover missing provider mappings.
Figures are website illustrations, not independent supporting evidence.

Provider reference: https://api-dashboard.search.brave.com/documentation/services/answers
