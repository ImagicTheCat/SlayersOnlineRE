# Structure

This file is about how all the game data is managed.

## Server resources and data

The server needs all the Slayers Online project files in `resources/project/`.

Cache files are located into the `cache/` directory.

**Cache:**

- **`cache/maps/`:** Compiled map events (Lua bytecode). It is a manual cache; if a
  map is updated the file must be deleted. The whole cache must be deleted if
  the code generation changes.

## Client resources

All game's persistent resources are located in the `resources/` path, which is
a combination of multiple origins.

**Resource origins in reverse order:**

- **base game files:** base/default files
- **`resources_repository/` game data files (streaming):** resources acquired from
  the remote repository
- **`resources/` game data files:** can be used to customize the game resources

**Required base resources:**

- `audio/Cursor1.wav`
- `audio/Item1.wav`
- `font.ttf`
- `textures/phials.png`
- `textures/system.png`
- `textures/xp.png`
- `textures/mobile/quick1.png`
- `textures/mobile/quick2.png`
- `textures/mobile/quick3.png`
- `textures/mobile/stick.png`
- `textures/mobile/stick_cursor.png`
- `textures/mobile/attack.png`
- `textures/mobile/defend.png`
- `textures/mobile/interact.png`
- `textures/mobile/chat.png`
- `textures/sets/tileset.png` (default tileset on error)
- `textures/sets/charaset.png` (default charaset on error)
- `textures/loadings/...` (loading screens)
- `textures/title_screen.jpg`

### Repository / Streaming

To update the repository from the SO project, use `tools/update_repository.sh`.

- `Chipset\` images go to `textures/sets/`. Indexed PNGs are converted with
  proper alpha with `tools/convert_png.lua`.

    **Warning:** Not all indexed PNGs should be converted with an alpha
    channel; those need to be manually moved to the repository.

- `Sound\` files go to `audio/`; midi files are converted to Ogg/Vorbis using
  `tools/convert_midi.sh`.

**Client's updating process:**

- Check for the file in `repository.manifest` and `local.manifest`.
- Try to re-compute the hash from disk if missing.
- Download/update if the file is missing or if the hash is different.
