# Samsung T7 2TB — Test Results

**Project:** DailyTweak macOS Storage Speed Test  
**Drive:** Samsung Portable SSD T7, 2TB

These results document the specific tests performed for the DailyTweak review. They are not guaranteed performance figures for every drive, computer, connection, or test run.

## 1. Blackmagic Disk Speed Test

Results are averages of three runs. Values are write/read in decimal MB/s.

| Connection path | Write (MB/s) | Read (MB/s) |
|---|---:|---:|
| UGOURD USB4 cable, direct to MacBook Pro | 1,407.1 | 647.8 |
| Samsung USB-C to USB-C cable, direct to MacBook Pro | 1,412.3 | 637.8 |
| Samsung USB-A to USB-C cable via Satechi Thunderbolt 4 Slim Hub USB-A port | 1,171.2 | 613.3 |
| Baseus USB 2.0 USB-A to USB-C cable via the same Satechi hub path | 44.5 | 31.4 |
| Samsung USB-A to USB-C cable via BenQ EX2710U monitor USB-A port | 611.7 | 333.6 |

Note: 1,407.1 MB/s is about 11.3 Gbps, above the 10 Gbps limit of the T7’s USB 3.2 Gen 2 link, so this write figure likely includes caching or a measurement artifact and should not be read as the drive’s real write speed.

### Interpretation

- Connection path affected the measured results, particularly when using the USB 2.0 cable.
- The T7 uses USB 3.2 Gen 2, rated for up to 10 Gbps. A 40 Gbps-rated cable does not make the drive a 40 Gbps device.
- Converting MB/s to Gbps is a mathematical conversion, not a measurement of the negotiated USB link speed.
- The direct-connection Blackmagic write figures exceed Samsung's advertised 1,000 MB/s figure. These are results from this specific benchmark setup, not a guarantee of sustained real-world write speed.

## 2. Sequential 100 GB Transfer Test

| Setting | Recorded configuration |
|---|---|
| Drive | Samsung Portable SSD T7, 2TB |
| Cable | Samsung USB-C to USB-C, rated for USB 3.2 Gen 2, 10 Gbps |
| Filesystem | exFAT |
| Test data | Random data |
| Block size | 64 MiB |
| Write speed | 510.7 MB/s |
| Read speed | 985.2 MB/s |
| Write timing | Includes final flush to disk |
| Read-cache handling | Volume unmounted and remounted before reading |

The write and read results represent different phases of the sequential transfer test. The write measurement includes the final flush, and the volume was unmounted and remounted before the read test to reduce the effect of cached data.

This was not an endurance, TBW, thermal-stress, or long-term reliability test.

## 3. Samsung Magician Benchmark

Recorded results with the T7 connected directly using the Samsung USB-C cable:

| Measurement | Result |
|---|---:|
| Sequential read | 888 MB/s |
| Sequential write | 857 MB/s |
| Random read | 20,400 IOPS |
| Random write | 8,595 IOPS |

## 4. Limitations

- Results depend on the drive, host, cable, adapter, port, filesystem, test size, cache behavior, and background activity.
- The Blackmagic figures are three-run averages, not guaranteed sustained speeds.
- The published shell script is a general-purpose implementation. Its measurements may differ from those recorded above.
- USB cable ratings do not establish the negotiated link speed.
- No physical testing of the T7 Shield or T9 is implied by this document.

## Reproducibility

For useful comparisons, record the drive model and capacity, filesystem, Mac model, macOS version, connection path, cable or reader, test size, and test conditions. Keep these consistent when comparing results.

**Created for DailyTweak.**
