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
}
