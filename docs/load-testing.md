# Load testing

`tool/load.dart` measures how much load a server built on the framework
takes. For each scenario it answers two questions:

- **the highest sustainable QPS**: how many requests a second the server
  answers in time, without errors;
- **the breaking point**: at what load it stops answering, and whether it
  comes back afterwards.

The server is the bench application, `tool/load_bench`: a small server on
`spring_boot_starter_web`, the security starter and the data starter, with
one endpoint per scenario. The load comes from
[oha](https://github.com/hatoo/oha). The tool raises the load in steps,
reads oha's numbers and the server's memory after each step, and writes a
report.

Beyond these sweeps the tool measures how the throughput grows with the
server's isolates, what happens while their number changes under load,
whether CPU-bound work leaves the server responsive, and what the server
does when it is asked for more than its limits.

Read this page when you want to measure a change of the web stack, compare
two configurations (one isolate against four), or read a report of the
nightly job.

**Contents**

1. [Install oha](#1-install-oha)
2. [Run it](#2-run-it)
3. [The scenarios](#3-the-scenarios)
4. [How a step is judged](#4-how-a-step-is-judged)
5. [Why the latency is corrected](#5-why-the-latency-is-corrected)
6. [Rate steps and transfer steps](#6-rate-steps-and-transfer-steps)
7. [The report](#7-the-report)
8. [Comparing runs](#8-comparing-runs)
9. [Isolates: how the throughput scales](#9-isolates-how-the-throughput-scales)
10. [Scaling while loaded](#10-scaling-while-loaded)
11. [CPU-bound work](#11-cpu-bound-work)
12. [Overload checks](#12-overload-checks)
13. [The bench server](#13-the-bench-server)
14. [The CI job](#14-the-ci-job)
15. [Limits](#15-limits)

---

## 1. Install oha

oha is a load generator written in Rust. The tool needs it on the `PATH`
(or `--oha <path>`); without it, it stops with the install command.

```sh
brew install oha                 # macOS
cargo install oha --locked       # any system with Rust
```

Release binaries for Linux, macOS and Windows are on
[its releases page](https://github.com/hatoo/oha/releases). The tool is
written for oha 1.16; the tests read the JSON of that version
(`tool/test/load/`).

## 2. Run it

```sh
dart pub get
dart run tool/load.dart                        # every sweep, about 20 minutes
dart run tool/load.dart --scenarios text,json  # two scenarios
dart run tool/load.dart --scenarios api --rates 1000,2000,4000,8000
dart run tool/load.dart --start 500 --step 500 --max 5000 --duration 20s
dart run tool/load.dart --scenarios api --isolates 1,2,4   # section 9
dart run tool/load.dart --scenarios scaling,cpu,overload   # sections 10 to 12
dart run tool/load.dart --help
```

The tool:

1. builds the bench server to a native executable (`dart build cli`);
   `--no-compile` runs it with `dart run` instead, which starts faster but
   measures the JIT, not what a deployed server does;
2. starts it on a free port and waits until it answers;
3. runs each scenario: a short warm-up, then the steps, from the lowest
   load to the highest. It stops a scenario at its breaking point
   (`--keep-going` runs the remaining steps too);
4. stops the server, also on Ctrl+C and on errors;
5. writes the report into `--out` (default `build/load`).

| Option | Default | Meaning |
|---|---|---|
| `--scenarios a,b` | `sweep` | scenarios, or the groups `sweep` (`api` and `files`), `api`, `files`, `scaling`, `overload`, `all` |
| `--isolates 1,2,4,auto` | | run the sweeps once per number of server isolates and compare them ([section 9](#9-isolates-how-the-throughput-scales)) |
| `--rates 500,1000` | `500,1000,2000,4000,8000,16000,32000` | the rates of the steps, in requests a second |
| `--start N --step N --max N` | | the same as a range |
| `--concurrency 1,2,4` | `1,2,4,8` | the connections of the transfer steps ([section 6](#6-rate-steps-and-transfer-steps)) |
| `--duration 10s` | `10s` | how long a step lasts, or the load of a check |
| `--warmup 2s` | `2s` | unmeasured load before the first step of a scenario; `0` for none |
| `--pause 1s` | `1s` | rest between two steps |
| `--connections 50` | `50` | connections of the rate steps |
| `--timeout 5s` | `5s` | a request of a rate step unanswered for so long is a timeout |
| `--transfer-timeout 2m` | `2m` | the same for a transfer |
| `--p99 100ms` | `100ms` | the highest p99 latency of a sustained step |
| `--break-p99 1s` | `1s` | a p99 above it is a breaking point |
| `--max-errors 0.1` | `0.1` | a sustained step has less than this percentage of errors |
| `--keep-going` | | run the steps after the breaking point too |
| `--no-keepalive` | | a new connection for every request |
| `--window 2s` | `2s` | the windows of the scaling scenarios ([section 10](#10-scaling-while-loaded)) |
| `--scale-to 3` | `3` | the isolates `scale-manual` scales to, and the most `scale-auto` may start |
| `--medium-size 10MB`, `--huge-size 512MB` | | the sizes of the generated files |
| `--server-arg --key=value` | | an argument for the server; repeatable |
| `--<a.b>=value` | | an option with a dot in its name is a property of the server and is passed to it: `--server.isolates.count=4` |
| `--label isolates=4` | | names the run in the reports and in `--compare` |
| `--out <dir>` | `build/load` | where the reports go |
| `--no-compile` | | `dart run` instead of a native executable |
| `--oha <path>`, `--oha-threads N` | | the oha executable, and its worker threads (default: one a core) |
| `--compare a.json b.json` | | compare reports ([section 8](#8-comparing-runs)) |

A longer step gives a sharper answer: a server that is 2 % short of a rate
falls behind slowly, and only a long step shows it. Use `--duration 30s`
or more for numbers you want to keep.

## 3. The scenarios

Each scenario is one request, sent again and again.

| Scenario | Request | What it measures |
|---|---|---|
| `text` | `GET /text` | the least a request costs: routing and a `String` |
| `json` | `GET /json` | 50 objects written as JSON by the `ObjectMapper` |
| `json-post` | `POST /json` | a JSON body read and validated (`@Valid`); one body in ten is invalid and answered with 400, which counts as a good answer |
| `secure` | `GET /secure/text` | the security filter chain: a bearer token (a JWT signed with HS256) checked on every request |
| `db-read` | `GET /db/items/{id}` | a row read by its key through a `spring_boot_starter_data` repository, on SQLite; the id is random, from 1 to 999 |
| `db-write` | `POST /db/items` | an insert through the same repository |
| `static` | `GET /static/hello.txt` | a small file from the static resource handler |
| `download-small` | `GET /files/small` | a file of 4 KB as a `Resource` |
| `download-range` | `GET /files/huge` with `Range` | 64 KiB out of the huge file (206) |
| `download-medium` | `GET /files/medium` | a file of 10 MB, streamed from disk |
| `download-huge` | `GET /files/huge` | a file of 512 MB (`--huge-size`), streamed from disk |
| `upload-small-multipart`, `upload-medium-multipart`, `upload-huge-multipart` | `POST /upload/multipart` | the same files sent as `multipart/form-data`; the resolver streams the part to a temporary file |
| `upload-small-raw`, `upload-medium-raw`, `upload-huge-raw` | `PUT /upload/raw` | the same files sent as the body, which the handler pipes to a file as it arrives |

The groups: `api` is the first seven, `files` the downloads and uploads,
`sweep` both (the default). These are the sweeps: one request, loaded in
rising steps. The other scenarios each start a server of their own with
the settings they are about:

| Scenario | Group | What it shows |
|---|---|---|
| `scale-manual`, `scale-auto` | `scaling` | the number of isolates changing under load ([section 10](#10-scaling-while-loaded)) |
| `cpu` | | CPU-bound work in the request's isolate and in a task isolate ([section 11](#11-cpu-bound-work)) |
| `overload-concurrent`, `overload-connections`, `slow-headers`, `slow-body`, `big-body` | `overload` | the server's limits and timeouts ([section 12](#12-overload-checks)) |

`all` is every scenario.

The files are generated by the server when it starts, into
`build/load_bench/data`, and kept for the next run. The small and medium
ones hold pseudo-random bytes (the same on every machine). The huge one is
a sparse file: it reads as zeros and takes no room on disk. None of them
is committed.

**Why a bearer token and not HTTP Basic.** With HTTP Basic the password is
checked on every request. The security starter checks each password on
another isolate (`Isolate.run`) and only a few at a time
(`PasswordCheckLimiter`), and answers 503 past that limit. That is right
for logins, but it would measure the password checks, not the filter
chain. A token's signature is checked in the request itself, with no such
limit, as an API's requests are.

**Uploads and memory.** Neither upload is written to hold the body in
memory: the multipart resolver streams a part to a temporary file, and the
raw handler pipes the body to a file. The report is the proof to read: the
server's memory (RSS) of an upload step, next to the size of the file. A
server that held bodies in memory would need the file's size for every
connection. Memory still rises above the idle level during uploads: the
chunks in flight and the garbage not yet collected are memory too.

## 4. How a step is judged

A step is **sustained** when both hold:

- its p99 latency is at most `--p99` (100 ms);
- less than `--max-errors` (0.1 %) of its requests failed. A failure is a
  timeout, a refused or broken connection, or an answer with a status the
  scenario does not expect (a 500, a 503).

The **highest sustainable QPS** of a scenario is the good answers a second
of its last sustained step, counting only the steps before the first one
that was not sustained. A sustained step after a failed one is luck, not
capacity, so it does not count. The number is what the server answered,
not the rate that was asked for.

A step is **broken** when the server stopped answering in a useful time:

- a request timed out (`--timeout`);
- a connection was refused, reset or closed before its answer;
- nothing was answered at all;
- the p99 latency is above `--break-p99` (1 s).

The **breaking point** is the first broken step. After it the tool sends a
light request (`GET /bench/info`) until the server answers, for at most
15 seconds. The report says whether it **recovered** and after how long.
When the server's process is gone, the next scenario gets a new server and
the report counts the restart (`serverRestarts`).

Between the two thresholds a step is neither: `not sustained`, but not
broken. Answers with an unexpected status make a step not sustained; they
do not break it, since the server still answers.

Requests still running when a step's time is up are cut by oha. They are
neither answers nor errors, and the report counts them apart
(`abortedAtDeadline`).

## 5. Why the latency is corrected

A simple load generator sends a request, waits for the answer and sends
the next one. When the server stalls for a second, such a generator sends
nothing during that second. It records one slow request, and the hundreds
it should have sent in that second are never measured. The latency looks
fine while real users would have waited. This is called coordinated
omission.

oha avoids it. With a rate (`-q`) every request has a time at which it is
due. With `--latency-correction` a request's latency is counted from that
time, not from when it was sent. A request that waited behind a stalled
server is charged the whole wait.

So when the server cannot follow a rate, the corrected latency grows for
as long as the step lasts, and the p99 says so. Example from a real run: at
40 000 requests a second asked for, the server answered 4 861 a second.
No request failed, yet the p99 was 1.74 s after two seconds.

## 6. Rate steps and transfer steps

Small requests are loaded by **rate**: `--rates 500,1000,2000` are three
steps of 500, 1 000 and 2 000 requests a second, over `--connections`
connections. This is every `api` scenario and the small files.

A rate makes no sense for large bodies: 500 requests a second of a file of
1 GB is more than any network carries. The medium and huge downloads and
uploads are loaded by **concurrency** instead: `--concurrency 1,2,4,8` are
four steps with 1, 2, 4 and 8 connections, each sending one transfer after
the other as fast as it goes. A step lasts `--duration`, and the transfers
under way at the end are finished, not cut.

A transfer step is judged by its errors only. Its latency is the time of a
whole transfer, which depends on the size of the file, so no p99 threshold
applies. The report gives for these scenarios:

- the **MB/s** of each step and the peak over the steps;
- the most connections without errors;
- the first number of connections with timeouts or connection errors, if
  any.

For an upload the MB/s count the bodies of the good answers. For a
download they count the bytes received.

## 7. The report

`--out` (default `build/load`) receives:

| File | What |
|---|---|
| `report.md` | the summary, a table and charts for each scenario |
| `report.json` | every number, the options, the machine (cores, processor, system, Dart and oha versions) and the git commit |
| `server.log`, `server-<scenario>.log` | what each server printed |
| `raw/` | oha's JSON of each step, and the bodies sent |
| `isolates-<N>/report.md`, `report.json`, `scaling.md` | with `--isolates`: a report per number of isolates, and their comparison |

`report.md` starts with a summary table: for each scenario its highest
sustainable QPS, its breaking point, whether the server recovered, and
the highest memory. Then each scenario has:

- a table with one row per step: the good answers a second, the p50, p95,
  p99 and slowest latency, the share of errors, the timeouts, the refused
  connections, the status codes, the server's memory (the peak and the end
  of the step) and the processor cores the server kept busy;
- a Mermaid chart: the good answers a second as bars and the rate asked
  for as a line. Where the bars stay under the line, the server did not
  follow;
- a text chart of the p99 latency on a logarithmic scale, with the
  threshold marked. Mermaid's charts have no logarithmic axis, and the p99
  goes from a fraction of a millisecond to seconds.

**Memory** is the resident memory of the server's process, read with
`ps -o rss=` four times a second during the step. **Cores** is the
processor time the process used during the step, divided by the step's
length: `1` is one core busy all the time. With several isolates in one
process both numbers cover all of them. On Linux `ps` gives the processor
time in whole seconds, so the cores of a short step are rough.

GitHub renders the Mermaid charts in the job summary and when it shows
the file.

## 8. Comparing runs

Give each run a label and its own directory, then compare the reports:

```sh
dart run tool/load.dart --label isolates=1 --out build/load/1 \
  --server.isolates.count=1
dart run tool/load.dart --label isolates=4 --out build/load/4 \
  --server.isolates.count=4
dart run tool/load.dart --compare build/load/1/report.json \
  build/load/4/report.json --out build/load
```

The comparison is printed, and written to `comparison.md` when `--out` is
given. It has one column per run and the ratio of each to the first run:
the highest sustainable QPS, the breaking point, the peak MB/s and the
peak memory of every scenario.

Run the labels you compare on the same machine, one after the other, with
the same options. Two runs with the same label get their commit added to
tell them apart.

## 9. Isolates: how the throughput scales

A server can run several isolates on one port (`server.isolates.count`).
Each uses one processor core. `--isolates` measures what that gives:

```sh
dart run tool/load.dart --scenarios text,json,db-read --isolates 1,2,4 \
  --connections 128 --out build/load/isolates
```

The sweeps run once per value, each on a new server started with
`--server.isolates.count=<value>` (`auto`: one isolate per core). `--out`
receives a report per value (`isolates-1/report.md`, `isolates-2/...`) and
`scaling.md`, which is also printed.

**Every report says how many isolates served.** The tool asks the server
(`GET /bench/isolates`) how many isolates it runs and how many requests
each has taken, before and after every scenario. The report has the
number at the top, and for each scenario the share of the requests each
isolate answered. A run that asked for four isolates and got one says so
in bold, so it cannot pass for a measure of four.

`scaling.md` has a table per scenario, one row per number of isolates:

| Column | Meaning |
|---|---|
| Isolates | the isolates the server ran |
| Served | how many of them took at least 1 % of the requests |
| Sustainable | the highest sustainable QPS ([section 4](#4-how-a-step-is-judged)); it moves in the steps of the rates tried |
| Peak | the most good answers a second of any step, the overloaded one included: what the server puts out when it is full. Finer than the sustainable value, which is one of the rates |
| × | the ratio to the run with the fewest isolates |
| Efficiency | that ratio over the ratio of the isolates: 100 % is twice the throughput for twice the isolates |
| Breaking point | as in the report |

Under the table: where it **stops scaling**, the first number of isolates
whose peak is less than 10 % above the run before.

How to read it:

- A value with **≥** was sustained at the highest rate tried. The server
  can take more: raise `--rates`, or the efficiency means nothing.
- **Give the load enough connections** (`--connections 128`). A
  connection belongs to the isolate that accepted it, and stays there.
  With few connections the isolates get uneven shares, and the fullest
  one breaks first. The shares in the report show it.
- **The generator needs cores too.** With four isolates and oha on the
  same machine, oha may be the one that cannot follow. The `Cores` column
  of a step tells: a server on four isolates that broke while using two
  cores was not the limit.
- Efficiency under 100 % is normal: the isolates share the memory bus,
  the kernel's network stack and, for `db-*`, one SQLite file.

## 10. Scaling while loaded

The pool of isolates can change while the server runs: by hand, through
the `IsolateScaler` bean, or by itself with `server.isolates.scaling=auto`.
Two scenarios show what clients see meanwhile. Both load `GET /json` at a
fixed rate in **windows** of `--window` (2 s), and report a row per
window: the good answers a second, the p50 and p99, the errors and the
isolates serving at its end. Each window opens new connections, as new
clients would arrive.

Both measure first what one isolate takes: two seconds as fast as it
goes. The rates are multiples of that, so the scenarios fit any machine.

**`scale-manual`** starts one isolate (`server.isolates.count=1`,
`server.isolates.max=<--scale-to>`) and loads it with 1.5 times what it
takes, for the whole timeline:

1. three windows on one isolate: overloaded;
2. in the middle of a window, `POST /bench/isolates?to=3`; the call
   returns when the new isolates serve;
3. three windows on three isolates;
4. in the middle of a window, `POST /bench/isolates?to=1`; the call
   returns when the others take no more connections;
5. two windows on one isolate again.

The report gives the time each scaling call took, the **dip** (how far
the worst window during the scaling fell under the QPS before), **when
the new isolates helped** (from the call to the first window that kept up
with the rate), and the **errors of the drain** (the requests that failed
in the windows the scaling down touched). The connections open when the
pool grows stay with the old isolate, so the new ones help from the next
window on: new connections.

**`scale-auto`** starts one isolate with `server.isolates.scaling=auto`
and a ramp: 2 windows at half of what one isolate takes, 6 at 1.5 times,
12 at 0.3 times. The server's policy grows the pool when its isolates'
event loops run late, and shrinks it when they are free. The tool gives
it short thresholds, so the timeline lasts under a minute:

| Property | The tool passes | Default |
|---|---|---|
| `server.isolates.scale-up-after` | `2s` | `5s` |
| `server.isolates.scale-down-after` | `6s` | `2m` |
| `server.isolates.cooldown` | `4s` | `15s` |
| `server.isolates.scale-up-lag` | (default) | `10ms` |

The report gives when the overload began, how long until the first step
up, how long until a window kept up, the same for the way down, and the
**changes of direction**. One peak of load should give one: up, then
down. More is flapping.

The steps of the pool come from the server's log (the tool sets
`logging.level.spring.web.isolates=info`), with their reasons, and are
listed under the table in seconds from the start.

## 11. CPU-bound work

An isolate does one thing at a time. A request that computes for 25 ms
holds up every other request of its isolate for 25 ms. The
`IsolateTaskExecutor` runs such work in another isolate. `cpu` shows the
difference:

- `GET /cpu/inline?rounds=N` hashes a block N times in the request's
  isolate;
- `GET /cpu/task?rounds=N` does the same through
  `IsolateTaskExecutor.submitWith`.

The tool first finds the N that takes about 25 ms on the machine. Then,
for each endpoint, it sends 20 requests a second (half of one core) for
`--duration`, and beside them a **probe**: `GET /text` 100 times a second.
The probe's p50 and p99 say how long other requests waited. Last, it
measures the most work a second: four connections as fast as they go,
for three seconds.

The check passes when the probe's p99 with tasks is within `--p99` and
under the probe's p99 inline.

## 12. Overload checks

These are checks with a verdict, not sweeps. Each starts a server with one
limit set, breaks that limit, and judges what the server did. Beside each
runs a probe (`GET /text`, 20 a second), and after each the tool asks
whether the server still answers. The report has a row per expectation:
`ok`, `FAIL`, or `info` for a number that is reported and not judged.

| Check | The server | The load | It passes when |
|---|---|---|---|
| `overload-concurrent` | `server.max-concurrent-requests=8` | `GET /slow?ms=50` 600 times a second on 64 connections: the limit allows 160 a second | the rest is answered 503, fast (p99 within `--p99`); the server goes on answering about 160 a second; an accepted request does not wait (p99 within 50 ms and `--p99`); a 503 has `Retry-After`; no timeout, no broken connection |
| `overload-connections` | `server.max-connections=16` | `GET /text` on 64 connections | the connections over the limit get a fast 503 with `Retry-After` and `Connection: close`; those within it are served; no timeout |
| `slow-headers` | `server.connection-timeout=2s` | 200 connections that send a header line every half second and never finish | every one is dropped within twice the timeout (4 s; `dart:io` drops an idle connection between one and two timeouts); the memory rises by at most 256 KB a connection; the probe is answered in time |
| `slow-body` | `server.connection-timeout=2s` | 4 requests whose body stalls after 1 KB of 1 MB; 4 that send a byte every half second | a stalled body is answered 408 within twice the timeout, and its connection closed (up to 5 s later: after an early answer the server reads on for a body that ends late) |
| `big-body` | `server.max-http-request-body-size=1MB` | `POST /json` with the headers of a body of 256 MB; 2 MB in chunks; 256 MB sent as fast as it goes | both are answered 413 within a second; the server does not read the flood to its end (the client cannot write it all); the memory rises by at most 32 MB |

Two rows are `info` on purpose:

- **A body that trickles** is not cut by `server.connection-timeout`,
  which counts silence. The check reports whether such requests were
  still open at the end. `server.request-timeout` is the limit for them.
- **A client that keeps sending** an oversized body may read no 413. The
  server answers, reads up to 2 MB more and closes the connection with
  the rest unread, which resets it. A client that reads while it writes
  (curl) gets the 413. A client whose write fails first (a `dart:io`
  socket) gets "broken pipe". The check reports which it saw.

In the probe of the two `overload-*` checks a 503 counts as an answer:
the limit counts the probe's requests too.

## 13. The bench server

`tool/load_bench` is a workspace package like the examples: its generated
code is committed (`dart run build_runner build` after a change of its
beans), and CI checks it. It runs alone too:

```sh
cd tool/load_bench
dart run bin/main.dart --server.port=18080
curl localhost:18080/bench/info
```

Its settings are properties, so the tool (or you) can change them on the
command line:

| Property | Default | Meaning |
|---|---|---|
| `server.port` | `18080` | the tool picks a free port |
| `bench.directory` | `build/load_bench` | where the files are generated, the uploads written and the SQLite database kept; created at startup |
| `bench.files.small-size`, `medium-size`, `huge-size` | `4KB`, `10MB`, `512MB` | the sizes of the files of `/files/{name}` |
| `bench.upload.max-size` | `2GB` | the largest body of `PUT /upload/raw` |
| `spring.web.multipart.max-file-size`, `max-request-size` | `2GB` | the limits of `POST /upload/multipart` |
| `bench.json.items` | `50` | the objects of `GET /json` |
| `bench.security.jwt-secret`, `token-lifetime` | a secret of the bench, `24h` | the key and the lifetime of the token of `/secure/**` |
| `spring.datasource.url` | `sqlite:file:${bench.directory}/load_bench.db` | the database; the migration creates `items` with 1 000 rows |
| `spring.datasource.pool.max-size` | `4` | the connections of the pool |

`GET /bench/info` answers the state of the server: `ready` (the files
exist), `pid`, `rss` and `maxRss` in bytes, `processors`, the size of each
file and the bearer `token`. The tool waits for `ready`, samples the
memory of `pid` and sends the token.

Its other endpoints for the tool:

| Endpoint | What |
|---|---|
| `GET /bench/isolates` | the isolate that answers (`isolate`, `primary`), the pool (`pool`, `count`, `min`, `max`) and the load of each isolate (`loads`: its event loop's lag, its requests in flight and, under `details.requests`, the requests it has taken). Only the first isolate knows the pool: another one answers `"count": null`, and the tool asks again on a new connection |
| `POST /bench/isolates?to=N` | scales the pool through the `IsolateScaler` bean and answers once it has N isolates. 409 without a pool (`server.isolates.max` or `count` above 1 makes one); 421 from an isolate that is not the first: ask again on a new connection |
| `GET /cpu/inline?rounds=N`, `GET /cpu/task?rounds=N` | SHA-256 over 4 KB, N times, in the request's isolate or through the `IsolateTaskExecutor`; the answer has the time it took (`micros`) and the isolate |
| `GET /slow?ms=N` | answers after N milliseconds without using the processor |

**Several isolates** each run the whole bench: each has its own beans,
and they share what is outside the process's memory. The files are
generated under a temporary name and renamed, so no isolate reads half a
file. The bearer token is signed with one secret, so a token of one
isolate is good for all. The SQLite database is one file: the first
isolate migrates it before the others start, and every isolate has its
own pool of connections to it.

Any other property of the framework works the same way, for example
`--server.compression.enabled=true` or the isolates of the server.

## 14. The CI job

`.github/workflows/load.yml` runs the tool on a GitHub runner:

- **when:** every night, and by hand (Run workflow) with the scenarios,
  the duration of a step, the rates and arguments for the server. Never on
  a push: a run takes about 20 minutes and its numbers are not a pass or
  a fail;
- **`load`:** every sweep scenario, six rates, 10 seconds a step, a huge
  file of 256 MB. oha comes from a release binary of a fixed version,
  checked by its SHA-256. The matrix of the job has one entry per run: a
  label and the server arguments that make it differ; the `compare` job
  puts the entries side by side;
- **`isolates`:** the `api` scenarios on 1, 2 and 4 isolates
  (`--isolates 1,2,4`, 128 connections, oha on 2 threads), with
  `scaling.md` in the summary. A hosted runner has 4 cores: the run with
  4 isolates shares them with oha, so its efficiency there is a floor;
- **`behaviour`:** the scaling timelines, `cpu` and the overload checks
  (`--scenarios scaling,cpu,overload`). A check that fails is in the
  summary and the report; the job itself stays green, as the numbers of
  a shared runner are no gate;
- **result:** `report.md` in each job's summary, and `report.json`,
  `report.md`, the server's logs and oha's raw output as artifacts
  (`load-<label>`, `load-isolates`, `load-behaviour`). The summary of
  `load` also compares the run with the previous successful run of the
  same label.

**Shared runners are noisy.** Other jobs run on the same host, the
processor differs from one day to the next, and oha shares the machine's
cores with the server. Compare ratios: between the labels of one run, or
against the previous run on the same runner type. Do not compare absolute
numbers with another machine's.

## 15. Limits

- **The generator shares the machine.** oha takes processor time the
  server could use. With few cores, or a server on several isolates, give
  oha a fixed share (`--oha-threads 2`) and keep it the same in every run
  you compare.
- **Loopback only.** The requests never leave the machine: no network
  latency, no TLS, no proxy.
- **One request per scenario.** A real client mixes requests; a scenario
  repeats one.
- **SQLite takes one writer at a time.** `db-write` measures the
  repository on SQLite, not what another database would do.
- **Connections stay with their isolate.** With several isolates a
  connection is served by the one that accepted it until it closes. A
  sweep's connections are opened once per step, and a timeline's once per
  window; a real client's keep-alive connections may live longer and see
  a new isolate later.
- **A timeline sees in windows.** What happens within a window of two
  seconds is one row; the server's log lines under the table have the
  exact times.
- **macOS and Linux.** The memory and the processor time come from `ps`.
