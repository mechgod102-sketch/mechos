# MechScope UI migration guardrails

1. `src/mechscope/mechscope_shell.py` owns visual composition.
2. Build/integration scripts may connect runtime callbacks and package the shell.
3. No later script may replace `MechScope.build_ui()` with a nested layout dashboard.
4. VM compatibility may change rendering flags, never the authored geometry.
5. The shell preserves a 16:9 design canvas and letterboxes at other aspect ratios.
