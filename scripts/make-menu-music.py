#!/usr/bin/env python3
"""The built-in themes' menu music (assets/themes/<theme>/<theme>.ogg), made here.

Each tune is a short loop of a few instruments of the kind an old games
console has (pulse and triangle waves, noise drums, a bell, an electric
piano), played from the notes below and mixed so that its end runs into its
start: mpv loops it seamlessly under the menus (MenuMusic). Run it again
after changing a tune; it needs Python 3 and ffmpeg with libopus, nothing
else, and writes the files in place.

Demoscene's is a tracker's module instead (assets/themes/demoscene/
demoscene.xm), written here as FastTracker 2 wrote one: its instruments are
single cycles of a wave, its notes rows of patterns, played by mpv through
libopenmpt. And the theme template's is a MIDI file (docs/theme-template/
tune.mid, "template"), only notes, which FluidSynth plays with a SoundFont.

    python3 scripts/make-menu-music.py [theme ...]
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave
from array import array

RATE = 32000
HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(HERE, "..", "assets", "themes")

NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(note):
    """"A4", "F#3", "Bb2" as a MIDI note number."""
    pitch = NAMES[note[0]]
    rest = note[1:]
    while rest and rest[0] in "#b":
        pitch += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return pitch + 12 * (int(rest) + 1)


def freq(note):
    return 440.0 * 2 ** ((midi(note) - 69) / 12)


# --- Instruments: a sample for a phase (in turns) and a time into the note ---

def pulse(duty):
    return lambda phase, t: 1.0 if phase % 1.0 < duty else -1.0


def triangle(phase, t):
    return 4.0 * abs(phase % 1.0 - 0.5) - 1.0


def sine(phase, t):
    return math.sin(2 * math.pi * phase)


def epiano(phase, t):
    # A tine's tone: the note, its octave fading faster, a little bark.
    return (math.sin(2 * math.pi * phase)
            + 0.35 * math.exp(-t * 6) * math.sin(4 * math.pi * phase)
            + 0.12 * math.exp(-t * 14) * math.sin(6 * math.pi * phase))


def bell(phase, t):
    # A music box's tine: inharmonic partials, the high ones gone quickly.
    return (math.sin(2 * math.pi * phase)
            + 0.45 * math.exp(-t * 5) * math.sin(2 * math.pi * phase * 2.76)
            + 0.2 * math.exp(-t * 11) * math.sin(2 * math.pi * phase * 5.4))


def saw(phase, t):
    return 2.0 * (phase % 1.0) - 1.0


class Tune:
    def __init__(self, bpm, bars, swing=0.0, seed=1):
        self.beat = 60.0 / bpm
        self.n = int(round(bars * 4 * self.beat * RATE))
        self.mix = [0.0] * self.n
        self.swing = swing
        self.random = random.Random(seed)

    def at(self, beats):
        """Seconds from the start for a time in beats, eighths swung."""
        whole = math.floor(beats * 2 + 1e-9)
        if self.swing and whole % 2 == 1 and abs(beats * 2 - whole) < 1e-6:
            beats += self.swing * 0.5
        return beats * self.beat

    def note(self, start, length, note, voice, volume, attack=0.005, decay=0.1, sustain=0.7,
             release=0.08, vibrato=0.0, bus=None):
        """`note` (a name or a frequency) from `start` for `length` beats."""
        f = note if isinstance(note, float) else freq(note)
        begin = int(self.at(start) * RATE)
        held = self.at(start + length) - self.at(start)
        total = int((held + release) * RATE)
        out = self.mix if bus is None else bus
        phase = 0.0
        step = f / RATE
        for i in range(total):
            t = i / RATE
            if t < attack:
                env = t / attack
            elif t < attack + decay:
                env = 1.0 - (1.0 - sustain) * (t - attack) / decay
            elif t < held:
                env = sustain
            else:
                env = sustain * max(0.0, 1.0 - (t - held) / release)
            if vibrato:
                phase += step * (1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t * 2))
            else:
                phase += step
            # Past the end, round to the start: the loop's seam.
            out[(begin + i) % self.n] += voice(phase, t) * env * volume

    def kick(self, start, volume=0.6):
        begin = int(self.at(start) * RATE)
        phase = 0.0
        for i in range(int(0.3 * RATE)):
            t = i / RATE
            phase += (45 + 95 * math.exp(-t * 28)) / RATE
            self.mix[(begin + i) % self.n] += math.sin(2 * math.pi * phase) * math.exp(-t * 14) * volume

    def snare(self, start, volume=0.25):
        begin = int(self.at(start) * RATE)
        phase = 0.0
        for i in range(int(0.22 * RATE)):
            t = i / RATE
            phase += 185 / RATE
            noise = self.random.uniform(-1, 1)
            self.mix[(begin + i) % self.n] += (noise * math.exp(-t * 18) * 0.8
                                               + math.sin(2 * math.pi * phase) * math.exp(-t * 30) * 0.5) * volume

    def hat(self, start, volume=0.06, length=0.05):
        begin = int(self.at(start) * RATE)
        last = 0.0
        for i in range(int(length * RATE)):
            t = i / RATE
            noise = self.random.uniform(-1, 1)
            # Only the hiss: the noise less what it was a sample ago.
            self.mix[(begin + i) % self.n] += (noise - last) * 0.5 * math.exp(-t * 70) * volume
            last = noise

    def brush(self, start, volume=0.05):
        begin = int(self.at(start) * RATE)
        for i in range(int(0.25 * RATE)):
            t = i / RATE
            env = min(1.0, t / 0.03) * math.exp(-t * 12)
            self.mix[(begin + i) % self.n] += self.random.uniform(-1, 1) * env * volume

    def melody(self, start, voice, volume, line, **options):
        """`line`: [(note or "R", eighths)], from `start` beats on."""
        at = start
        for note, eighths in line:
            if note != "R":
                self.note(at, eighths * 0.5 * 0.92, note, voice, volume, **options)
            at += eighths * 0.5

    def finish(self, path, echo=0.0, echo_beats=0.75, lowpass=0.0, gain=0.5):
        out = self.mix
        if lowpass:
            # A one-pole low pass, twice round the loop so its seam settles.
            a = math.exp(-2 * math.pi * lowpass / RATE)
            y = out[-1]
            for _ in range(2):
                for i in range(self.n):
                    y = (1 - a) * out[i] + a * y
                    out[i] = y
        if echo:
            delay = int(echo_beats * self.beat * RATE)
            y = [0.0] * self.n
            for _ in range(4):
                for i in range(self.n):
                    y[i] = out[i] + echo * y[i - delay]
            out = [0.65 * out[i] + 0.35 * y[i] for i in range(self.n)]
        peak = max(1e-9, max(abs(v) for v in out))
        pcm = array("h", (int(32767 * math.tanh(v / peak * 1.1) * gain) for v in out))
        with tempfile.TemporaryDirectory() as tmp:
            raw = os.path.join(tmp, "tune.wav")
            with wave.open(raw, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(pcm.tobytes())
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", raw, "-c:a", "libopus",
                            "-b:a", "40k", "-map_metadata", "-1", path], check=True)
        print(f"{path}: {self.n / RATE:.1f} s")


def chords(tune, start, progression, beats, voice, volume, **options):
    at = start
    for chord in progression:
        for note in chord:
            tune.note(at, beats * 0.95, note, voice, volume, **options)
        at += beats


def arpeggio(tune, start, progression, pattern, step, voice, volume, **options):
    """Each chord's notes in `pattern` order, a note every `step` beats, for a bar."""
    at = start
    for chord in progression:
        for k in range(int(round(4 / step))):
            tune.note(at + k * step, step * 0.8, chord[pattern[k % len(pattern)]], voice, volume, **options)
        at += 4


