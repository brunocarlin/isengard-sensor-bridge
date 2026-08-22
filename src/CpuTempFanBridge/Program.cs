using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Linq;
using System.Runtime.Versioning;
using System.Text;
using System.Text.Json;
using System.Threading;
using LibreHardwareMonitor.Hardware;

[assembly: SupportedOSPlatform("windows")]

internal static class Program
{
    private const string MapName = @"Global\HWiNFO_SENS_SM2";
    private const string MutexName = @"Global\HWiNFO_SM2_MUTEX";
    private const uint ActiveSignature = 0x53695748; // "HWiS"

    private sealed record Reading(string Sensor, string Label, string Unit, double Value);
    private sealed record LhmReading(string HardwareType, string HardwareName, string SensorType, string SensorName, float Value, string Identifier);

    private static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0].Equals("--watch", StringComparison.OrdinalIgnoreCase))
        {
            int? parentPid = args.Length >= 4 && args[2].Equals("--parent", StringComparison.OrdinalIgnoreCase)
                && int.TryParse(args[3], out int parsedPid) ? parsedPid : null;
            return Watch(args[1], parentPid);
        }

        if (args.Length >= 2 && args[0].Equals("--watch-lhm", StringComparison.OrdinalIgnoreCase))
            return WatchLhm(args[1]);

        if (args.Length >= 1 && args[0].Equals("--list-rpm", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                foreach (var reading in ReadSnapshot().Where(r => r.Unit.Equals("RPM", StringComparison.OrdinalIgnoreCase)))
                    Console.WriteLine($"{Math.Round(reading.Value):0}\t{reading.Sensor}\t{reading.Label}");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 1;
            }
        }

        if (args.Length >= 1 && args[0].Equals("--list-lhm", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                foreach (var reading in ReadLhmSnapshot())
                    Console.WriteLine($"{reading.HardwareType}\t{reading.HardwareName}\t{reading.SensorType}\t{reading.SensorName}\t{reading.Value.ToString(CultureInfo.InvariantCulture)}\t{reading.Identifier}");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return 1;
            }
        }

        if (args.Length >= 2 && args[0].Equals("--list-lhm-file", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var lines = ReadLhmSnapshot().Select(reading =>
                    $"{reading.HardwareType}\t{reading.HardwareName}\t{reading.SensorType}\t{reading.SensorName}\t{reading.Value.ToString(CultureInfo.InvariantCulture)}\t{reading.Identifier}");
                File.WriteAllLines(args[1], lines, Encoding.UTF8);
                return 0;
            }
            catch (Exception ex)
            {
                File.WriteAllText(args[1], "ERROR: " + ex, Encoding.UTF8);
                return 1;
            }
        }

        try
        {
            var selected = SelectCpuFan(ReadSnapshot());
            Console.WriteLine(selected is null
                ? "CPU fan reading not found."
                : $"{Math.Round(selected.Value):0}\t{selected.Sensor}\t{selected.Label}\t{selected.Unit}");
            return selected is null ? 2 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static int Watch(string outputDirectory, int? parentPid)
    {
        Directory.CreateDirectory(outputDirectory);
        string rpmPath = Path.Combine(outputDirectory, "CpuTempFanBridge.rpm");
        string statusPath = Path.Combine(outputDirectory, "CpuTempFanBridge.status");

        while (true)
        {
            if (parentPid.HasValue && !IsProcessRunning(parentPid.Value)) return 0;
            try
            {
                var selected = SelectCpuFan(ReadSnapshot());
                if (selected is null)
                {
                    WriteAtomic(statusPath, "ERROR: No CPU fan RPM reading was found in HWiNFO shared memory.");
                }
                else
                {
                    int rpm = (int)Math.Round(selected.Value);
                    WriteAtomic(rpmPath, rpm.ToString(CultureInfo.InvariantCulture));
                    WriteAtomic(statusPath, $"OK: {rpm} RPM from '{selected.Sensor}' / '{selected.Label}'.");
                }
            }
            catch (Exception ex)
            {
                WriteAtomic(statusPath, "ERROR: " + ex.Message);
            }
            Thread.Sleep(1000);
        }
    }

    private static int WatchLhm(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        string jsonPath = Path.Combine(outputDirectory, "CpuTempFanBridge.json");
        string rpmPath = Path.Combine(outputDirectory, "CpuTempFanBridge.rpm");
        string statusPath = Path.Combine(outputDirectory, "CpuTempFanBridge.status");
        var computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMotherboardEnabled = true,
            IsControllerEnabled = true
        };

        try
        {
            computer.Open();
            while (true)
            {
                try
                {
                    var readings = new List<LhmReading>();
                    foreach (var hardware in computer.Hardware) CollectHardware(hardware, readings);
                    var snapshot = BuildStandaloneSnapshot(readings, outputDirectory);
                    WriteAtomic(jsonPath, JsonSerializer.Serialize(snapshot));
                    if (snapshot.CpuFanRpm.HasValue)
                        WriteAtomic(rpmPath, snapshot.CpuFanRpm.Value.ToString(CultureInfo.InvariantCulture));
                    WriteAtomic(statusPath, snapshot.CpuFanRpm.HasValue
                        ? $"OK: {snapshot.CpuFanRpm} RPM from LibreHardwareMonitor / IT8696E; CPU {snapshot.CpuClockMhz ?? 0} MHz."
                        : "ERROR: IT8696E CPU fan sensor was not found. Run the bridge elevated and verify PawnIO.");
                }
                catch (Exception ex) { WriteAtomic(statusPath, "ERROR: " + ex.Message); }
                Thread.Sleep(1000);
            }
        }
        finally { computer.Close(); }
    }

    private sealed record StandaloneSnapshot(int? CpuFanRpm, int? CpuClockMhz, string? GpuName, int? GpuClockMhz, int? GpuFan1Rpm, int? GpuFan2Rpm);
    private sealed record BridgeConfig(string? PreferredGpu);

    private static StandaloneSnapshot BuildStandaloneSnapshot(List<LhmReading> readings, string outputDirectory)
    {
        BridgeConfig config = ReadConfig(outputDirectory);
        var gpu = readings
            .Where(r => r.HardwareType.StartsWith("Gpu", StringComparison.OrdinalIgnoreCase))
            .GroupBy(r => new { r.HardwareType, r.HardwareName })
            .OrderByDescending(group => GpuScore(group.Key.HardwareType, group.Key.HardwareName, group, config.PreferredGpu))
            .FirstOrDefault();
        var gpuClock = gpu?.FirstOrDefault(r => r.SensorType.Equals("Clock", StringComparison.OrdinalIgnoreCase)
                                                && r.SensorName.Equals("GPU Core", StringComparison.OrdinalIgnoreCase));
        var gpuFans = gpu?.Where(r => r.SensorType.Equals("Fan", StringComparison.OrdinalIgnoreCase))
            .OrderBy(r => r.Identifier, StringComparer.OrdinalIgnoreCase).Take(2).ToArray() ?? Array.Empty<LhmReading>();
        var cpuFan = readings.FirstOrDefault(r => r.Identifier.Equals("/lpc/it8696e/0/fan/0", StringComparison.OrdinalIgnoreCase))
            ?? readings.FirstOrDefault(r => r.SensorType.Equals("Fan", StringComparison.OrdinalIgnoreCase)
                                            && r.SensorName.Contains("CPU", StringComparison.OrdinalIgnoreCase));
        var cpuClock = readings.FirstOrDefault(r => r.Identifier.Equals("/amdcpu/0/clock/1", StringComparison.OrdinalIgnoreCase))
            ?? readings.FirstOrDefault(r => r.HardwareType.Contains("Cpu", StringComparison.OrdinalIgnoreCase)
                                            && r.SensorType.Equals("Clock", StringComparison.OrdinalIgnoreCase)
                                            && r.SensorName.Contains("Average", StringComparison.OrdinalIgnoreCase));
        return new StandaloneSnapshot(
            cpuFan is null ? null : (int)Math.Round(cpuFan.Value),
            cpuClock is null ? null : (int)Math.Round(cpuClock.Value),
            gpu?.Key.HardwareName,
            gpuClock is null ? null : (int)Math.Round(gpuClock.Value),
            gpuFans.Length > 0 ? (int)Math.Round(gpuFans[0].Value) : null,
            gpuFans.Length > 1 ? (int)Math.Round(gpuFans[1].Value) : null);
    }

    private static int GpuScore(string hardwareType, string hardwareName, IEnumerable<LhmReading> readings, string? preferredGpu)
    {
        int score = readings.Any(r => r.SensorType.Equals("Fan", StringComparison.OrdinalIgnoreCase)) ? 1000 : 0;
        if (!string.IsNullOrWhiteSpace(preferredGpu) && hardwareName.Contains(preferredGpu, StringComparison.OrdinalIgnoreCase)) score += 10000;
        if (hardwareType.Equals("GpuNvidia", StringComparison.OrdinalIgnoreCase)) score += 30;
        else if (hardwareType.Equals("GpuAmd", StringComparison.OrdinalIgnoreCase)) score += 20;
        else if (hardwareType.Equals("GpuIntel", StringComparison.OrdinalIgnoreCase)) score += 10;
        if (hardwareName.Contains("(TM) Graphics", StringComparison.OrdinalIgnoreCase)) score -= 100;
        return score;
    }

    private static BridgeConfig ReadConfig(string outputDirectory)
    {
        string path = Path.Combine(outputDirectory, "CpuTempFanBridge.config.json");
        if (!File.Exists(path)) return new BridgeConfig(null);
        try { return JsonSerializer.Deserialize<BridgeConfig>(File.ReadAllText(path)) ?? new BridgeConfig(null); }
        catch { return new BridgeConfig(null); }
    }

    private static bool IsProcessRunning(int processId)
    {
        try { return !Process.GetProcessById(processId).HasExited; }
        catch (ArgumentException) { return false; }
    }

    private static List<LhmReading> ReadLhmSnapshot()
    {
        var result = new List<LhmReading>();
        var computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMotherboardEnabled = true,
            IsControllerEnabled = true
        };
        try
        {
            computer.Open();
            foreach (var hardware in computer.Hardware)
                CollectHardware(hardware, result);
        }
        finally { computer.Close(); }
        return result;
    }

    private static void CollectHardware(IHardware hardware, List<LhmReading> result)
    {
        hardware.Update();
        foreach (var sensor in hardware.Sensors)
        {
            if (sensor.Value.HasValue)
                result.Add(new LhmReading(hardware.HardwareType.ToString(), hardware.Name,
                    sensor.SensorType.ToString(), sensor.Name, sensor.Value.Value, sensor.Identifier.ToString()));
        }
        foreach (var child in hardware.SubHardware)
            CollectHardware(child, result);
    }

    private static Reading? SelectCpuFan(IEnumerable<Reading> readings)
    {
        var rpm = readings.Where(r => r.Unit.Equals("RPM", StringComparison.OrdinalIgnoreCase) && r.Value >= 0).ToList();
        return rpm.FirstOrDefault(r => r.Label.Equals("CPU", StringComparison.OrdinalIgnoreCase))
            ?? rpm.FirstOrDefault(r => r.Label.Equals("CPU Fan", StringComparison.OrdinalIgnoreCase))
            ?? rpm.FirstOrDefault(r => r.Label.Contains("CPU", StringComparison.OrdinalIgnoreCase)
                                     && r.Label.Contains("Fan", StringComparison.OrdinalIgnoreCase))
            ?? rpm.FirstOrDefault(r => r.Label.Contains("CPU", StringComparison.OrdinalIgnoreCase));
    }

    private static List<Reading> ReadSnapshot()
    {
        Mutex? mutex = null;
        bool locked = false;
        try
        {
            try { mutex = Mutex.OpenExisting(MutexName); }
            catch (WaitHandleCannotBeOpenedException) { }
            if (mutex is not null)
            {
                locked = mutex.WaitOne(2000);
                if (!locked) throw new TimeoutException("Timed out waiting for the HWiNFO shared-memory mutex.");
            }

            using var map = MemoryMappedFile.OpenExisting(MapName, MemoryMappedFileRights.Read);
            using var view = map.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read);
            if (view.ReadUInt32(0) != ActiveSignature)
                throw new InvalidDataException("HWiNFO shared memory exists but is not active.");

            uint sensorOffset = view.ReadUInt32(20);
            uint sensorSize = view.ReadUInt32(24);
            uint sensorCount = view.ReadUInt32(28);
            uint readingOffset = view.ReadUInt32(32);
            uint readingSize = view.ReadUInt32(36);
            uint readingCount = view.ReadUInt32(40);

            if (sensorSize < 264 || readingSize < 316 || sensorCount > 10000 || readingCount > 100000)
                throw new InvalidDataException("Unexpected HWiNFO shared-memory layout.");

            var sensors = new Dictionary<uint, string>();
            for (uint i = 0; i < sensorCount; i++)
            {
                long pos = sensorOffset + (long)sensorSize * i;
                string original = ReadCString(view, pos + 8, 128);
                string user = ReadCString(view, pos + 136, 128);
                sensors[i] = string.IsNullOrWhiteSpace(user) ? original : user;
            }

            var result = new List<Reading>((int)Math.Min(readingCount, int.MaxValue));
            for (uint i = 0; i < readingCount; i++)
            {
                long pos = readingOffset + (long)readingSize * i;
                uint sensorIndex = view.ReadUInt32(pos + 4);
                string labelOriginal = ReadCString(view, pos + 12, 128);
                string labelUser = ReadCString(view, pos + 140, 128);
                string unit = ReadCString(view, pos + 268, 16);
                double value = view.ReadDouble(pos + 284);
                string label = string.IsNullOrWhiteSpace(labelUser) ? labelOriginal : labelUser;
                sensors.TryGetValue(sensorIndex, out string? sensor);
                result.Add(new Reading(sensor ?? $"Sensor {sensorIndex}", label, unit, value));
            }
            return result;
        }
        finally
        {
            if (locked) mutex!.ReleaseMutex();
            mutex?.Dispose();
        }
    }

    private static string ReadCString(MemoryMappedViewAccessor view, long offset, int length)
    {
        var bytes = new byte[length];
        view.ReadArray(offset, bytes, 0, length);
        int end = Array.IndexOf(bytes, (byte)0);
        if (end < 0) end = bytes.Length;
        return Encoding.UTF8.GetString(bytes, 0, end).Trim();
    }

    private static void WriteAtomic(string path, string contents)
    {
        string temp = path + ".tmp";
        File.WriteAllText(temp, contents + Environment.NewLine, new UTF8Encoding(false));
        File.Move(temp, path, true);
    }
}
