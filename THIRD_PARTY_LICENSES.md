# Third-party notices

TermLaunch embeds GhosttyKit (libghostty), built from the Ghostty source in `vendor/ghostty`, and ships Ghostty's shell-integration scripts and theme collection.

## Ghostty

MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Components bundled with Ghostty

GhosttyKit statically links, or embeds, the components below. Each is used under its own license; the full texts are in the upstream projects named here.

| Component | License |
|---|---|
| libxev, zigimg, uucode, zig-objc, dcimgui (Dear ImGui) | MIT |
| z2d | MPL-2.0 |
| FreeType | FreeType License (FTL) or GPL-2.0, used under the FTL |
| HarfBuzz | MIT (Old MIT) |
| libpng | PNG Reference Library License |
| zlib | zlib License |
| Oniguruma | BSD-2-Clause |
| simdutf | MIT or Apache-2.0 |
| Highway | Apache-2.0 or BSD-3-Clause |
| Wuffs | Apache-2.0 |
| glslang | BSD-3-Clause and related permissive licenses |
| SPIRV-Cross | Apache-2.0 |
| libxml2 | MIT |
| Sentry Native, Breakpad | MIT, BSD-3-Clause |
| JetBrains Mono (embedded font) | SIL Open Font License 1.1, Copyright 2020 The JetBrains Mono Project Authors |
| Nerd Fonts Symbols Only (embedded font) | MIT, Copyright (c) Ryan L McIntyre and Nerd Fonts contributors |
| iTerm2-Color-Schemes (theme collection in `ghostty/themes`) | MIT, Copyright (c) Mark Badolato and contributors; individual themes remain the work of their authors |

The FreeType License requires this credit: portions of this software are copyright (c) The FreeType Project (www.freetype.org). All rights reserved.
