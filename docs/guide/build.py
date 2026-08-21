import os, sys, html
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from figures import FIGURES, SIZES

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vision-pro-operator-guide.html")


def icon(src, cx, cy, box=46):
    """A square crop centred on (cx,cy) (fractions of the full image), `box` px wide."""
    iw, ih = SIZES[src]
    hx, hy = (box / 2) / iw, (box / 2) / ih
    x0, y0 = cx - hx, cy - hy
    w = 100.0 / (2 * hx)
    h = 100.0 / (2 * hy)
    l = -100.0 * x0 / (2 * hx)
    t = -100.0 * y0 / (2 * hy)
    return (f'<span class="ic"><img src="images/{src}" '
            f'style="width:{w:.1f}%;height:{h:.1f}%;left:{l:.1f}%;top:{t:.1f}%;"></span>')

def figure(fid, num):
    f = FIGURES[fid]
    iw, ih = SIZES[f["src"]]
    x0, y0, x1, y1 = f["crop"]
    cw, ch = (x1 - x0), (y1 - y0)
    ar = (cw * iw) / (ch * ih)
    img_w, img_l = 100.0 / cw, -100.0 * x0 / cw
    img_h, img_t = 100.0 / ch, -100.0 * y0 / ch

    def to_crop(px, py):
        return ((px - x0) / cw * 100.0, (py - y0) / ch * 100.0)

    lines, marks = [], []
    for c in f["callouts"]:
        tx, ty = to_crop(*c["t"])
        bx, by = to_crop(*c["b"])
        lines.append(f'<line x1="{bx:.2f}" y1="{by:.2f}" x2="{tx:.2f}" y2="{ty:.2f}" vector-effect="non-scaling-stroke"/>')
        marks.append(f'<span class="dot" style="left:{tx:.2f}%;top:{ty:.2f}%"></span>')
        marks.append(f'<span class="badge" style="left:{bx:.2f}%;top:{by:.2f}%">{c["n"]}</span>')

    legend = "".join(f'<li><span class="ln">{i+1}</span><div>{t}</div></li>'
                     for i, t in enumerate(f["legend"]))
    legend_html = f'<ol class="legend">{legend}</ol>' if f["legend"] else ""

    return f"""
<figure class="fig">
  <div class="shot" style="aspect-ratio:{ar:.4f};">
    <img src="images/{f['src']}" style="width:{img_w:.3f}%;height:{img_h:.3f}%;left:{img_l:.3f}%;top:{img_t:.3f}%;">
    <svg class="ovl" viewBox="0 0 100 100" preserveAspectRatio="none">{''.join(lines)}</svg>
    {''.join(marks)}
  </div>
  <figcaption><b>Figure {num}.</b> {f['caption']}</figcaption>
  {legend_html}
</figure>"""

