# APH-Search

*Search settings, keybinds, add-ons, items, skills, champion stars, the map, quests, achievements, menus and slash commands, and jump straight to what you picked, and you can also find your friends and share waypoints with your group.*

## Dependencies

Requires **LibAPH** (shared helper library, hard dependency).

Optionals for additional features:
- **LibAddonMenu-2.0:** required for the PC Settings Menu.
- **LibHarvensAddonSettings:** required for the Console Settings Menu.
- **LibImplex:** arrows on the ground and names in the world for the guide.
- **LibGroupBroadcast:** shares waypoints and wayshrine travel with your group.
- **APH-Search Map Data:** roads and walkable ground for every map, so the guide can follow paths.

Without the optional dependencies, the addon still runs entirely independently and can be controlled via built-in slash commands as a standalone utility.

## Slash Commands

- `/fs`: opens the search bar.
- `/fsguide`: turns the guide on or off. `/fsguide clear` removes where it is leading you, `/fsguide quest` shares the quest you track with your group, and `/fsguide next` follows the next group member, and `/fsguide record` starts or stops recording a road.

**Console Testing Notes:** This addon was developed and tested on **PC / Steam Deck** (using Force Console Flow for console testing).

## License

Copyright © 2026 @APHONlC. All rights reserved. See LICENSE.md

This add-on is not created by, affiliated with, or sponsored by ZeniMax Media Inc. or its affiliates. The Elder Scrolls® and related logos are registered trademarks or trademarks of ZeniMax Media Inc. in the United States and/or other countries. All rights reserved.

For permissions or inquiries, contact @APHONlC on ESOUI.

## Credits

I would like to thank the following, for providing resources and their awesome projects:

- ESOUI Wiki
- @sirinsidiator
- @Flat-Badger-1971
- @sirinsidiator & @Seerah (LibAddonMenu-2.0)
- @Harven & @votan (LibHarvensAddonSettings)
- @sirinsidiator (LibGroupBroadcast)
- @imPDA (LibImplex)
- @SinusPi, @merlight, @Rhyono, @Dolgubon (Zgoo High Isle)
- @Baertram (Mer Torchbug - Fixed and Improved "Variable inspector/Scripts/Events/and more")

Testers & Suggestions:
- @Drakius192

Check out my other addons/projects:
- Auto Lua Memory Cleaner
- Permanent Memento
- Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater (Linux, macOS, SteamDeck, & Windows)

## Bug Reports

If you encounter any issues, please submit a report on ESOUI
