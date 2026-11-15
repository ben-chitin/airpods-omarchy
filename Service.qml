import QtQuick
import Quickshell
import Quickshell.Io

// One backend process for the whole shell, since a bar is created per monitor.
// It holds the connection to the AirPods, prints a JSON line when anything
// about them changes, and takes a command per line.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string script: Quickshell.env("HOME") + "/.config/omarchy/plugins/bhj.airpods/airpods"

  property bool connected: false
  // AirPods paired here but not connected, by name, for the Connect button.
  property string known: ""
  property bool connecting: false
  property string error: ""
  property string name: ""
  property string model: ""
  property string mode: ""
  property bool allowOff: false
  property bool conversation: false
  property var battery: ({})
  property var ears: []
  property bool autopause: true
  property bool duck: true
  property bool ready: false
  property var queued: []

  function send(line) {
    if (ready) {
      daemon.write(line + "\n")
      return
    }
    queued.push(line)
    if (!daemon.running) daemon.running = true
  }

  function sync() { send("sync") }

  function connect() {
    if (known === "" || connected) return
    connecting = true
    error = ""
    send("connect")
  }

  // Shown at once; the AirPods' answer confirms it.
  function setMode(value) {
    mode = value
    send("mode " + value)
  }

  function setConversation(on) {
    conversation = on
    send("conversation " + (on ? "on" : "off"))
  }

  function setAutopause(on) {
    autopause = on
    send("autopause " + (on ? "on" : "off"))
  }

  function setDuck(on) {
    duck = on
    send("duck " + (on ? "on" : "off"))
  }

  function ingest(line) {
    var data
    try {
      data = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!data || data.type !== "state") return
    connected = data.connected === true
    known = String(data.known || "")
    connecting = data.connecting === true
    error = String(data.error || "")
    name = String(data.name || "")
    model = String(data.model || "")
    mode = String(data.mode || "")
    allowOff = data.allowOff === true
    conversation = data.conversation === true
    battery = data.battery || {}
    ears = data.ears || []
    autopause = data.autopause !== false
    duck = data.duck !== false
  }

  Process {
    id: daemon
    command: [root.script, "serve"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
    onStarted: {
      root.ready = true
      var lines = root.queued
      root.queued = []
      for (var i = 0; i < lines.length; i++) daemon.write(lines[i] + "\n")
    }
    onExited: {
      root.ready = false
      root.connected = false
      restartTimer.start()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: daemon.running = true
  }
}
