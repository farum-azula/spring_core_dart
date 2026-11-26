# Recording a debug session

Status: planned, after release 0.10 (the owner, 26 November 2026); maybe
in 1.0.0, not decided ([release_1_0.md](release_1_0.md)). Not started.

## The idea

A **Record** button, in the debug console's header and in the debug panel,
records everything the debug tools see from the moment it is pressed until
**Stop**: the log records, the HTTP requests and WebSocket frames with
their timings, the signals (ticks, flushes, effects, `@Computed` runs),
the beans created and destroyed, the screens navigated to, the frames and
the frames lost, the memory over time, the observations (`@Observed`).
The recording is one file a tester sends to the developer; opened in the
debug tools, it shows everything on one timeline: what ran after what.

The owner's goal beyond that: **a video of the app's canvas with the events
mapped onto the same timeline**, so the developer sees what was on the
screen when a request failed or a signal ticked.

## What exists already

Most of the sources record today, each on its own:

- the logs: `LogBuffer`;
- the network: `DebugNetworkJournal`, with the phases of a request, the
  socket's connect time, uptime, heartbeat latency;
- the signals: `SignalsDebugRecorder` (ticks, flushes, effects per frame,
  reads, timings);
- the beans: `DebugBeanGraph` (created, destroyed, route scopes);
- the frames: `FrameStats`; the timeline's observations;
- the memory: the Isolates tab (being extended in 0.10).

## What it needs

1. **One event stream:** every source writes timed events (one monotonic
   clock) into a ring buffer while recording, each event typed (`log`,
   `http`, `ws`, `signal`, `bean`, `route`, `frame`, `memory`,
   `observation`), secrets masked as each source masks them today.
2. **The file:** one versioned JSON document (events, the app's name and
   build, the device, the start time). Exported through `DebugFileExport`
   (a download on the web, Downloads on a desktop, the app's own share
   exporter on a phone).
3. **The viewer:** the Timeline tab opens a file (Open, or a drop on the
   web) and draws one lane per source: requests as bars, log records as
   dots in their level's colour, signal ticks, frames, memory as a graph,
   screens as spans. A click on an event shows its detail as the source's
   own tab does.
4. **The canvas video** (the hard part): frames of the app's canvas
   captured while recording (`RenderRepaintBoundary.toImage` on the root,
   a few frames a second, scaled down; or the platform's screen recording
   where the app may use it), encoded small (a sequence of compressed
   frames, or a video codec through a platform API), and played in the
   viewer under the lanes, scrubbed with the timeline. Open questions: its
   cost while recording (frames must not drop), the file's size, the
   web's and the phones' limits, privacy (what the screen shows; a mask
   for chosen widgets, as the logs mask secrets).

## Where it lives

Likely a starter of its own, with the debug tools around it: the owner
(26 November 2026) suggests moving the Flutter debug tooling out of
`spring_boot_starter_flutter` into a separate starter (as
`spring-boot-devtools` is in Spring): the console, its panes, the graphs,
the network recorder, the recorder of sessions. The Flutter starter keeps
only the hooks (`WidgetAwareBuildTracker`, the overlay dock, the
shortcuts). Today the debug code is about as large as the rest of the
starter (some 23 500 lines against 26 800); none of it reaches a release
build, but it weighs on the package, its tests and its reviews.

As everything in the debug tools: every part has a build switch, and with
it off nothing of it is in the app.