# --- The tunes ---

def trinitron():
    # Calm, warm, in A minor: an arpeggio, a soft bass and a gentle tune.
    t = Tune(92, 8)
    prog = [["A3", "C4", "E4", "A4"], ["F3", "A3", "C4", "F4"], ["C4", "E4", "G4", "C5"], ["G3", "B3", "D4", "G4"]] * 2
    arpeggio(t, 0, prog, [0, 1, 2, 3, 2, 1], 0.25, pulse(0.25), 0.07, decay=0.08, sustain=0.4)
    for bar, root in enumerate(["A1", "F1", "C2", "G1"] * 2):
        t.note(bar * 4, 1.9, root, triangle, 0.32)
        t.note(bar * 4 + 2, 1.9, root, triangle, 0.28)
    t.melody(0, triangle, 0.22, [
        ("E5", 2), ("D5", 1), ("C5", 1), ("E5", 4),
        ("F5", 2), ("E5", 1), ("D5", 1), ("C5", 4),
        ("G5", 2), ("E5", 2), ("C5", 2), ("D5", 2),
        ("B4", 4), ("D5", 2), ("G5", 2),
        ("A5", 2), ("G5", 1), ("E5", 1), ("C5", 4),
        ("A4", 2), ("C5", 2), ("F5", 2), ("E5", 2),
        ("E5", 2), ("D5", 2), ("C5", 2), ("G4", 2),
        ("B4", 4), ("D5", 4)], vibrato=0.004, release=0.2)
    for beat in range(32):
        t.hat(beat + 0.5, 0.05)
        if beat % 2 == 0:
            t.kick(beat, 0.35)
    return t, dict(echo=0.3, lowpass=5500, gain=0.45)


