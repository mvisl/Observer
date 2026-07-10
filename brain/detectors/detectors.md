# Detector Definitions

Detectors are deterministic first. They produce hypotheses, not facts.

## frequent_app_switching

Signal:

- many `appFocus` events;
- at least two distinct apps.

Interpretation:

- possible comparison work;
- possible lost context.

Default behavior:

- write `detectorFired`;
- create quiet `hintCandidate`;
- do not interrupt.

## return_loop

Signal:

- repeated return to same app/context.

Interpretation:

- possible blocker;
- possible iterative work.

Default behavior:

- suggest collecting context quietly.

## reading_or_thinking

Signal:

- no input for threshold;
- optional face present signal.

Interpretation:

- reading, thinking, or watching.

Default behavior:

- mark as do-not-interrupt.
