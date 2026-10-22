#!/usr/bin/env python3
"""Render the editable Pomodoro Float brand SVGs into macOS-ready assets."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"
OUT.mkdir(parents=True, exist_ok=True)


def svg(content: str, width: int = 1024, height: int = 1024) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">\n{content}\n</svg>\n'
    )


DEFS = """<defs>
  <linearGradient id="front" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#383D40"/><stop offset="0.42" stop-color="#24292C"/>
    <stop offset="1" stop-color="#171A1D"/>
  </linearGradient>
  <linearGradient id="top" x1="0" y1="0" x2="0.9" y2="1">
    <stop stop-color="#464B4D"/><stop offset="1" stop-color="#292D30"/>
  </linearGradient>
  <linearGradient id="side" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#202427"/><stop offset="1" stop-color="#0D0F11"/>
  </linearGradient>
  <linearGradient id="progress" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#FFB469"/><stop offset="0.58" stop-color="#F2944B"/>
    <stop offset="1" stop-color="#E77739"/>
  </linearGradient>
  <radialGradient id="faceWarmth">
    <stop stop-color="#E98345" stop-opacity="0.13"/>
    <stop offset="1" stop-color="#E98345" stop-opacity="0"/>
  </radialGradient>
</defs>"""


FRONT_CUBE = """<ellipse cx="517" cy="872" rx="326" ry="35" fill="#000" opacity="0.16"/>
<path d="M150 275 285 149Q301 132 325 132H836Q854 132 869 150L725 275Z" fill="url(#top)"/>
<path d="M725 275 869 150V676Q869 699 851 716L725 852Z" fill="url(#side)"/>
<path d="M150 275H725V817Q725 852 690 852H185Q150 852 150 817Z" fill="url(#front)"/>
<path d="M150 275H725M725 275 869 150M725 275V817Q725 852 690 852" fill="none" stroke="#62696B" stroke-opacity="0.38" stroke-width="3"/>
<path d="M151 283V813Q151 851 188 851" fill="none" stroke="#677073" stroke-opacity="0.36" stroke-width="3"/>
<circle cx="438" cy="562" r="236" fill="url(#faceWarmth)"/>
<circle cx="438" cy="562" r="180" fill="none" stroke="#0C0F11" stroke-opacity="0.83" stroke-width="52"/>
<circle cx="438" cy="562" r="180" fill="none" stroke="url(#progress)" stroke-width="48"
  stroke-linecap="round" stroke-dasharray="822 309" transform="rotate(-90 438 562)"/>"""


TOP_CUBE = """<ellipse cx="510" cy="857" rx="315" ry="34" fill="#000" opacity="0.15"/>
<path d="M512 145 858 316 512 488 166 316Z" fill="url(#top)" stroke="#606669" stroke-opacity="0.44" stroke-width="3"/>
<path d="M166 316 512 488V856L185 690Q166 679 166 653Z" fill="url(#front)"/>
<path d="M858 316 512 488V856L839 690Q858 679 858 653Z" fill="url(#side)"/>
<path d="M166 316 512 488 858 316M512 488V856" fill="none" stroke="#697073" stroke-opacity="0.35" stroke-width="3"/>
<ellipse cx="512" cy="316" rx="183" ry="91" fill="none" stroke="#17191B" stroke-width="47"/>
<ellipse cx="512" cy="316" rx="183" ry="91" fill="none" stroke="url(#progress)"
  stroke-width="42" stroke-linecap="round" stroke-dasharray="669 210" transform="rotate(-25 512 316)"/>"""


ORBIT_CUBE = """<ellipse cx="514" cy="835" rx="272" ry="31" fill="#000" opacity="0.15"/>
<circle cx="512" cy="493" r="347" fill="none" stroke="#27292A" stroke-width="49"/>
<circle cx="512" cy="493" r="347" fill="none" stroke="url(#progress)" stroke-width="47"
  stroke-linecap="round" stroke-dasharray="1580 600" transform="rotate(-92 512 493)"/>
<path d="M280 320 392 215H705Q721 215 735 229L630 333Z" fill="url(#top)"/>
<path d="M630 333 735 229V640Q735 656 723 669L630 762Z" fill="url(#side)"/>
<path d="M280 320H630V739Q630 762 607 762H303Q280 762 280 739Z" fill="url(#front)"/>
<path d="M280 320H630L735 229M630 320V739" fill="none" stroke="#636A6C" stroke-opacity="0.44" stroke-width="3"/>"""


def write(name: str, content: str, width: int = 1024, height: int = 1024) -> Path:
    path = OUT / name
    path.write_text(svg(content, width, height), encoding="utf-8")
    return path


def raster(source: Path, destination: Path) -> None:
    subprocess.run(["sips", "-s", "format", "png", str(source), "--out", str(destination)],
                   check=True, capture_output=True)


def logo_body(dark: bool) -> str:
    main = "#F4F1EB" if dark else "#25292C"
    accent = "#F3A05D" if dark else "#C96127"
    tile = "#303639" if dark else "#EEECE8"
    return f"""<rect x="2" y="15" width="193" height="193" rx="38" fill="{tile}"/>