def late_show():
    # After hours: an electric piano's chords, a walking bass, brushes, a
    # muted tune, swung.
    t = Tune(72, 8, swing=0.33, seed=7)
    prog = [["D4", "F4", "A4", "C5"], ["G3", "B3", "D4", "F4"], ["C4", "E4", "G4", "B4"], ["A3", "C#4", "E4", "G4"]] * 2
    for bar, chord in enumerate(prog):
        for note in chord:
            t.note(bar * 4, 1.4, note, epiano, 0.08, decay=0.6, sustain=0.5, release=0.3)
            t.note(bar * 4 + 2.5, 0.4, note, epiano, 0.06, decay=0.2, sustain=0.5, release=0.2)
    walk = ["D2", "E2", "F2", "A2", "G2", "F2", "D2", "B1", "C2", "E2", "G2", "B2", "A2", "G2", "E2", "C#2"] * 2
    for beat, note in enumerate(walk):
        t.note(beat, 0.85, note, triangle, 0.34, decay=0.2, sustain=0.6)
    t.melody(0, sine, 0.16, [
        ("A4", 3), ("G4", 1), ("F4", 2), ("D4", 2),
        ("B4", 2), ("A4", 1), ("G4", 1), ("F4", 4),
        ("E4", 4), ("G4", 2), ("B4", 2),
        ("A4", 4), ("C#5", 2), ("E5", 2),
        ("F5", 3), ("E5", 1), ("D5", 2), ("C5", 2),
        ("B4", 2), ("D5", 2), ("F5", 4),
        ("E5", 2), ("C5", 2), ("G4", 4),
        ("A4", 4), ("R", 4)], vibrato=0.006, release=0.15)
    for beat in range(32):
        t.hat(beat, 0.04, 0.12)
        t.hat(beat + 0.5, 0.025, 0.08)
        if beat % 2 == 1:
            t.brush(beat, 0.06)
    # Now and then a crackle, as of a worn record.
    for _ in range(40):
        i = t.random.randrange(t.n)
        for k in range(12):
            t.mix[(i + k) % t.n] += t.random.uniform(-0.15, 0.15) * (1 - k / 12)
    return t, dict(echo=0.18, lowpass=3500, gain=0.45)


