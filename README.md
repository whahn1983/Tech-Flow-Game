# Tech Flow Game

## Proprietary Ownership

This software is owned by H3 Consulting Partners LLC, a Texas limited liability company. All rights reserved.

This program is proprietary software and is not open source. It may not be copied, modified, distributed, hosted, published, submitted to any marketplace, or used commercially without prior written permission from H3 Consulting Partners LLC. All music, audio, artwork, game design, source code, documentation, and related materials are owned by H3 Consulting Partners LLC or its licensors unless expressly stated otherwise in writing. See [LICENSE](LICENSE) for the full proprietary license terms.

## Overview

Tech Flow Runner is a fast-paced, neon circuit-board endless runner. You guide
the Tech Flow Runner across a glowing motherboard, leaping past hazards and
enemies while an original soundtrack drives the action. The objective is simple
to learn and hard to master: survive, build your combo, collect bits, and climb
the leaderboard.

The game is available on multiple platforms that share the same gameplay
identity. Platform-specific setup, deployment, and technical details live in
their own READMEs:

- **Web / PWA** — see [`web-app/README.md`](web-app/README.md)
- **Native iOS** — see [`TechFlowRunner/README.md`](TechFlowRunner/README.md)

## Gameplay

- The Runner auto-scrolls through the level at an ever-increasing pace.
- Time your **jumps** (including a **double jump**), **duck**, and **dash** to
  evade obstacles and enemies.
- Collect **bits** and chain actions to build a **combo multiplier** that boosts
  your score.
- Grab **power-ups** for temporary advantages.
- Push through **progressively harder** terrain and face a **Mainframe boss
  fight**.
- Compare your best runs on a **leaderboard**.

## Features

- **Dynamic Obstacles:** A variety of hazards and enemies, some of which move or
  change as you progress.
- **Collectible Bits & Combos:** Pick up bits and chain actions to multiply your
  score.
- **Power-Ups:** Temporary abilities that change how a run plays out.
- **Progressive Difficulty:** Each stretch ramps up speed and obstacle density,
  culminating in a boss encounter.
- **Scoring & Leaderboards:** Earn points for distance, speed, bits, and
  survival, then save your best runs to a leaderboard.
- **Original Soundtrack:** An original score owned by H3 Consulting Partners LLC.
- **Accessibility:** Pause support, reduced-motion handling, on-screen control
  fallbacks, and clear status messaging.

## Controls

Controls map naturally to each platform, but the core actions are the same
everywhere:

| Action          | How to perform it                          |
| --------------- | ------------------------------------------ |
| Jump / double jump | Keyboard jump key, tap, or on-screen button |
| Duck            | Hold down / swipe down / on-screen button   |
| Dash            | Dash key / swipe / on-screen button         |
| Pause / resume  | Pause key or on-screen button               |
| Restart         | Restart key after a run ends                |

See the platform READMEs for the exact key bindings and gestures.

## Project Structure

```
.
├── web-app/          # Browser game + PWA, leaderboard backends, web tooling
│                     #   → see web-app/README.md
├── TechFlowRunner/   # Native iOS app (Swift/SwiftUI/SpriteKit/GameKit)
│                     #   → see TechFlowRunner/README.md
├── docs/             # Static documentation pages
├── CHANGELOG.md      # Release notes
├── CONTRIBUTING.md   # Contributor guide
└── LICENSE           # Proprietary license terms
```

## Development

Each platform manages its own toolchain and build process; refer to the
platform READMEs above to get started.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full contributor guide and
[`CHANGELOG.md`](CHANGELOG.md) for release notes.

## License

This project is proprietary and owned exclusively by H3 Consulting Partners LLC, a Texas limited liability company. See [LICENSE](LICENSE) for the full license terms.

## Contact

For more information, licensing inquiries, bug reports, or feature requests, open an issue on [GitHub](https://github.com/whahn1983/Tech-Flow-Game/issues) or contact H3 Consulting Partners LLC through an official company communication channel.

For security issues, please open a private security advisory rather than a
public issue.
</content>
</invoke>
