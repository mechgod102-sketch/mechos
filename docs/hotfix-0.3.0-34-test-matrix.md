# Hotfix 34 MechScope target resolution matrix

The authored shell remains based on 1672x941 and scales uniformly.

| Target | Scale floor | Quick Action row | Quick Action width | GPU/status width |
| --- | ---: | ---: | ---: | ---: |
| 1280x720 | ~0.765 | ~31 px | ~383 px | ~383 px |
| 1600x900 | ~0.956 | ~39 px | ~478 px | ~478 px |
| 1920x1080 | ~1.147 | ~47 px | ~574 px | ~574 px |

CI enforces minimum geometry so future edits cannot silently return the 720p/900p clipping shown before Hotfix 34.