def matrix():
    # Dark and driving, in E Phrygian: a pulsing bass, a cold pad and bells.
    t = Tune(112, 8, seed=3)
    roots = ["E2", "F2", "E2", "D2"] * 2
    for bar, root in enumerate(roots):
        octave = root[0] + str(int(root[-1]) + 1)
        for k in range(16):
            note = octave if k % 4 == 2 else root
            t.note(bar * 4 + k * 0.25, 0.2, note, pulse(0.5), 0.12, decay=0.05, sustain=0.5, release=0.03)
    pads = [["E3", "G3", "B3"], ["F3", "A3", "C4"], ["E3", "G3", "B3"], ["D3", "F#3", "A3"]] * 2
    chords(t, 0, pads, 4, saw, 0.035, attack=0.6, decay=0.3, sustain=0.8, release=0.6)
    t.melody(0, bell, 0.18, [
        ("B4", 4), ("R", 4),
        ("C5", 2), ("B4", 2), ("A4", 4),
        ("G4", 4), ("F4", 4),
        ("E4", 8),
        ("E5", 4), ("D5", 2), ("C5", 2),
        ("B4", 4), ("A4", 4),
        ("G4", 2), ("A4", 2), ("B4", 4),
        ("E4", 8)], decay=1.2, sustain=0.0, release=0.4)
    for beat in range(32):
        if beat % 2 == 0:
            t.kick(beat, 0.5)
        else:
            t.snare(beat, 0.12)
        for k in range(4):
            t.hat(beat + k * 0.25, 0.025 if k else 0.04)
    t.kick(31.5, 0.35)
    return t, dict(echo=0.35, echo_beats=0.75, lowpass=6000, gain=0.45)


def inferno():
    # Fast and fiery, in D minor: a galloping bass, power chords, a riff.
    t = Tune(140, 8, seed=5)
    roots = ["D2", "Bb1", "C2", "A1"] * 2
    fifths = {"D2": "A2", "Bb1": "F2", "C2": "G2", "A1": "E2"}
    for bar, root in enumerate(roots):
        for k in range(8):
            t.note(bar * 4 + k * 0.5, 0.4, root if k % 2 == 0 else root[:-1] + str(int(root[-1]) + 1),
                   triangle, 0.3, decay=0.1, sustain=0.6)
            for note in (root[:-1] + str(int(root[-1]) + 1), fifths[root][:-1] + str(int(fifths[root][-1]) + 1)):
                t.note(bar * 4 + k * 0.5, 0.22, note, pulse(0.25), 0.05, decay=0.05, sustain=0.5, release=0.03)
    t.melody(0, pulse(0.5), 0.1, [
        ("D5", 2), ("F5", 2), ("A5", 2), ("F5", 2),
        ("Bb5", 3), ("A5", 1), ("G5", 2), ("F5", 2),
        ("G5", 2), ("E5", 2), ("C5", 2), ("E5", 2),
        ("A5", 4), ("C#5", 2), ("E5", 2),
        ("D5", 2), ("F5", 2), ("A5", 2), ("D6", 2),
        ("C6", 2), ("Bb5", 2), ("A5", 2), ("G5", 2),
        ("A5", 2), ("G5", 2), ("E5", 2), ("C5", 2),
        ("A4", 2), ("C#5", 2), ("E5", 2), ("A5", 2)], vibrato=0.006, decay=0.1, sustain=0.7)
    for beat in range(32):
        t.kick(beat, 0.5 if beat % 2 == 0 else 0.3)
        if beat % 2 == 1:
            t.snare(beat, 0.22)
        t.hat(beat + 0.5, 0.05)
        t.hat(beat, 0.035)
    return t, dict(echo=0.15, echo_beats=0.5, lowpass=7000, gain=0.42)


