#!/usr/bin/env python3
"""Vanks OS — проигрыватель для демо: MPRIS без звука.

    tools/demo-player.py <папка с обложками>

Показывается в оболочке как настоящий проигрыватель: название, исполнитель,
обложка, позиция, «Пауза» и «Следующий». Звука нет — для записи видео
(tools/delta-demo.sh) и проверок острова, виджета «Музыка» и экрана блокировки.
Обложки: cover-1.jpg, cover-2.jpg, … в указанной папке.
"""
import os
import sys
import time

from gi.repository import Gio, GLib

TRACKS = [
    ("Neon Rain", "Vanks Lab", "Quasar", 214),
    ("Afterglow", "Nebula Drive", "Pulsar", 187),
    ("Event Horizon", "Vanks Lab", "Quasar", 243),
]

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/>
    <method name="PlayPause"/><method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""
PATH = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"


class Player:
    def __init__(self, covers):
        self.covers = covers
        self.index = 0
        self.playing = True
        self.offset = 40.0          # с начала трека, чтобы полоска не была пустой
        self.since = time.monotonic()
        self.conn = None

    def position(self):
        pos = self.offset + (time.monotonic() - self.since if self.playing else 0)
        return int(min(pos, TRACKS[self.index][3]) * 1e6)

    def metadata(self):
        title, artist, album, length = TRACKS[self.index]
        art = os.path.join(self.covers, f"cover-{self.index + 1}.jpg")
        return {
            "mpris:trackid": GLib.Variant("o", f"/vanks/demo/track{self.index}"),
            "mpris:length": GLib.Variant("x", length * 1_000_000),
            "mpris:artUrl": GLib.Variant("s", "file://" + art),
            "xesam:title": GLib.Variant("s", title),
            "xesam:artist": GLib.Variant("as", [artist]),
            "xesam:album": GLib.Variant("s", album),
        }

    def props(self, iface):
        if iface == ROOT:
            return {
                "CanQuit": GLib.Variant("b", True), "CanRaise": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Vanks Demo"),
                "DesktopEntry": GLib.Variant("s", "vanks-demo"),
                "SupportedUriSchemes": GLib.Variant("as", []), "SupportedMimeTypes": GLib.Variant("as", []),
            }
        return {
            "PlaybackStatus": GLib.Variant("s", "Playing" if self.playing else "Paused"),
            "LoopStatus": GLib.Variant("s", "None"), "Rate": GLib.Variant("d", 1.0),
            "Shuffle": GLib.Variant("b", False), "Metadata": GLib.Variant("a{sv}", self.metadata()),
            "Volume": GLib.Variant("d", 0.8), "Position": GLib.Variant("x", self.position()),
            "MinimumRate": GLib.Variant("d", 1.0), "MaximumRate": GLib.Variant("d", 1.0),
            "CanGoNext": GLib.Variant("b", True), "CanGoPrevious": GLib.Variant("b", True),
            "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
            "CanSeek": GLib.Variant("b", True), "CanControl": GLib.Variant("b", True),
        }

    def changed(self, *names):
        all_props = self.props(PLAYER)
        self.conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                              GLib.Variant("(sa{sv}as)", (PLAYER, {n: all_props[n] for n in names}, [])))

    def seeked(self):
        self.conn.emit_signal(None, PATH, PLAYER, "Seeked", GLib.Variant("(x)", (self.position(),)))

    def set_playing(self, on):
        self.offset = self.position() / 1e6
        self.since = time.monotonic()
        self.playing = on
        self.changed("PlaybackStatus")

    def jump(self, step):
        self.index = (self.index + step) % len(TRACKS)
        self.offset, self.since = 0.0, time.monotonic()
        self.changed("Metadata", "PlaybackStatus")
        self.seeked()

    def call(self, conn, sender, path, iface, method, params, invocation):
        if method == "Next":
            self.jump(1)
        elif method == "Previous":
            self.jump(-1)
        elif method in ("Pause", "Stop"):
            self.set_playing(False)
        elif method == "Play":
            self.set_playing(True)
        elif method == "PlayPause":
            self.set_playing(not self.playing)
        elif method == "SetPosition":
            self.offset, self.since = params[1] / 1e6, time.monotonic()
            self.seeked()
        elif method == "Seek":
            self.offset, self.since = self.position() / 1e6 + params[0] / 1e6, time.monotonic()
            self.seeked()
        elif method == "Quit":
            GLib.idle_add(loop.quit)
        invocation.return_value(None)

    def get(self, conn, sender, path, iface, name):
        return self.props(iface).get(name)


player = Player(os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "."))
loop = GLib.MainLoop()
node = Gio.DBusNodeInfo.new_for_xml(XML)


def on_bus(conn, name):
    player.conn = conn
    for iface in node.interfaces:
        conn.register_object(PATH, iface, player.call, player.get, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.mpris.MediaPlayer2.vanksdemo",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, lambda *_: loop.quit())
loop.run()
