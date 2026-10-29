# Art and sound provenance

The Pikmin names and character designs belong to Nintendo. This personal implementation draws those characters with original SwiftUI vector paths; it does not bundle extracted game sprites, promotional image files, or game audio. The character drawings remain derivative fan art, not a claim to ownership of Nintendo's designs.

Visual references inspected during development:

- [Nintendo's official Pikmin lineup](https://assets.topics.apps-jp.nintendo.com/image/2023/06/29060649907554/0/014.jpg): distinguishing anatomy and species features.
- [Archived Nintendo flat Pikmin wallpaper](https://repo.mariocube.com/Wallpapers/unsorted/nintendo.co.jp/22_HBD_Pikmin_1536_2048.jpg): flat proportions and silhouette reference.
- [Nintendo's Glow Pikmin artwork](https://assets.nintendo.com/image/upload/f_png,c_limit,w_700/Marketing/microsite-pikmin-4-holiday/layouts/meetpikmin/glow-2x.png), from [the official Pikmin 4 site](https://pikmin4.nintendo.com/): rounded teardrop head, asymmetric blue eyes, cyan pupil, and pointed yellow flower. The ghost tail belongs to the body, not the head.

`PikminArt.swift` contains the authored paths. `SpriteLibrary.swift` renders those same paths for the external Antille host. `Chirps.swift` synthesizes original short PCM sounds, including the docking pop; it does not sample Nintendo audio.

The runtime island engine is independently authored [Antille](https://github.com/Upsidedly/antille), a Swift package dependency also released under MPL-2.0. No extracted reference-app source or binary is included as a runtime dependency.

## Top and contrast audit — October 27, 2026

The official-photo audit used the references above for all nine species. Corrected profiles retain each species’ stalk proportions, Rock’s light gray-green stalk, the white/pink/violet/yellow flower families, elongated buds, and Glow’s long sprout and pointed yellow flower. Default is a deliberate reference presentation; authentic Leaf, Bud, and Flower remain selectable. Nintendo also depicts Glow in bud form, so the flower default is not a claim that it has no other growth state. Local comparison captures are not bundled in this repository.

Body contours use a darker shade of the species color; leaves, petals, and stems have corresponding material-colored edges. [DuduClaw’s transparent pet-window implementation](https://os.duduclaw.dudustudio.monster/docs/en/features/35-photo-desktop-pet/) and [Desktop-Pets](https://github.com/LGaben/Desktop-Pets) informed the transparent-window comparison. No pet source or assets were copied. Pikminions keeps panel shadows disabled and draws contrast into the character pixels.

`AppIcon.swift` composes an authored Red Pikmin with a slight tilt and wink. The light-gray 904/1024 tile, 60-point inset, and 205-point corner radius match Matthew’s local Tuck and Snap icon family. Their code and assets were inspected read-only; the Pikmin composition and Antille island mark were drawn for these projects.

The MPL-2.0 grant covers the author's original code and contributions, not rights in Nintendo's underlying character designs or trademarks. Rights concerns and takedown requests can be sent to [matthewlloydw@gmail.com](mailto:matthewlloydw@gmail.com).