def arcade():
    # Bright and bouncy, in C major: arpeggios, an octave bass, a catchy tune.
    t = Tune(128, 8, seed=9)
    prog = [["C4", "E4", "G4", "C5"], ["A3", "C4", "E4", "A4"], ["F3", "A3", "C4", "F4"], ["G3", "B3", "D4", "G4"]] * 2
    arpeggio(t, 0, prog, [0, 1, 2, 3], 0.25, pulse(0.125), 0.06, decay=0.04, sustain=0.5, release=0.02)
    for bar, root in enumerate(["C2", "A1", "F1", "G1"] * 2):
        for k in range(8):
            note = root if k % 2 == 0 else root[:-1] + str(int(root[-1]) + 1)
            t.note(bar * 4 + k * 0.5, 0.4, note, triangle, 0.3, decay=0.1, sustain=0.6)
    t.melody(0, pulse(0.5), 0.1, [
        ("E5", 2), ("G5", 2), ("C6", 2), ("G5", 2),
        ("A5", 2), ("E5", 2), ("C5", 4),
        ("F5", 2), ("A5", 2), ("C6", 2), ("A5", 2),
        ("G5", 2), ("F5", 2), ("E5", 2), ("D5", 2),
        ("E5", 2), ("G5", 2), ("C6", 3), ("B5", 1),
        ("A5", 2), ("G5", 2), ("E5", 4),
        ("F5", 2), ("E5", 2), ("D5", 2), ("C5", 2),
        ("D5", 2), ("B4", 2), ("G4", 4)], vibrato=0.005, decay=0.08, sustain=0.6)
    for beat in range(32):
        if beat % 2 == 0:
            t.kick(beat, 0.45)
        else:
            t.snare(beat, 0.18)
        t.hat(beat + 0.5, 0.05)
    return t, dict(echo=0.2, echo_beats=0.75, lowpass=8000, gain=0.42)


def winter():
    # Gentle, in F major: a music box over a soft pad.
    t = Tune(84, 8, seed=11)
    pads = [["F3", "A3", "C4"], ["D3", "F3", "A3"], ["Bb2", "D3", "F3"], ["C3", "E3", "G3"]] * 2
    chords(t, 0, pads, 4, sine, 0.06, attack=0.8, decay=0.4, sustain=0.8, release=0.8)
    for bar, root in enumerate(["F2", "D2", "Bb1", "C2"] * 2):
        t.note(bar * 4, 3.8, root, sine, 0.22, attack=0.05, decay=0.5, sustain=0.6, release=0.4)
    t.melody(0, bell, 0.2, [
        ("A5", 2), ("C6", 2), ("F6", 2), ("C6", 2),
        ("D6", 2), ("A5", 2), ("F5", 4),
        ("Bb5", 2), ("D6", 2), ("F6", 2), ("D6", 2),
        ("C6", 2), ("Bb5", 2), ("A5", 2), ("G5", 2),
        ("A5", 2), ("C6", 2), ("F6", 3), ("E6", 1),
        ("D6", 2), ("C6", 2), ("A5", 4),
        ("Bb5", 2), ("A5", 2), ("G5", 2), ("F5", 2),
        ("G5", 4), ("C6", 4)], decay=1.4, sustain=0.0, release=0.5)
    # Sleigh bells, very softly.
    for beat in range(32):
        t.hat(beat + 0.5, 0.02, 0.09)
    return t, dict(echo=0.35, echo_beats=1.0, lowpass=6500, gain=0.45)


# --- A tracker's module: an XM, as FastTracker 2 wrote one ---

# XM's notes: 1 is C-0, 97 lets the note go. A note plays its sample at 8363
# Hz at C-4, so a 32-sample cycle sounds the note itself.
OFF = 97


def xm_note(note):
    return midi(note) - 11


def cycle(wave_at, length=32, level=110):
    """One cycle of a wave, 8-bit, from a function of the phase (0..1)."""
    return [int(round(level * wave_at(i / length))) for i in range(length)]


