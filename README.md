# VEP Schema

Dataplane interface definitions for the Vehicle Edge Platform using [COVESA IFEX](https://github.com/COVESA/ifex) format.

## Overview

This repository defines the message types exchanged on the VEP internal data bus (DDS/Zenoh). These interfaces are the contract between:

- **Probes** (CAN, OTEL, AVTP) that produce telemetry
- **Bridges** (KUKSA, RT) that route data between systems
- **Exporters** that offboard data to cloud/backend systems

## Files

| File | Types | Origin/Standard |
|------|-------|-----------------|
| `types.ifex` | Header, KeyValue | VEP common |
| `vss-signal.ifex` | VssSignal, VssValue, VssQuality, VssStructValue | COVESA VSS |
| `events.ifex` | Event, Severity | VEP |
| `diagnostics.ifex` | ScalarMeasurement, VectorMeasurement, MatrixMeasurement | VEP |
| `otel-metrics.ifex` | OtelCounter, OtelGauge, OtelHistogram, OtelSummary | OpenTelemetry |
| `otel-logs.ifex` | OtelLogEntry, OtelLogLevel | OpenTelemetry |
| `avtp.ifex` | AvtpCanFrame, AvtpCanBatch, AvtpCanTrace, AvtpStreamStats | IEEE 1722 |
| `uds-dtc.ifex` | UdsDtc, UdsSnapshot, UdsDid, UdsDtcBatch | ISO 14229 UDS |
| `security.ifex` | SecurityIncident, ThreatLevel | VEP (VSOC) |
| `opaque.ifex` | MemoryDump, OpaqueCapture | VEP (debug) |

## Dependencies

```
types.ifex (common)
    ├── vss-signal.ifex
    │       └── events.ifex (uses VssSignal for context)
    ├── diagnostics.ifex
    ├── otel-metrics.ifex
    ├── otel-logs.ifex
    ├── avtp.ifex
    ├── uds-dtc.ifex
    ├── security.ifex
    └── opaque.ifex
```

Each domain owns its own value representation:
- **VSS**: `VssValue` with full type system (primitives, arrays, structs)
- **OTEL metrics**: `double` values with labels
- **UDS**: Raw `uint8[]` DID data
- **Diagnostics**: `double` / `double[]` measurements

## Topic Naming Convention

Topics follow the pattern `rt/<domain>/<type>`:

| Topic | Message Type | Key Field(s) |
|-------|--------------|--------------|
| `rt/vss/signals` | VssSignal | `path` |
| `rt/vss/signals/batch` | VssSignalBatch | - |
| `rt/vss/actuators/target` | VssSignal | `path` |
| `rt/vss/actuators/actual` | VssSignal | `path` |
| `rt/events` | Event | `event_id` |
| `rt/diagnostics/scalar` | ScalarMeasurement | `variable_id` |
| `rt/diagnostics/vector` | VectorMeasurement | `variable_id` |
| `rt/diagnostics/matrix` | MatrixMeasurement | `variable_id` |
| `rt/otel/counters` | OtelCounter | `name` |
| `rt/otel/gauges` | OtelGauge | `name` |
| `rt/otel/histograms` | OtelHistogram | `name` |
| `rt/otel/summaries` | OtelSummary | `name` |
| `rt/otel/logs` | OtelLogEntry | - |
| `rt/avtp/can/frames` | AvtpCanFrame | `stream_id`, `can_id` |
| `rt/avtp/can/batch` | AvtpCanBatch | `stream_id` |
| `rt/avtp/can/trace` | AvtpCanTrace | - |
| `rt/avtp/stats` | AvtpStreamStats | `stream_id` |
| `rt/uds/dtc` | UdsDtc | `ecu_id`, `dtc_number` |
| `rt/uds/dtc/batch` | UdsDtcBatch | `ecu_id` |
| `rt/security/incidents` | SecurityIncident | `incident_id` |
| `rt/debug/memory` | MemoryDump | `ecu_id` |
| `rt/debug/capture` | OpaqueCapture | `capture_type` |

## QoS Recommendations

| Category | Reliability | Durability | History |
|----------|-------------|------------|---------|
| VSS signals (sensors) | Best Effort | Volatile | Keep Last 1 |
| VSS signals (actuators) | Reliable | Volatile | Keep Last 1 |
| Events | Reliable | Transient Local | Keep Last 100 |
| Diagnostics | Best Effort | Volatile | Keep Last 1 |
| OTEL metrics | Best Effort | Volatile | Keep Last 1 |
| OTEL logs | Reliable | Transient Local | Keep Last 1000 |
| UDS DTCs | Reliable | Transient Local | Keep All |
| Security | Reliable | Transient Local | Keep All |
| Debug | Best Effort | Volatile | Keep Last 10 |

## Code Generation

### Generate Protobuf (Zenoh, gRPC)

```bash
ifexgen --format protobuf ifex/types.ifex -o generated/proto/
```

### Generate DDS IDL (CycloneDDS)

```bash
# Custom template needed - IFEX doesn't have built-in DDS IDL support
./generate_idl.sh
```

## Versioning

Each `.ifex` file declares `major_version` and `minor_version`:
- **Major**: Breaking changes (field removal, type changes)
- **Minor**: Backwards-compatible additions

## License

Apache-2.0
