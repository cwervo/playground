/// Data models mirroring the JSON produced by the C control plane.
library;

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String _str(dynamic v) => v?.toString() ?? '';

class PlatformStatus {
  final String version;
  final String arch;
  final int uptimeMs;
  final int isolates;
  final int requests;
  final int errors;
  final int inflight;
  final int contextSwitches;
  final int fibersTotal;
  final int fibersDone;
  final int connections;
  final int connectionsTotal;
  final int sliceInstructions;
  final int fiberStackBytes;
  final int defaultCpuLimit;
  final int defaultMemLimit;
  final bool persistence;
  final int pid;

  PlatformStatus.fromJson(Map<String, dynamic> j)
      : version = _str(j['version']),
        arch = _str(j['arch']),
        uptimeMs = _int(j['uptime_ms']),
        isolates = _int(j['isolates']),
        requests = _int(j['requests']),
        errors = _int(j['errors']),
        inflight = _int(j['inflight']),
        contextSwitches = _int(j['context_switches']),
        fibersTotal = _int(j['fibers_total']),
        fibersDone = _int(j['fibers_done']),
        connections = _int(j['connections']),
        connectionsTotal = _int(j['connections_total']),
        sliceInstructions = _int(j['slice_instructions']),
        fiberStackBytes = _int(j['fiber_stack_bytes']),
        defaultCpuLimit = _int(j['default_cpu_limit']),
        defaultMemLimit = _int(j['default_mem_limit']),
        persistence = j['persistence'] == true,
        pid = _int(j['pid']);
}

class WorkerSummary {
  final String name;
  final int createdMs;
  final int deployedMs;
  final int deploys;
  final int instructionsInScript;
  final int constants;
  final int scriptBytes;
  final int cpuLimit;
  final int memLimit;
  final int requests;
  final int errors;
  final int instructions;
  final int cpuNs;
  final int maxCpuNs;
  final int lastInvokedMs;
  final int peakMem;
  final int inflight;
  final int kvEntries;
  final int envCount;
  final List<int> rps;

  WorkerSummary.fromJson(Map<String, dynamic> j)
      : name = _str(j['name']),
        createdMs = _int(j['created_ms']),
        deployedMs = _int(j['deployed_ms']),
        deploys = _int(j['deploys']),
        instructionsInScript = _int(j['instructions_in_script']),
        constants = _int(j['constants']),
        scriptBytes = _int(j['script_bytes']),
        cpuLimit = _int(j['cpu_limit']),
        memLimit = _int(j['mem_limit']),
        requests = _int(j['requests']),
        errors = _int(j['errors']),
        instructions = _int(j['instructions']),
        cpuNs = _int(j['cpu_ns']),
        maxCpuNs = _int(j['max_cpu_ns']),
        lastInvokedMs = _int(j['last_invoked_ms']),
        peakMem = _int(j['peak_mem']),
        inflight = _int(j['inflight']),
        kvEntries = _int(j['kv_entries']),
        envCount = _int(j['env_count']),
        rps = ((j['rps'] as List?) ?? const []).map(_int).toList();

  double get avgCpuUs => requests == 0 ? 0 : cpuNs / requests / 1000;
  double get errorRate => requests == 0 ? 0 : errors / requests;
  int get requestsLastMinute => rps.fold(0, (a, b) => a + b);
}

class WorkerDetail extends WorkerSummary {
  final String script;
  final Map<String, String> env;

  WorkerDetail.fromJson(super.j)
      : script = _str(j['script']),
        env = ((j['env'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        super.fromJson();
}

class LogEntry {
  final int tsMs;
  final String msg;
  LogEntry.fromJson(Map<String, dynamic> j)
      : tsMs = _int(j['ts_ms']),
        msg = _str(j['msg']);
  bool get isError => msg.startsWith('error ');
}

class KvEntry {
  final String key;
  final String value;
  final int updatedMs;
  KvEntry.fromJson(Map<String, dynamic> j)
      : key = _str(j['key']),
        value = _str(j['value']),
        updatedMs = _int(j['updated_ms']);
}

class InvokeResult {
  final int status;
  final Map<String, String> headers;
  final String body;
  final int errorCode;
  final String error;
  final int instructions;
  final int cpuUs;
  final int wallUs;
  final int memPeak;
  final int memLimit;
  final int cpuLimit;
  final int switches;

  InvokeResult.fromJson(Map<String, dynamic> j)
      : status = _int(j['status']),
        headers = ((j['headers'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        body = _str(j['body']),
        errorCode = _int(j['error_code']),
        error = _str(j['error']),
        instructions = _int(j['instructions']),
        cpuUs = _int(j['cpu_us']),
        wallUs = _int(j['wall_us']),
        memPeak = _int(j['mem_peak']),
        memLimit = _int(j['mem_limit']),
        cpuLimit = _int(j['cpu_limit']),
        switches = _int(j['switches']);

  bool get ok => errorCode == 0;
}

class DisasmLine {
  final int pc;
  final String text;
  DisasmLine.fromJson(Map<String, dynamic> j)
      : pc = _int(j['pc']),
        text = _str(j['text']);
}

class AssembleResult {
  final bool ok;
  final String error;
  final List<DisasmLine> listing;
  final int instructions;
  final int constants;

  AssembleResult.fromJson(Map<String, dynamic> j)
      : ok = j['ok'] == true,
        error = _str(j['error']),
        listing = (((j['disasm'] as Map?)?['listing'] as List?) ?? const [])
            .map((e) => DisasmLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        instructions = _int((j['disasm'] as Map?)?['instructions']),
        constants = _int((j['disasm'] as Map?)?['constants']);
}

class ExampleScript {
  final String name;
  final String description;
  final String script;
  ExampleScript.fromJson(Map<String, dynamic> j)
      : name = _str(j['name']),
        description = _str(j['description']),
        script = _str(j['script']);
}

class InstructionDoc {
  final String name;
  final String operand;
  final String desc;
  InstructionDoc.fromJson(Map<String, dynamic> j)
      : name = _str(j['name']),
        operand = _str(j['operand']),
        desc = _str(j['desc']);
  bool get isHostCall => name.contains('.') ||
      const {'log', 'time', 'yield', 'env', 'rand', 'worker', 'spin'}.contains(name);
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'HTTP $status: $message';
}