def drum(seconds, tone, decay, seed):
    """A hit: `tone` (a function of the time) under an envelope, 8-bit, at 8363 Hz."""
    rng = random.Random(seed)
    n = int(seconds * 8363)
    return [int(max(-127, min(127, 120 * tone(i / 8363, rng) * math.exp(-i / 8363 * decay)))) for i in range(n)]


class Module:
    """Patterns of rows of cells, a cell (note, instrument, volume, effect, parameter)."""

    def __init__(self, name, channels, rows=64, speed=6, bpm=125):
        self.name, self.channels, self.rows, self.speed, self.bpm = name, channels, rows, speed, bpm
        self.patterns, self.order, self.instruments = [], [], []

    def instrument(self, name, sample, loop=True, envelope=(), vibrato=(0, 0, 0, 0), panning=128):
        """The instrument's number, from 1. envelope: [(tick, volume 0-64)];
        vibrato: (type, sweep, depth, rate), the instrument's own."""
        self.instruments.append(dict(name=name, sample=sample, loop=loop, envelope=list(envelope),
                                     vibrato=vibrato, panning=panning))
        return len(self.instruments)

    def pattern(self):
        rows = [[None] * self.channels for _ in range(self.rows)]
        self.patterns.append(rows)
        return rows

    def write(self, path):
        def text(value, size):
            return value.encode("ascii").ljust(size, b"\0")[:size]
        out = b"Extended Module: " + text(self.name, 20) + b"\x1a" + text("OSD/OS", 20) + struct.pack("<H", 0x0104)
        # Linear frequencies (flag 1), the order table always 256 long.
        out += struct.pack("<IHHHHHHHH", 276, len(self.order), 0, self.channels, len(self.patterns),
                           len(self.instruments), 1, self.speed, self.bpm)
        out += bytes(self.order) + bytes(256 - len(self.order))
        for rows in self.patterns:
            data = b""
            for row in rows:
                for cell in row:
                    # Packed: a byte saying which of the five follow.
                    flags, values = 0x80, b""
                    for bit, value in zip((1, 2, 4, 8, 16), cell or ()):
                        if value:
                            flags |= bit
                            values += bytes([value])
                    data += bytes([flags]) + values
            out += struct.pack("<IBHH", 9, 0, len(rows), len(data)) + data
        for ins in self.instruments:
            env = ins["envelope"]
            head = text(ins["name"], 22) + b"\0" + struct.pack("<HI", 1, 40) + bytes(96)
            head += b"".join(struct.pack("<HH", x, y) for x, y in env) + bytes(48 - 4 * len(env)) + bytes(48)
            head += bytes([len(env), 0, 0, 0, 0, 0, 0, 0, 1 if env else 0, 0]) + bytes(ins["vibrato"])
            head += struct.pack("<H", 0) + bytes(2)
            head = struct.pack("<I", 263) + head
            out += head + bytes(263 - len(head))
            sample, loop = ins["sample"], ins["loop"]
            out += struct.pack("<III", len(sample), 0, len(sample) if loop else 0)
            out += bytes([64, 0, 1 if loop else 0, ins["panning"], 0, 0]) + text(ins["name"], 22)
            # Each sample as the difference from the one before.
            last, delta = 0, bytearray()
            for value in sample:
                delta.append((value - last) & 0xFF)
                last = value
            out += bytes(delta)
        with open(path, "wb") as f:
            f.write(out)
        seconds = len(self.order) * self.rows * self.speed * 2.5 / self.bpm
        print(f"{path}: {seconds:.1f} s")


