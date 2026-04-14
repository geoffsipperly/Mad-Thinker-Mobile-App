---
description: Walk through adding a new species class to the ML pipeline without drift
---

A new species class must be updated in **three places in lockstep** or the app will ship with broken inference. Walk the user through this checklist. Do not skip steps even if the user says "just do the code part."

Target species (from $ARGUMENTS, or ask if missing): **$ARGUMENTS**

## Step 1 — Verify the model actually contains the new class
Before touching any code, confirm the shipped `ViTFishSpecies.mlpackage` was retrained with the new class. Ask the user:
- Has the model been retrained and re-exported?
- What is the new class count, and where does the new label fall in ImageFolder alphabetical order? (This determines its array index — it is **not** appended to the end.)

If the answer is no / unclear, STOP. Updating code against a model that doesn't know the class will produce silent misclassification.

## Step 2 — Update `speciesLabels` in `SkeenaSystem/Managers/CatchPhotoAnalyzer.swift`
- Read the current array.
- Insert the new label in the correct alphabetical position (matches training ImageFolder order).
- If the label uses the `<species>_<lifecycle>` pattern, confirm lifecycle is `holding` or `traveler` — `splitSpecies()` only parses those two trailing words.

## Step 3 — Update `speciesDisplayNames` in `SkeenaSystem/Models/CatchChatViewModel.swift`
- Add a mapping from the model label's species prefix to the user-facing display name (e.g. `"brook" -> "Brook Trout"`).
- If this species bypasses the length regressor (like `sea_run_trout`), note it and verify the heuristic fallback path handles it.

## Step 4 — Check the regressor path
- Re-estimation uses `speciesLabelToIndex(_:)` in `CatchPhotoAnalyzer.swift`. Inserting a label shifts every subsequent index.
- If `LengthRegressor.mlmodel` was trained against the old index mapping, it is now misaligned for every species after the insertion point. Confirm with the user whether the regressor was retrained alongside the ViT model. If not, STOP.

## Step 5 — Verify with a sync check
Read both files and confirm:
- Every entry in `speciesLabels` has a corresponding prefix in `speciesDisplayNames`.
- No stale entries in `speciesDisplayNames` that are no longer in `speciesLabels`.

## Step 6 — Tests
- Add or update any species-related tests.
- Run `/test` and report results.

## Step 7 — Summarize changes
Give the user a one-paragraph summary of what changed and flag any follow-ups (e.g., "the regressor still needs retraining before this can ship").
