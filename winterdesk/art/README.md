# Background paintings

The backgrounds are painted in code (Python with numpy + Pillow), so they are original and reproducible.

```bash
cd winterdesk/art
python3 scene_cabin.py && python3 scene_fireplace.py && python3 scene_village.py && python3 scene_aurora.py
```

Each script writes `../Resources/bg-<name>.jpg` and `bg-<name>.json`. The JSON lists where the
animated touches go (twinkling lights, window glows, chimney smoke, the fire, candles, aurora bands),
as fractions of the picture's width/height measured from its top-left corner.