def demoscene():
    # A demo's tune, in A minor: a lead with vibrato, a chord arpeggio
    # (effect 0), an octave bass and a drum channel. Three patterns of four
    # bars, the third turning round to the first on E.
    m = Module("OSD/OS Demoscene", 4)
    lead = m.instrument("lead", cycle(lambda p: 1 if p < 0.25 else -1, level=90),
                        envelope=[(0, 64), (6, 52), (30, 44)], vibrato=(0, 24, 3, 10), panning=96)
    arp = m.instrument("arp", cycle(lambda p: 1 if p < 0.5 else -1, level=70),
                       envelope=[(0, 48), (8, 28), (32, 16)], panning=160)
    bass = m.instrument("bass", cycle(lambda p: 4 * abs(p - 0.5) - 1, level=120),
                        envelope=[(0, 64), (12, 44), (40, 36)])
    kick = m.instrument("kick", drum(0.18, lambda t, r: math.sin(2 * math.pi * (50 * t + 100 * (1 - math.exp(-t * 25)) / 25)), 14, 1), loop=False)
    snare = m.instrument("snare", drum(0.14, lambda t, r: r.uniform(-1, 1) * 0.8 + 0.3 * math.sin(2 * math.pi * 190 * t), 22, 2), loop=False)
    hat = m.instrument("hat", drum(0.05, lambda t, r: r.uniform(-1, 1), 70, 3), loop=False)

    minor, major = 0x37, 0x47
    sections = [
        ([("A4", minor), ("F4", major), ("G4", major), ("E4", minor)],
         [("E5", 2), ("A5", 2), ("C6", 2), ("B5", 1), ("A5", 1), ("C6", 3), ("A5", 1), ("F5", 2), ("A5", 2),
          ("B5", 2), ("D6", 2), ("G5", 2), ("B5", 2), ("E5", 4), ("G5", 2), ("B5", 2)]),
        ([("A4", minor), ("F4", major), ("C4", major), ("G4", major)],
         [("A5", 2), ("C6", 2), ("E6", 2), ("D6", 1), ("C6", 1), ("A5", 4), ("F5", 2), ("A5", 2),
          ("G5", 2), ("C6", 2), ("E6", 2), ("C6", 2), ("D6", 4), ("B5", 2), ("G5", 2)]),
        ([("A4", minor), ("F4", major), ("G4", major), ("E4", major)],
         [("C6", 2), ("B5", 2), ("A5", 2), ("E5", 2), ("F5", 2), ("A5", 2), ("C6", 2), ("A5", 2),
          ("B5", 2), ("G5", 2), ("D6", 2), ("B5", 2), ("G#5", 4), ("B5", 2), ("E6", 2)]),
    ]
    for chords_, line in sections:
        rows = m.pattern()
        # The lead: a row is a sixteenth, a step of the line an eighth.
        at = 0
        for note, eighths in line:
            rows[at][0] = (xm_note(note), lead, 0x10 + 48)
            if eighths >= 3:
                # Let a long note go just before the next.
                rows[at + eighths * 2 - 1][0] = (OFF,)
            at += eighths * 2
        for bar, (root, chord) in enumerate(chords_):
            for r in range(16):
                row = bar * 16 + r
                # The arpeggio on every row, the note again on every beat.
                rows[row][1] = (xm_note(root), arp, 0x10 + 32, 0, chord) if r % 4 == 0 else (0, 0, 0, 0, chord)
                if r % 2 == 0:
                    octave = int(root[-1]) - 2 + (r // 2) % 2
                    rows[row][2] = (xm_note(root[:-1] + str(octave)), bass, 0x10 + 56)
                if r in (0, 8) or (bar == 3 and r == 10):
                    rows[row][3] = (xm_note("C4"), kick, 0x10 + 64)
                elif r in (4, 12):
                    rows[row][3] = (xm_note("C4"), snare, 0x10 + 44)
                elif r % 2 == 0:
                    rows[row][3] = (xm_note("C5"), hat, 0x10 + 20)
    m.order = [0, 1, 0, 2]
    return m


# --- A MIDI file: notes only, a General MIDI instrument for each channel ---

def write_midi(path, bpm, programs, notes, ppq=480):
    """programs: {channel: General MIDI program}; notes: [(start beat, beats,
    note, velocity, channel)], channel 9 the drums. One track, type 0."""
    def number(n):
        out = [n & 0x7F]
        while n > 0x7F:
            n >>= 7
            out.insert(0, (n & 0x7F) | 0x80)
        return bytes(out)
    events = []
    for start, beats, note, velocity, channel in notes:
        on = int(round(start * ppq))
        off = int(round((start + beats) * ppq))
        pitch = note if isinstance(note, int) else midi(note)
        events.append((on, 1, bytes([0x90 | channel, pitch, velocity])))
        events.append((off, 0, bytes([0x80 | channel, pitch, 0])))
    events.sort(key=lambda e: (e[0], e[1]))
    track = b"\x00\xff\x51\x03" + int(round(60e6 / bpm)).to_bytes(3, "big")
    for channel, program in sorted(programs.items()):
        track += b"\x00" + bytes([0xC0 | channel, program])
    last = 0
    for tick, _, data in events:
        track += number(tick - last) + data
        last = tick
    # The end, on the loop's last beat, so it loops in time.
    end = int(round(max(n[0] + n[1] for n in notes) * ppq))
    track += number(max(0, end - last)) + b"\xff\x2f\x00"
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, ppq) + b"MTrk" + struct.pack(">I", len(track)) + track)
    print(f"{path}: {end / ppq * 60 / bpm:.1f} s")


