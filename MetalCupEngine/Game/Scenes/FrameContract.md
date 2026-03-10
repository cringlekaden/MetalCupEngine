# Frame Contract

## Scene Update Modes

- Animation evaluation runs in `Edit`, `Simulate`, and `Play` scene modes.
- `Play` mode is still the only mode with full gameplay/runtime authority.
- `Edit` and `Simulate` animation updates are preview-only pose evaluation and do not imply gameplay/root-motion authority.

## Practical Implications

- Animator inspector controls (clip selection, play/pause, loop, speed, scrub) update visible skinned pose in Edit and Simulate.
- Script/gameplay systems remain gated by existing runtime policy and are not implicitly enabled by animation preview.
