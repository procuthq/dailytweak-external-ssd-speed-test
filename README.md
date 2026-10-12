# DailyTweak macOS Storage Speed Test

A macOS shell script for measuring sequential write and read performance on external storage devices, including SSDs, HDDs, USB flash drives, and SD/microSD cards connected through compatible readers.

The script collects storage, filesystem, partition-map, Mac hardware, macOS, and connection information where available. It also generates a text report with the test results.

## Features

- Detects supported writable external and removable volumes.
- Lets you select a target volume when multiple candidates are found.
- Allows you to choose the test-data size.
- Generates random test data for sequential write and read measurements.
- Reports write and read speeds in MB/s and MiB/s.
- Includes the final system flush in the write-time measurement.
- Attempts to clear the read cache by unmounting and remounting the test volume.
- Records available device, filesystem, partition-map, and host information.
- Saves a text report in the directory from which the script was launched.
- Cleans up its temporary test files after the test completes.

## Requirements

- A Mac running macOS.
- Bash and standard macOS command-line utilities.
- A writable external storage volume or supported removable-storage volume.
- Enough free space for the selected test size and the script's safety margin.

SD and microSD cards require a compatible card reader or connection that macOS recognizes. Actual detection and reported device information depend on the hardware and macOS.

## Download

Download [`external-storage-speed-test.sh`](./external-storage-speed-test.sh) from this repository.

## How to Run

1. Download the script to your Mac.
2. Open Terminal and change to the directory containing the downloaded file. For example:

   ```bash
   cd ~/Downloads
   ```

3. Run the script with Bash:

   ```bash
   bash external-storage-speed-test.sh
   ```

4. If multiple supported volumes are detected, select the intended test volume.
5. Enter a test size when prompted, such as `5GB` or `100GB`.
6. Review the drive information and confirmation screen carefully.
7. Press Enter only after confirming that the correct volume is selected.

The script writes a temporary test file to the selected storage volume. It should not be run on a volume containing important data without first reviewing the script and understanding its cleanup behavior.

## Understanding the Results

**Sequential write speed** measures how quickly the test data is written to the selected volume. The reported write time includes the final system flush.

**Sequential read speed** measures how quickly the test file is read back. The script attempts to reduce the effect of cached data by unmounting and remounting the volume. If cache clearing is unsuccessful, the report should be interpreted accordingly.

- **MB/s** uses decimal megabytes: 1 MB = 1,000,000 bytes.
- **MiB/s** uses binary mebibytes: 1 MiB = 1,048,576 bytes.

Results can vary with the storage device, connection, cable, port, reader, filesystem, free space, test size, caching, and background activity.

Short tests may primarily reflect a drive's cache performance rather than its sustained write speed. For meaningful comparisons, keep the test size, connection path, filesystem, and test conditions consistent.

## Safety and Limitations

- **Verify the target volume before starting.** The test writes data to the selected volume.
- Keep sufficient free space available. The script calculates a test-size limit and retains a safety margin, but you should still review the displayed values.
- Do not disconnect the device while the test is running.
- Do not interrupt the test unless necessary. The script removes its test files if you press Ctrl-C. If the Mac loses power or the drive is unplugged mid-test, delete the hidden '.ssd-speedtest.*' folder on the drive.
- The script is intended for sequential transfer testing, not endurance, TBW, temperature, or long-term reliability testing.
- Reported connection details are based on information available from macOS and may not always identify the exact negotiated storage-device link.
- The cable questions are optional and are skipped for the built-in SD slot.
- Cable names and advertised cable ratings are user-entered information, not independently verified measurements.
- The script does not verify SD-card speed-class ratings such as UHS, U3, V30, or A2.
- NAND technology identified by the script is based on a built-in model-name lookup where available, not direct hardware interrogation.

## Reproducibility

For comparisons, document the storage model and capacity, filesystem, partition map, Mac model, macOS version, connection path, cable and reader, test size, and the number of repeated runs.

This project provides a repeatable testing approach, but results from different scripts or test applications are not necessarily directly comparable because their buffering, timing, cache handling, and write-flush behavior may differ.

## Project

Created for **DailyTweak** to document practical storage performance testing on macOS.

Repository: [dailytweak-external-ssd-speed-test](https://github.com/procuthq/dailytweak-external-ssd-speed-test)