def template():
    # Easy and warm, in D major: an electric piano's chords, a finger bass,
    # a soft lead and a light kit, eight bars.
    notes = []
    progression = [["D4", "F#4", "A4"], ["B3", "D4", "F#4"], ["G3", "B3", "D4"], ["A3", "C#4", "E4"]] * 2
    for bar, chord in enumerate(progression):
        for beat in (0, 1.5, 2.5):
            for note in chord:
                notes.append((bar * 4 + beat, 1.0 if beat == 0 else 0.9, note, 64, 0))
        root = chord[0][:-1] + str(int(chord[0][-1]) - 2)
        for beat, step in ((0, root), (1.5, root), (2, chord[0][:-1] + str(int(chord[0][-1]) - 1)), (3, root)):
            notes.append((bar * 4 + beat, 0.45, step, 90, 1))
    line = [("F#5", 1.5), ("E5", 0.5), ("D5", 1), ("A4", 1), ("B4", 1.5), ("D5", 0.5), ("F#5", 2),
            ("G5", 1.5), ("F#5", 0.5), ("E5", 1), ("D5", 1), ("C#5", 2), ("E5", 2),
            ("F#5", 1.5), ("A5", 0.5), ("F#5", 1), ("D5", 1), ("B4", 1.5), ("D5", 0.5), ("E5", 2),
            ("D5", 1), ("E5", 1), ("F#5", 1), ("E5", 1), ("D5", 4)]
    at = 0
    for note, beats in line:
        notes.append((at, beats * 0.95, note, 80, 2))
        at += beats
    for beat in range(32):
        notes.append((beat, 0.25, 36 if beat % 2 == 0 else 38, 90 if beat % 2 == 0 else 70, 9))
        notes.append((beat + 0.5, 0.25, 42, 45, 9))
    # Electric piano 1, finger bass, vibraphone.
    write_midi(os.path.join(HERE, "..", "docs", "theme-template", "tune.mid"), 96, {0: 4, 1: 33, 2: 11}, notes)


TUNES = {"trinitron": trinitron, "late-show": late_show, "matrix": matrix,
         "inferno": inferno, "arcade": arcade, "winter": winter}
MODULES = {"demoscene": demoscene}
MIDI = {"template": template}


def main():
    names = sys.argv[1:] or list(TUNES) + list(MODULES) + list(MIDI)
    for name in names:
        if name in MIDI:
            MIDI[name]()
            continue
        if name in MODULES:
            MODULES[name]().write(os.path.join(THEMES, name, name + ".xm"))
            continue
        tune, finish = TUNES[name]()
        tune.finish(os.path.join(THEMES, name, name + ".ogg"), **finish)


if __name__ == "__main__":
    main()