CSS = """
:root{--ink:#16181d;--mut:#5b6270;--line:#d9dde5;--accent:#b5179e;--warn:#b45309;--ok:#0f7b4f;--bg:#fff}
*{box-sizing:border-box}
body{margin:0;font:11pt/1.55 -apple-system,"Helvetica Neue",Arial,sans-serif;color:var(--ink);background:var(--bg)}
.page{padding:0 14mm}
h1{font-size:30pt;line-height:1.1;margin:0 0 6mm;letter-spacing:-.02em}
h2{font-size:16pt;margin:14mm 0 4mm;padding-bottom:2mm;border-bottom:2px solid var(--ink);letter-spacing:-.01em;break-after:avoid}
h3{font-size:12.5pt;margin:8mm 0 2mm;break-after:avoid}
p{margin:0 0 3mm}
code{font:10pt/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f1f3f7;padding:1px 4px;border-radius:3px}
b{font-weight:650}
a{color:inherit}
ul,ol{margin:0 0 3mm;padding-left:6mm}
li{margin:0 0 1.5mm}
table{width:100%;border-collapse:collapse;margin:0 0 4mm;font-size:10pt;break-inside:avoid}
th,td{text-align:left;vertical-align:top;padding:2mm 2.5mm;border-bottom:1px solid var(--line)}
th{background:#f1f3f7;font-weight:650;border-bottom:1.5px solid var(--ink)}
td code{font-size:9pt}
.cover{height:247mm;display:flex;flex-direction:column;justify-content:center;break-after:page}
.cover .kick{font-size:10pt;letter-spacing:.18em;text-transform:uppercase;color:var(--accent);font-weight:700;margin-bottom:5mm}
.cover .sub{font-size:13pt;color:var(--mut);max-width:150mm;margin-bottom:14mm}
.cover dl{display:grid;grid-template-columns:34mm 1fr;gap:2mm 4mm;font-size:10pt;margin:0;max-width:150mm}
.cover dt{color:var(--mut)}
.cover dd{margin:0}
.toc{break-after:page}
.toc ol{list-style:none;padding:0;counter-reset:t}
.toc li{counter-increment:t;padding:2mm 0;border-bottom:1px solid var(--line);display:flex;gap:4mm}
.toc li::before{content:counter(t);color:var(--accent);font-weight:700;min-width:7mm}
.note,.warn,.tip{border-left:3px solid var(--accent);background:#faf5fa;padding:3mm 4mm;margin:0 0 4mm;font-size:10pt;break-inside:avoid}
.warn{border-color:var(--warn);background:#fdf6ec}
.tip{border-color:var(--ok);background:#eef8f3}
.note b:first-child,.warn b:first-child,.tip b:first-child{display:block;margin-bottom:1mm}
.fig{margin:0 0 6mm;break-inside:avoid}
.shot{position:relative;overflow:hidden;border:1px solid var(--line);border-radius:5px;background:#eef0f4;width:100%}
.shot img{position:absolute;display:block;max-width:none}
.ovl{position:absolute;inset:0;width:100%;height:100%;overflow:visible}
.ovl line{stroke:var(--accent);stroke-width:1.3;stroke-linecap:round;opacity:.9}
.shot .dot{position:absolute;width:2.9mm;height:2.9mm;margin:-1.45mm 0 0 -1.45mm;border-radius:50%;background:transparent;border:1.2px solid var(--accent);box-shadow:0 0 0 1.1px rgba(255,255,255,.85),inset 0 0 0 1.1px rgba(255,255,255,.85)}
.shot .badge{position:absolute;width:6.4mm;height:6.4mm;margin:-3.2mm 0 0 -3.2mm;border-radius:50%;background:var(--accent);color:#fff;font:700 9.5pt/6.4mm -apple-system,Arial,sans-serif;text-align:center;box-shadow:0 0 0 1.4px #fff}
figcaption{font-size:9.5pt;color:var(--mut);margin-top:2mm}
.legend{list-style:none;padding:0;margin:3mm 0 0;font-size:10pt;columns:2;column-gap:8mm}
.legend li{display:flex;gap:2.5mm;margin:0 0 2mm;break-inside:avoid}
.legend .ln{flex:0 0 4.6mm;height:4.6mm;border-radius:50%;background:var(--accent);color:#fff;font-size:8pt;font-weight:700;display:flex;align-items:center;justify-content:center;margin-top:.6mm}
.flow{display:flex;align-items:stretch;gap:0;margin:0 0 5mm;font-size:9pt;break-inside:avoid}
.flow .st{flex:1;border:1px solid var(--line);border-radius:4px;padding:2.5mm;background:#f8f9fb}
.flow .st b{display:block;font-size:9.5pt;margin-bottom:1mm}
.flow .ar{flex:0 0 7mm;display:flex;align-items:center;justify-content:center;color:var(--accent);font-size:13pt}
.pb{break-before:page}
.ic{position:relative;display:inline-block;width:8mm;height:8mm;overflow:hidden;border:1px solid var(--line);border-radius:4px;background:#fff;vertical-align:middle}
.ic img{position:absolute;display:block;max-width:none}
.gl{display:inline-flex;align-items:center;justify-content:center;min-width:7mm;height:7mm;padding:0 1mm;border:1px solid var(--line);border-radius:3px;background:#f8f9fb;font-size:11pt;line-height:1;vertical-align:-2mm}
.icontbl td:first-child{text-align:center;white-space:nowrap}
.icontbl .gl{margin:0}
@page{size:A4;margin:16mm 0 14mm}
"""

