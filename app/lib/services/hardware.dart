import 'dart:io';

/// What this computer has. Detected with standard OS tools, no extra installs.
class Hardware {
  Hardware({
    required this.os,
    required this.cpu,
    required this.cores,
    required this.ramGb,
    required this.gpu,
    required this.vramGb,
    required this.unifiedMemory,
    required this.freeDiskGb,
  });

  final String os, cpu, gpu;
  final int cores;
  final double ramGb, freeDiskGb;

  /// Dedicated GPU memory (NVIDIA/AMD). 0 when none or unknown.
  final double vramGb;

  /// Apple Silicon: GPU shares system memory.
  final bool unifiedMemory;

  /// Memory a model may use, following the plan's sizing rules:
  /// ≤85 % of VRAM, ≤70 % of unified memory, ≤60 % of RAM for CPU-only.
  /// 1.5 GB is kept back for speech engines.
  double get modelBudgetGb {
    final b = vramGb >= 4
        ? vramGb * .85
        : unifiedMemory
            ? ramGb * .70
            : ramGb * .60;
    return (b - 1.5).clamp(0, double.infinity).toDouble();
  }

  String get accel => vramGb >= 4
      ? 'GPU · ${vramGb.toStringAsFixed(0)} GB'
      : unifiedMemory
          ? 'GPU (Metal) · shared memory'
          : 'CPU only';

  static Future<Hardware> detect() async {
    try {
      if (Platform.isMacOS) return await _mac();
      if (Platform.isLinux) return await _linux();
      if (Platform.isWindows) return await _windows();
    } catch (_) {
      // Fall through to a safe minimal answer.
    }
    return Hardware(
      os: Platform.operatingSystem,
      cpu: 'Unknown processor',
      cores: Platform.numberOfProcessors,
      ramGb: 0,
      gpu: 'Unknown',
      vramGb: 0,
      unifiedMemory: false,
      freeDiskGb: 0,
    );
  }

  static Future<String> _out(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args);
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<double> _freeDiskUnix() async {
    final df = await _out('df', ['-k', Platform.environment['HOME'] ?? '/']);
    final lines = df.split('\n');
    if (lines.length < 2) return 0;
    final cols = lines[1].split(RegExp(r'\s+'));
    return cols.length > 3 ? (double.tryParse(cols[3]) ?? 0) / 1024 / 1024 : 0;
  }

  static Future<(String, double)> _nvidia() async {
    final s = await _out('nvidia-smi', ['--query-gpu=name,memory.total', '--format=csv,noheader,nounits']);
    if (s.isEmpty) return ('', 0.0);
    final parts = s.split('\n').first.split(',');
    return (parts[0].trim(), (double.tryParse(parts.last.trim()) ?? 0) / 1024);
  }

  static Future<Hardware> _mac() async {
    final cpu = await _out('sysctl', ['-n', 'machdep.cpu.brand_string']);
    final mem = double.tryParse(await _out('sysctl', ['-n', 'hw.memsize'])) ?? 0;
    final arm = (await _out('uname', ['-m'])) == 'arm64';
    return Hardware(
      os: 'macOS ${await _out('sw_vers', ['-productVersion'])}',
      cpu: cpu.isEmpty ? 'Mac' : cpu,
      cores: Platform.numberOfProcessors,
      ramGb: mem / 1073741824,
      gpu: arm ? '${cpu.isEmpty ? 'Apple' : cpu} GPU · Metal' : 'Integrated',
      vramGb: 0,
      unifiedMemory: arm,
      freeDiskGb: await _freeDiskUnix(),
    );
  }

  static Future<Hardware> _linux() async {
    final info = await File('/proc/cpuinfo').readAsString().catchError((_) => '');
    final cpu = RegExp(r'model name\s*:\s*(.+)').firstMatch(info)?.group(1) ?? 'Linux CPU';
    final meminfo = await File('/proc/meminfo').readAsString().catchError((_) => '');
    final kb = double.tryParse(RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo)?.group(1) ?? '') ?? 0;
    final (gpu, vram) = await _nvidia();
    return Hardware(
      os: 'Linux',
      cpu: cpu,
      cores: Platform.numberOfProcessors,
      ramGb: kb / 1048576,
      gpu: gpu.isEmpty ? 'No dedicated GPU found' : gpu,
      vramGb: vram,
      unifiedMemory: false,
      freeDiskGb: await _freeDiskUnix(),
    );
  }

  static Future<Hardware> _windows() async {
    Future<String> ps(String q) => _out('powershell', ['-NoProfile', '-Command', q]);
    final cpu = await ps('(Get-CimInstance Win32_Processor | Select-Object -First 1).Name');
    final mem = double.tryParse(await ps('(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory')) ?? 0;
    final free = double.tryParse(await ps("(Get-PSDrive C).Free")) ?? 0;
    var (gpu, vram) = await _nvidia();
    if (gpu.isEmpty) gpu = await ps('(Get-CimInstance Win32_VideoController | Select-Object -First 1).Name');
    return Hardware(
      os: 'Windows',
      cpu: cpu.isEmpty ? 'Windows PC' : cpu,
      cores: Platform.numberOfProcessors,
      ramGb: mem / 1073741824,
      gpu: gpu.isEmpty ? 'Unknown' : gpu,
      vramGb: vram,
      unifiedMemory: false,
      freeDiskGb: free / 1073741824,
    );
  }
}
