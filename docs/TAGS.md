# Tags

Registry for greppable `[[type:slug]]` anchors in the TVC fork of HaishinKit. Upstream code
carries none; only the fork's own changes are tagged here. The consuming app
(`mobile_streaming`) keeps its own registry and names fork call sites from there
(`[[contract:encoder-stats]]`, `[[contract:limit-reason]]`).

| Tag | Location | Purpose |
|-----|----------|---------|
| `[[gotcha:ts-pmt-row-per-pid]]` | `SRTHaishinKit/Sources/TS/TSWriter.swift` (`setElementaryStream`, the `audioFormat`/`videoFormat` didSets); `SRTHaishinKit/Tests/TS/TSWriterTests.swift` | A format-description change on the TS writer replaces the PMT row for that PID; it used to append one. Harmless while formats changed once per stream, wrong once the TVC adaptive-resolution work makes mid-stream resolution changes routine: every encoder-session swap at a new `videoSize` arrives as a new CMFormatDescription, and with append the PMT carried one row for PID 256 per rung ever visited, for the life of the publish. Demuxers key by PID and survived it, but the table grew without bound and stopped describing the program. The continuity-counter reset and the PMT rewrite that follow a change are kept on purpose. |