BODY = r"""
<div class="page">

<section class="cover">
  <div class="kick">Operator Guide</div>
  <h1>Vision Pro Player<br>&amp; Controller</h1>
  <div class="sub">Loading video onto headsets, naming it so a group can play together, running single and synchronised playback, and diagnosing a headset that will not connect.</div>
  <dl>
    <dt>Applies to</dt><dd>Vision Pro Player 3.5 (visionOS) · VP Controller 1.5 (iPadOS / iOS)</dd>
    <dt>Audience</dt><dd>Operators running one or more Vision Pro headsets from a tablet</dd>
    <dt>Screenshots</dt><dd>Captured from the running apps: VP Controller on iPad, Vision Pro Player on visionOS 26.1</dd>
    <dt>Document date</dt><dd>21 August 2026</dd>
  </dl>
</section>

<section class="toc">
  <h2 style="margin-top:0">Contents</h2>
  <ol>
    <li>How the system fits together</li>
    <li>What the network has to allow</li>
    <li>Naming each headset</li>
    <li>Starting the controller</li>
    <li>How a headset finds its controller</li>
    <li>Getting video onto a headset</li>
    <li>Naming videos — the rule that makes group playback work</li>
    <li>Playing on one headset</li>
    <li>Playing on every headset at once</li>
    <li>Status badges at a glance</li>
    <li>Icons you will see</li>
    <li>Seeing what the wearer sees</li>
    <li>Removing a video from a headset</li>
    <li>When something does not work</li>
    <li>Quick reference</li>
  </ol>
</section>

<h2>1. How the system fits together</h2>
<p>There are two apps, and they have different jobs.</p>
<table>
  <tr><th style="width:38mm">App</th><th>Runs on</th><th>Role</th></tr>
  <tr><td><b>VP Controller</b></td><td>iPad or iPhone</td><td>The operator's app. It <b>is</b> the server: it hands out commands, stores nothing permanently, and copies video files to the headsets.</td></tr>
  <tr><td><b>Vision Pro Player</b></td><td>Each Vision Pro</td><td>Plays the video. It stores its own copy of every video locally and connects <i>out</i> to the controller.</td></tr>
</table>

<div class="flow">
  <div class="st"><b>Controller (iPad)</b>WebSocket server on port 8080 · file server on port 8081 · advertises itself on the network</div>
  <div class="ar">&#8594;</div>
  <div class="st"><b>Wi-Fi network</b>One ordinary local network. No internet connection is required.</div>
  <div class="ar">&#8594;</div>
  <div class="st"><b>Each Vision Pro</b>Finds the controller by itself, connects, reports its video list and playback state</div>
</div>

<p>Two consequences worth understanding before anything else:</p>
<ul>
  <li><b>Video is never streamed during playback.</b> Each headset plays a file it already holds on its own storage. The network is only used for commands, status, and the one-off copy of a file. A weak network can stop a headset connecting, but it cannot stutter a video that is already playing.</li>
  <li><b>The controller is the server.</b> If the controller app is closed or its server is stopped, every headset loses its link. The headsets keep whatever they were doing but can no longer be commanded.</li>
</ul>

<h2>2. What the network has to allow</h2>
<p>The two apps find each other automatically, but only if the network permits it. In order of how often each one causes trouble:</p>
<table>
  <tr><th style="width:52mm">Requirement</th><th>Why, and what breaks without it</th></tr>
  <tr><td><b>Same Wi-Fi network, same subnet</b></td><td>The headsets look for the controller on the local network only. A headset on a guest network, a different SSID, or a different VLAN will never see it — even if both have internet.</td></tr>
  <tr><td><b>Client isolation OFF</b><br>(also called AP isolation, client separation, or guest mode)</td><td>This setting stops devices on the same Wi-Fi from talking to each other. It is <b>on by default on most guest and hotel networks</b> and it blocks this system completely. This is the single most common cause of "the headset never appears".</td></tr>
  <tr><td><b>mDNS / Bonjour allowed</b></td><td>Auto-discovery uses multicast DNS. Some managed and enterprise networks filter it. If it is blocked, discovery fails but the manual address (section 5) still works.</td></tr>
  <tr><td><b>TCP ports 8080 and 8081 open between devices</b></td><td>8080 carries commands and status; 8081 carries the video file during a transfer. A firewall between the devices will break one or both.</td></tr>
  <tr><td><b>All devices on one band, or a single merged SSID</b></td><td>Some routers keep 2.4 GHz and 5 GHz as separate isolated networks. If the tablet is on one and a headset on the other, they may not see each other.</td></tr>
</table>

<div class="tip"><b>The reliable setup</b>A dedicated router or a phone hotspot that you control, with client isolation off, carrying nothing but the tablet and the headsets. No internet needed. This removes every variable above at once and is what to use for a live event.</div>

<div class="warn"><b>Do not rely on a venue's public Wi-Fi</b>Public, guest and conference networks almost always have client isolation enabled, and you usually cannot turn it off. Test on the actual network before the event, not on the day.</div>

<h2>3. Naming each headset</h2>
<p>With more than one headset in the room, every one of them is called "Vision Pro" until you name it. Do this once per headset, before anything else — it is what you will see on the controller and in the log for the rest of the event.</p>
<p>On the headset: open <b>Vision Pro Player</b> → the gear icon (or tap the address line) → <b>Device</b> → type a name → <b>Save</b>.</p>

{{FIG:vp-settings}}

<div class="tip"><b>Name them after the physical world, not the hardware</b>Use "Seat 1", "Seat 2", "Lobby Headset" — something a person holding the device can verify at a glance. Serial numbers and user names are useless when you are trying to work out which of five identical headsets has frozen. The name is kept until you change it or delete the app.</div>

<h2>4. Starting the controller</h2>
<p>Open <b>VP Controller</b> on the tablet. On first launch the server is not running.</p>

{{FIG:server-stopped}}

<p>Tap <b>Start Server</b>. The header turns green and the connection details appear. From this moment the controller is discoverable and headsets can join.</p>

{{FIG:main-running}}

<div class="note"><b>Order does not matter</b>You can start the controller before or after opening the app on the headsets. Whichever comes second will find the other within a few seconds. What <i>is</i> required is that both are running at the same time — a headset with the app closed is invisible.</div>

<h2>5. How a headset finds its controller</h2>
<p>The headset does this by itself. The controller announces its presence on the local network; each headset watches for that announcement and connects.</p>

{{FIG:vp-main}}

<h3>What the addresses mean</h3>
<table>
  <tr><th style="width:56mm">Where you see it</th><th>What it is</th></tr>
  <tr><td>Controller, <b>Vision Pro Connection URL</b><br><code>ws://192.168.88.247:8080</code></td><td>The tablet's own address on this Wi-Fi network, and the control port. This is what the headsets connect to. <b>It changes when the tablet joins a different network</b>, which is normal.</td></tr>
  <tr><td>Headset Settings, under a discovered controller</td><td>The same address, as the headset resolved it. If it matches the tablet, discovery is working.</td></tr>
  <tr><td>Headset main window, the address line</td><td>The controller this headset is actually connected to right now.</td></tr>
</table>

<div class="note"><b>The headset remembers the controller, not the address</b>It stores <i>which</i> controller it was paired with and re-resolves the address every time. So a new address from the router after a restart does not strand a headset — it will find the same controller again on its own.</div>

<h3>If it does not connect on its own</h3>
<p>Use the manual route: read the address from the controller (figure {{REF:main-running}}, callout 8), then on the headset open <b>Settings → Manual Server Connection</b> and type it exactly, including <code>ws://</code> and <code>:8080</code>. If the manual address works but discovery does not, the network is filtering mDNS — see section 13.</p>

<h2>6. Getting video onto a headset</h2>
<p>Every headset plays from its own local copy, so the file has to physically be on each headset that will play it. There are two ways to put it there.</p>

<h3>Route A — send it from the controller (normal)</h3>
<p>Tap the <b>share icon</b> in the controller's toolbar (figure {{REF:main-running}}, callout 5).</p>

{{FIG:transfer}}

<p>The copy runs over Wi-Fi on port 8081. Progress appears in the Activity Log, and the headset's video list refreshes by itself when it lands.</p>

<div class="warn"><b>One headset at a time</b>Step 2 takes a single device. To put the same video on five headsets you repeat the send five times — and every copy must end up with the <b>same filename</b>, which is what section 7 is about.</div>

<h3>Route B — put the file on the headset directly</h3>
<p>The player reads from its own <b>Documents/Videos</b> folder. Anything placed there appears in the headset's local video list after the app rescans (it rescans on launch and whenever the app comes back to the foreground).</p>
<p>Use this when you have very large files and access to the headset directly — copying a 20 GB immersive file over Wi-Fi is slow, and putting it in place with a cable or via the Files app is much faster.</p>
<ul>
  <li><b>Files app on the headset:</b> Files → On My Vision Pro → <b>Vision Pro Player</b> → <b>Videos</b> → paste the file there.</li>
  <li><b>From a Mac (Xcode):</b> Devices and Simulators → select the headset → Installed Apps → Vision Pro Player → download the container, drop the file into <code>Documents/Videos</code>, then replace the container.</li>
</ul>

<div class="note"><b>Both routes end in the same place</b><code>Documents/Videos</code> inside the Vision Pro Player app. A video that is in that folder will play; one that is anywhere else will not be seen.</div>

<h2>7. Naming videos — the rule that makes group playback work</h2>
<p>This is the part that most often goes wrong, so it is worth being precise.</p>

<div class="warn"><b>The rule</b>A video appears under <b>VIDEOS ON ALL DEVICES</b> only if a file with <b>exactly the same filename</b> exists on <b>every connected headset</b>. The comparison is on the whole filename including the extension, and it is <b>case sensitive</b>.</div>

<p>So <code>Tour.mp4</code> and <code>Tour.MP4</code> are two different videos as far as the controller is concerned, and a headset holding one and a headset holding the other have <b>nothing in common</b> — the list will be empty and <b>Play on All</b> will have nothing to offer.</p>

<h3>The three traps</h3>
<table>
  <tr><th style="width:44mm">Trap</th><th>What happens</th><th>How to avoid it</th></tr>
  <tr><td><b>Importing from Photos</b></td><td>The photo library does not keep the original filename. The file arrives as something like <code>E736F8EA-2264-47A3-AC24-3F7B073AB6EE.mp4</code> (figure {{REF:transfer}}, callout 6). It still works, but nobody can read it, and if you import the same video from Photos twice you may get two different identifiers.</td><td>Import from <b>Files</b> instead. It preserves the real filename.</td></tr>
  <tr><td><b>Sending the same video twice to one headset</b></td><td>The headset never overwrites. The second copy is saved as <code>name_1.mp4</code>, the third as <code>name_2.mp4</code>. That headset now has a filename none of the others have, and the video silently drops out of the "all devices" list.</td><td>Check the headset's local list first. If the video is already there, do not send it again — delete the old copy first if you need to replace it.</td></tr>
  <tr><td><b>Renaming on only some headsets</b></td><td>Any difference at all — a space, a capital letter, a different extension — splits the group.</td><td>Decide the filename once, before the first transfer, and never change it per device.</td></tr>
</table>

<h3>A naming convention that holds up</h3>
<ul>
  <li>Letters, digits, hyphens and underscores only. <b>No spaces</b> — they survive here but cause trouble everywhere else in a production chain.</li>
  <li>All lower case, consistently. That removes the <code>.mp4</code> / <code>.MP4</code> class of mistake entirely.</li>
  <li>Put the format in the name so the operator can pick the right one under pressure: <code>tour-lobby_360sbs.mp4</code>, <code>welcome_180sbs.mp4</code>, <code>safety-briefing_flat.mp4</code>.</li>
  <li>Rename the file <b>on the computer, once</b>, before you transfer it anywhere.</li>
</ul>

<div class="tip"><b>Verify before the audience arrives</b>After loading every headset, look at <b>VIDEOS ON ALL DEVICES</b>. If a video is in that list, every connected headset has it under that exact name and group playback will work. If it is missing, it is missing from at least one headset — expand each card and compare the local lists to find which.</div>

<h2>8. Playing on one headset</h2>
<p>Expand a headset's card with the chevron (figure {{REF:main-running}}, callout 16).</p>

{{FIG:device-card}}

<p>Select a video tile, set <b>Video Format</b> to match the video, then tap <b>Play</b>. The headset opens its immersive view and begins.</p>

{{FIG:playing}}

<h3>What the three buttons actually do</h3>
<table>
  <tr><th style="width:26mm">Button</th><th>Effect on the headset</th><th>Immersive view</th></tr>
  <tr><td><b>Play</b></td><td>Opens the immersive view, loads the selected file and starts it from the beginning.</td><td>Opens</td></tr>
  <tr><td><b>Pause</b></td><td>Freezes on the current frame. Position is kept.</td><td><b>Stays open</b> — the wearer keeps looking at a still frame</td></tr>
  <tr><td><b>Resume</b></td><td>Continues from the paused position.</td><td>Stays open</td></tr>
  <tr><td><b>Stop</b></td><td>Ends playback and releases the file. Position is <b>not</b> kept — the next Play starts from the beginning.</td><td><b>Closes</b> — the wearer is returned to the app window</td></tr>
</table>

{{FIG:paused}}

<div class="note"><b>When a video reaches its end</b>The headset stops by itself, closes the immersive view and brings the window back, exactly as if Stop had been pressed. You do not need to clear anything before starting the next video.</div>

<h3>Choosing the format</h3>
<p>The format tells the headset how to interpret the picture. It is not detected for you — if it is wrong, the video plays but looks wrong.</p>
<table>
  <tr><th style="width:42mm">Format</th><th>Use for</th><th>Symptom if wrong</th></tr>
  <tr><td><b>2D</b></td><td>An ordinary flat film</td><td>—</td></tr>
  <tr><td><b>3D SBS / 3D OU</b></td><td>Flat stereoscopic film, two images packed side-by-side or one above the other</td><td>Two squashed copies of the picture</td></tr>
  <tr><td><b>180° VR</b> / <b>180° VR 3D (SBS)</b></td><td>Half-sphere content filling the front of the view</td><td>Content wrapped around too far, or only half the sphere filled</td></tr>
  <tr><td><b>360° VR</b> / <b>360° VR 3D (SBS)</b> / <b>(OU)</b></td><td>Full-sphere content</td><td>The scene appears twice around the wearer, or is stretched</td></tr>
</table>
<div class="tip"><b>If the picture looks doubled</b>You have almost certainly picked a non-stereo format for a stereo file, or the wrong packing (SBS vs OU). Stop, change the format, play again.</div>

{{FIG:immersive}}

<h2>9. Playing on every headset at once</h2>
<p>The <b>Synchronized Playback</b> panel at the top of the controller plays one video on every connected headset, starting at the same instant.</p>

<h3>Before you press it</h3>
<ol>
  <li>Every headset that should take part is <b>connected</b> — check the device count in the header.</li>
  <li>The video appears under <b>VIDEOS ON ALL DEVICES</b> — which, per section 7, means every headset holds it under that exact filename.</li>
  <li>The <b>Format</b> is set correctly. It applies to all headsets.</li>
</ol>

<h3>What happens when you tap Play on All</h3>
<div class="flow">
  <div class="st"><b>1 · Measure clocks</b>The controller measures each headset's clock against its own, several times, and keeps the best reading.</div>
  <div class="ar">&#8594;</div>
  <div class="st"><b>2 · Prepare</b>Every headset opens its immersive view and pre-loads the file — but does not start.</div>
  <div class="ar">&#8594;</div>
  <div class="st"><b>3 · Wait for all</b>Each headset reports that it is ready. A headset that cannot get ready in time is dropped from this run.</div>
  <div class="ar">&#8594;</div>
  <div class="st"><b>4 · Start together</b>A moment about a second in the future is chosen and sent to each headset in <i>its own</i> corrected clock, so they all begin at the same real instant.</div>
</div>

<p>Once running, the panel offers <b>Pause All</b>, <b>Resume All</b> and <b>Stop All</b>. Resume All re-synchronises on the way back in, so the group stays together after a pause.</p>

<h3>Why a video is missing from the list</h3>
<table>
  <tr><th style="width:52mm">What you see</th><th>Cause</th></tr>
  <tr><td><b>"No videos available on all devices"</b></td><td>There is no single filename common to every connected headset. Expand each card and compare the local lists.</td></tr>
  <tr><td>A video is on the headsets but not in the list</td><td>The filename differs somewhere — a <code>_1</code> suffix from a repeated transfer, a different extension case, or a Photos-generated identifier on one device. See section 7.</td></tr>
  <tr><td>The list shrinks when a headset joins</td><td>Correct and expected. The newly joined headset does not have those videos, so they are no longer common to all.</td></tr>
  <tr><td>A headset is playing but was not in the group</td><td>It was dropped at step 3 because it did not report ready in time — usually a very large file on a slow network. The Activity Log names it.</td></tr>
</table>

<h2>10. Status badges at a glance</h2>
<table>
  <tr><th style="width:34mm">Badge</th><th>Meaning</th></tr>
  <tr><td><b>Idle</b> (grey)</td><td>Connected, nothing loaded. The normal resting state.</td></tr>
  <tr><td><b>Playing</b> (green)</td><td>Rendering video now.</td></tr>
  <tr><td><b>Paused</b> (orange)</td><td>Held on a frame, immersive view still open.</td></tr>
  <tr><td><b>Stopped</b> (grey)</td><td>Playback ended or was stopped.</td></tr>
  <tr><td><b>Immersive</b> (purple)</td><td>The immersive view is open — the wearer is inside the content, not looking at a window. Appears alongside the state badge.</td></tr>
  <tr><td>Headset missing entirely</td><td>Not connected. It is not a playback problem — see section 13.</td></tr>
</table>

<h2>11. Icons you will see</h2>
<p>Two of these carry meaning that is easy to miss, so they are worth learning: the <b>Preview Library</b> in the toolbar, and the small <b>badge in the corner of a video tile</b>.</p>
<table class="icontbl">
  <tr><th style="width:20mm">Icon</th><th style="width:44mm">Name</th><th>What it means and why it is there</th></tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.037:0.0455:58}</td><td><b>Start / Stop</b><br>(navigation bar, left)</td>
    <td>Turns the controller's server on and off. Green triangle = start, red square = stop.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.847:0.046:60}</td><td><b>Send Videos</b><br>(box with an arrow leaving it)</td>
    <td>Opens the transfer sheet. This is how a video file gets from the tablet onto a headset.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.903:0.046:60}</td><td><b>Preview Library</b><br>(two stacked rectangles)</td>
    <td>The tablet's library of <b>flat companion videos</b>. These never go to a headset — they exist only so the operator can watch along on the tablet while the wearer is inside the immersive version. Import companions here first; pair them afterwards.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.960:0.046:60}</td><td><b>Activity Log</b><br>(lines in a box)</td>
    <td>The timestamped record of what the controller actually did. The first place to look when anything is wrong.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.051:0.1395:58}</td><td><b>Link</b><br>(next to the address)</td>
    <td>Marks the connection URL block. Not a button.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.936:0.168:60}</td><td><b>Copy</b><br>(two overlapping pages)</td>
    <td>Copies the connection URL to the clipboard, for typing into a headset by hand.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.903:0.046:60}</td>
    <td><b>Has a preview video</b><br>(same two-rectangle glyph, in a small circle on the <i>top-left corner of a video tile</i>)</td>
    <td><b>This is the one that is most often missed.</b> It marks a headset video that already has a flat companion paired to it. Tiles <i>without</i> the badge have no companion, so selecting them gives you playback but no watch-along preview. The badge appears only after you pair one — see the next section.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-03-controls.png:0.155:0.800:48}</td><td><b>Delete</b><br>(red trash, under a tile)</td>
    <td>Permanently removes that video from that headset. Asks for confirmation first.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.842:0.292:60}</td><td><b>Selection circle / tick</b></td>
    <td>In the synchronised list, an empty circle is an unselected video and a filled purple tick is the one <b>Play on All</b> will use. On a headset's own tiles, selection is shown as a <b>blue outline</b> instead.</td>
  </tr>
  <tr>
    <td>{ICON:ipad-01-main.png:0.460:0.729:60}</td><td><b>Chevron</b><br>(right of a headset card)</td>
    <td>Expands or collapses that headset's card. Collapsed cards still show name and status.</td>
  </tr>
</table>

<div class="tip"><b>Reading the badge at a glance</b>The two-stacked-rectangles glyph always means "flat companion video". In the toolbar it opens the library of them; on a video tile it means "this one has one".</div>

<h2>12. Seeing what the wearer sees</h2>
<p>The operator cannot see the headset's picture directly — an immersive file is far too large to stream to a tablet, and a 360° stereo frame would be unreadable on a flat screen anyway. Instead the controller can play a <b>flat companion copy</b> of the same film, in step with the headset.</p>

<h3>Pairing a companion video</h3>
<ol>
  <li>Put a flat, ordinary (mono, non-VR) version of the film on the tablet — <b>the same running time</b> as the immersive original.</li>
  <li>Import it through the companion library (the middle toolbar icon).</li>
  <li>In the headset's card, <b>long-press the video tile</b> and pair it with that companion.</li>
</ol>
<p>Once paired, two things change: the card shows the companion playing in step with the headset, and <b>a small badge appears in the top-left corner of that video's tile</b> (the two-stacked-rectangles glyph from the previous section). That badge is how you tell, at a glance, which videos already have a companion and which do not. Where no companion is paired, the card says so instead — visible in figure {{REF:playing}}, callout 5.</p>

<div class="note"><b>The running times must match</b>If the companion's duration does not match the file the headset actually loaded, the preview is withheld and both durations are shown instead. This is deliberate: a preview sitting convincingly on the wrong moment is worse than no preview.</div>

<h3>Where the wearer is looking</h3>
<p>While a companion preview is running, the card also shows a <b>direction indicator</b>: a bar with a marker showing where in the content the wearer's head is pointed, captioned in plain words — <i>"Facing the centre"</i>, <i>"Looking 43° right of centre"</i>. It is measured relative to where the content was placed when playback started, not to the room.</p>
<div class="note"><b>Head direction, not eye gaze</b>This is where the headset is pointed. visionOS does not make eye-tracking available to apps, by design, so true gaze cannot be shown. The indicator dims if the readings stop arriving.</div>

<h2>13. Removing a video from a headset</h2>
<p>Expand the headset's card and tap the <b>trash icon</b> under a video tile (figure {{REF:device-card}}, callout 6). You are asked to confirm; the file is then permanently deleted from that headset and the list refreshes.</p>
<div class="warn"><b>Per headset, and permanent</b>Deleting removes the file from that one headset only. There is no undo and no copy left behind — the file has to be transferred again if you need it back.</div>

<h2>14. When something does not work</h2>
<p>Open the <b>Activity Log</b> first. It is timestamped and it records what actually happened, which is almost always faster than guessing.</p>

{{FIG:log}}

<h3>A headset never appears on the controller</h3>
<p>Work down this list in order — it is ordered by how often each one is the answer.</p>
<ol>
  <li><b>Is the app open on the headset, on the Vision Pro Player window?</b> A headset with the app closed cannot be seen. This is the most common cause by a wide margin.</li>
  <li><b>Is the server running?</b> The controller header must be green and say <b>Server Running</b>.</li>
  <li><b>Same Wi-Fi network?</b> Check the actual network name on both devices, not just that both say "connected". Guest networks are a frequent trap.</li>
  <li><b>Client isolation.</b> If both are on the same network and still cannot see each other, this is almost certainly it. Test by moving both to a phone hotspot — if they connect there, the venue network is isolating clients.</li>
  <li><b>Try the manual address.</b> Read the URL from the controller, type it into the headset's <b>Manual Server Connection</b>. If manual works and automatic does not, the network is blocking mDNS — usable, but you will have to enter the address on every headset.</li>
  <li><b>Restart the server</b>, then the headset app. In that order.</li>
</ol>

<h3>Other symptoms</h3>
<table>
  <tr><th style="width:50mm">Symptom</th><th>Where to look</th></tr>
  <tr><td>Headset connects, then drops out repeatedly</td><td>Wi-Fi coverage at the headset's position, or two devices holding the same IP address. Check the log for repeated connect/disconnect pairs.</td></tr>
  <tr><td>A transfer never finishes</td><td>The log shows the percentage. If it stalls, the headset moved out of range or port 8081 is blocked. Delete the partial file from the headset before retrying so you do not end up with a <code>_1</code> copy.</td></tr>
  <tr><td>Video plays but the picture looks wrong</td><td>Format setting — section 8.</td></tr>
  <tr><td>Sound plays but there is no picture</td><td>Give it about three seconds: the player detects this and falls back automatically, and the picture appears. If it persists, note the file and the format and report it.</td></tr>
  <tr><td>Headsets start at visibly different moments</td><td>Check the measured round-trip times in the log (figure {{REF:log}}, callout 5). Values of a few milliseconds are healthy; tens or hundreds of milliseconds mean a congested network.</td></tr>
  <tr><td>One headset did not join a group start</td><td>It failed to report ready in time. The log names it. Usually a very large file; try again, or start that headset on its own.</td></tr>
</table>

<div class="tip"><b>Reproducing a problem cleanly</b>Tap <b>Clear</b> in the log, do the thing that fails, then read the log from the bottom up. The sequence in figure {{REF:log}} is what a healthy run looks like — compare against it.</div>

<h2>15. Quick reference</h2>
<table>
  <tr><th style="width:52mm">Item</th><th>Value</th></tr>
  <tr><td>Control port (WebSocket)</td><td><code>8080</code></td></tr>
  <tr><td>File transfer port (HTTP)</td><td><code>8081</code></td></tr>
  <tr><td>Controller address form</td><td><code>ws://&lt;tablet-ip&gt;:8080</code></td></tr>
  <tr><td>Video folder on the headset</td><td><code>Documents/Videos</code> inside Vision Pro Player</td></tr>
  <tr><td>Container formats</td><td>MP4, MOV, M4V</td></tr>
  <tr><td>Group playback requires</td><td>Byte-identical filename on every connected headset, including extension and letter case</td></tr>
  <tr><td>Duplicate transfer produces</td><td><code>name_1.mp4</code>, <code>name_2.mp4</code> … — which breaks group playback</td></tr>
  <tr><td>Companion preview requires</td><td>A flat copy of the same running time (within half a second)</td></tr>
</table>

<h3>Pre-event checklist</h3>
<ol>
  <li>Every headset has a distinct device name.</li>
  <li>Final video filenames decided and applied on the computer, before any transfer.</li>
  <li>The video is loaded on every headset and <b>appears under VIDEOS ON ALL DEVICES</b>.</li>
  <li>Format selected and verified by actually playing it on one headset.</li>
  <li>A full <b>Play on All</b> rehearsal completed on the real network, in the real room.</li>
  <li>Every headset charged, and the tablet set not to sleep.</li>
</ol>

</div>
"""

for fid in FIGURES:
    pass

nums = {}
n = 0
import re
def sub(m):
    global n
    fid = m.group(1)
    n += 1
    nums[fid] = n
    return figure(fid, n)
body = re.sub(r"\{\{FIG:([a-z0-9\-]+)\}\}", sub, BODY)
body = re.sub(r"\{\{REF:([a-z0-9\-]+)\}\}", lambda m: str(nums[m.group(1)]), body)
body = re.sub(r"\{ICON:([^:]+):([\d.]+):([\d.]+):(\d+)\}",
              lambda m: icon(m.group(1), float(m.group(2)), float(m.group(3)), int(m.group(4))), body)

doc = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Vision Pro Player &amp; Controller — Operator Guide</title>
<style>{CSS}</style></head><body>{body}</body></html>"""

open(OUT, "w").write(doc)
print("wrote", OUT, len(doc), "bytes,", n, "figures")
