# shader-movie-

The first 30 seconds of *Super Silas*, rebuilt as a single procedural GLSL fragment shader:
no textures, no video frames, only distance fields, noise and light. Made with the
[shader-skills](https://github.com/gokayfem/shader-skills) GLSL library.

| File | What it is |
|---|---|
| `shader/super-silas.glsl` | The source, written against the shader-skills library by function name. |
| `shader/super-silas.out.glsl` | The bundled, self-contained shader. Paste it into [Shadertoy](https://www.shadertoy.com/new) and press play. |
| `tools/render.py` | Renders the shader to MP4 in headless Chromium (WebGL2) and lays the original audio under it. |

The original film is attached to the `R1` release. It is not stored in the repository.

## Shots

| Film time | Shot |
|---|---|
| 0:00 | Close flight over sunset clouds |
| 0:01.75 | Wide flight toward the sun |
| 0:06 | Forest with fireflies |
| 0:10.5 | A mossy root sweeps past |
| 0:11.25 | Low over a sparkling stream |
| 0:12.5 | Big tree and sunlit clearing |
| 0:16 | The knight and the robot wave |
| 0:19 | Backlit forest |
| 0:21 | Pink dusk over the pines |
| 0:25 | The cabin, the catch, the hug |

## Rebuild and render

```sh
git clone --depth 1 https://github.com/gokayfem/shader-skills
python3 shader-skills/skills/shader-art-coding/scripts/glsl_tools.py bundle shader/super-silas.glsl -o shader/super-silas.out.glsl
pip install playwright
python3 tools/render.py shader/super-silas.out.glsl out.mp4 --w 960 --h 540 --dur 30 --audio original.mp4
```

`render.py` looks for Chromium at `/opt/pw-browsers/chromium`. Edit `executable_path` in the script to point at your own copy.

## Tuning

The constants at the top of `super-silas.glsl` control the look: `FOCAL`, `EXPOSURE`, `CAPE_SPEED`, `GRAIN`
and the `C_*` character colors. `setupShot()` holds the edit. Each shot sets Silas's position, scale, yaw
and tilt (0 is an upright hover, 1 is flying flat), plus that shot's key, fill and rim light.
Set `DEBUG_MODE` to 1 for normals or 2 for material ids. Set `LOOP` to 1 to loop it on Shadertoy.