<g transform="translate(-20 -2) scale(0.235)">{FRONT_CUBE}</g>
<text x="233" y="175" fill="{main}" font-family="Avenir Next, Helvetica Neue, Arial, sans-serif"
  font-size="91" font-weight="600" letter-spacing="-2.7">Pomodoro</text>
<text x="727" y="175" fill="{accent}" font-family="Avenir Next, Helvetica Neue, Arial, sans-serif"
  font-size="91" font-weight="600" letter-spacing="-2.7">Float</text>"""


def logo(dark: bool) -> str:
    return DEFS + logo_body(dark)


def preview(dark: bool) -> str:
    bg = "#101315" if dark else "#F5F3EF"
    surface = "#343A3D" if dark else "#FFFFFF"
    heading = "#E9E7E3" if dark else "#262A2C"
    label = "DARK BACKGROUND" if dark else "LIGHT BACKGROUND"
    return f"""{DEFS}
<rect width="1400" height="700" fill="{bg}"/>
<rect x="65" y="72" width="400" height="470" rx="48" fill="{surface}"/>
<g transform="translate(104 121) scale(0.32)">{FRONT_CUBE}</g>
<text x="265" y="617" fill="{heading}" text-anchor="middle"
  font-family="Avenir Next, Helvetica Neue, Arial, sans-serif" font-size="22" letter-spacing="2">APP ICON</text>
<g transform="translate(532 266) scale(0.7)">{logo_body(dark)}</g>
<text x="1315" y="617" fill="{heading}" text-anchor="end" opacity="0.62"
  font-family="Avenir Next, Helvetica Neue, Arial, sans-serif" font-size="19" letter-spacing="2">{label}</text>"""


def concept_sheet() -> str:
    panels = []
    items = (("A", "Front-face dial", FRONT_CUBE),
             ("B", "Top-face dial", TOP_CUBE),
             ("C", "Orbit", ORBIT_CUBE))
    for index, (letter, title, art) in enumerate(items):
        x = 55 + index * 580
        panels.append(f"""<rect x="{x}" y="55" width="545" height="655" rx="38" fill="#FFFFFF"/>
<g transform="translate({x + 35} 104) scale(0.46)">{art}</g>
<text x="{x + 40}" y="624" fill="#E98242" font-family="Avenir Next, Helvetica Neue, Arial, sans-serif"
  font-size="24" font-weight="700" letter-spacing="3">{letter}</text>
<text x="{x + 87}" y="624" fill="#25292C" font-family="Avenir Next, Helvetica Neue, Arial, sans-serif"
  font-size="34" font-weight="600">{title}</text>""")
    return DEFS + '<rect width="1800" height="765" fill="#F1EFEB"/>' + "\n".join(panels)


write("concept-a-face-dial.svg", DEFS + FRONT_CUBE)
write("concept-b-top-dial.svg", DEFS + TOP_CUBE)
write("concept-c-orbit.svg", DEFS + ORBIT_CUBE)
icon_svg = write("pomodoro-float-icon.svg", DEFS + FRONT_CUBE)
write("pomodoro-float-logo-light.svg", logo(False), 1200, 250)
write("pomodoro-float-logo-dark.svg", logo(True), 1200, 250)
write("preview-light.svg", preview(False), 1400, 700)
write("preview-dark.svg", preview(True), 1400, 700)
write("concept-sheet.svg", concept_sheet(), 1800, 765)

for name in ("concept-a-face-dial", "concept-b-top-dial", "concept-c-orbit",
             "pomodoro-float-icon", "pomodoro-float-logo-light", "pomodoro-float-logo-dark",
             "preview-light", "preview-dark", "concept-sheet"):
    raster(OUT / f"{name}.svg", OUT / f"{name}.png")

with tempfile.TemporaryDirectory() as temporary:
    iconset = Path(temporary) / "PomodoroFloat.iconset"
    iconset.mkdir()
    sizes = {"16x16": 16, "16x16@2x": 32, "32x32": 32, "32x32@2x": 64,
             "128x128": 128, "128x128@2x": 256, "256x256": 256,
             "256x256@2x": 512, "512x512": 512, "512x512@2x": 1024}
    for label, size in sizes.items():
        subprocess.run(["sips", "-z", str(size), str(size),
                        str(OUT / "pomodoro-float-icon.png"),
                        "--out", str(iconset / f"icon_{label}.png")],
                       check=True, capture_output=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset),
                    "-o", str(OUT / "PomodoroFloat.icns")],
                   check=True, capture_output=True)

print(f"Created brand assets in {OUT}")
